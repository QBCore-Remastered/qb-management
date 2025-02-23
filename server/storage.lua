local config = require 'config.server'

local function createActivityTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `player_jobs_activity` (
            `id` int UNSIGNED NOT NULL AUTO_INCREMENT,
            `citizenid` VARCHAR(50) COLLATE utf8mb4_unicode_ci,
            `job` varchar(255) NOT NULL,
            `last_checkin` int NOT NULL,
            `last_checkout` int NULL DEFAULT NULL,
            FOREIGN KEY (`citizenid`) REFERENCES `players` (`citizenid`) ON DELETE CASCADE,
            PRIMARY KEY (`id`) USING BTREE,
            INDEX `id` (`id` DESC) USING BTREE,
            INDEX `last_checkout` (`last_checkout` ASC) USING BTREE,
            INDEX `citizenid_job` (`citizenid`, `job`) USING BTREE
        ) ENGINE = InnoDB AUTO_INCREMENT = 1 CHARACTER SET = utf8mb4 COLLATE = utf8mb4_general_ci;
    ]])
end

local function cleanupActivity()
    MySQL.query('DELETE FROM `player_jobs_activity` WHERE `last_checkout` < UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 31 DAY)) OR `last_checkout` IS NULL')
end

local function onPlayerCheckOut(clockInPayload)
    local checkOutTime = os.time()
    local checkInTime = clockInPayload.time
    if (checkOutTime - checkInTime) / 60 < config.minOnDutyLogTimeMinutes then
        return
    end

    MySQL.insert("INSERT INTO `player_jobs_activity` (`citizenid`, `job`, `last_checkin`, `last_checkout`) VALUES (?, ?, ?, ?)", {
        clockInPayload.citizenid,
        clockInPayload.job,
        checkInTime,
        checkOutTime,
    })
end

---@param citizenid string
---@param job string
---@return table?
local function getPlayerActivityData(citizenid, job)
    local result = MySQL.single.await('SELECT `last_checkin`, ROUND(COALESCE(SUM(last_checkout-last_checkin) / 3600, 0), 2) AS `hours` FROM `player_jobs_activity` WHERE `citizenid` = ? AND `job` = ? GROUP BY `citizenid`', { citizenid, job })
    return { hours = result?.hours or 0, last_checkin = result?.last_checkin and os.date(config.formatDateTime, result?.last_checkin) or 'N/A' }
end

local function createGroupsTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `management_groups` (
            `name` varchar(255) NOT NULL UNIQUE,
            `type` varchar(10) NOT NULL,
            `label` varchar(255) NOT NULL,
            `defaultDuty` tinyint(1) DEFAULT 1,
            `offDutyPay` tinyint(1) DEFAULT 0,
            `grades` LONGTEXT DEFAULT NULL,
            PRIMARY KEY (`name`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

---Update / insert group data
---@param name string
---@param groupType GroupType
---@param data Job|Gang
local function updateGroup(name, groupType, data)
    MySQL.query([[
        INSERT INTO `management_groups` (name, type, label, defaultDuty, offDutyPay, grades)
            VALUES (@name, @type, @label, @defaultDuty, @offDutyPay, @grades)
        ON DUPLICATE KEY UPDATE
            `type` = @type, `label` = @label, `defaultDuty` = @defaultDuty, `offDutyPay` = @offDutyPay, `grades` = @grades
    ]], {
        name = name,
        type = groupType,
        label = data.label,
        defaultDuty = data.defaultDuty,
        offDutyPay = data.offDutyPay,
        grades = data.grades and json.encode(data.grades),
    })
end

local function convertGrades(gangJson)
    local _grades = json.decode(gangJson)
    local grades = {}
    for k, v in pairs(_grades) do
        grades[tonumber(("%d"):format(k))] = v
    end
    return grades
end

---Fetch job data
---@return table<string, Job>
local function fetchJobs()
    local results = MySQL.query.await("SELECT * FROM `management_groups` WHERE `type` = 'job'")
    local jobData = {}

    for i = 1, #results do
        jobData[results[i].name] = {
            label = results[i].label,
            type = results[i].type,
            defaultDuty = results[i].defaultDuty == 1,
            offDutyPay = results[i].offDutyPay == 1,
            grades = results[i].grades and convertGrades(results[i].grades) or {},
        }
    end

    return jobData
end

---Fetch gang data
---@return table<string, Gang>
local function fetchGangs()
    local results = MySQL.query.await("SELECT * FROM `management_groups` WHERE `type` = 'gang'")
    local gangData = {}

    for i = 1, #results do
        gangData[results[i].name] = {
            label = results[i].label,
            grades = results[i].grades and convertGrades(results[i].grades) or {},
        }
    end

    return gangData
end

return {
    createActivityTable = createActivityTable,
    cleanupActivity = cleanupActivity,
    onPlayerCheckOut = onPlayerCheckOut,
    getPlayerActivityData = getPlayerActivityData,
    createGroupsTable = createGroupsTable,
    updateGroup = updateGroup,
    fetchJobs = fetchJobs,
    fetchGangs = fetchGangs,
}
