lib.versionCheck('Qbox-project/qbx_management')
if not lib.checkDependency('qbx_core', '1.18.0', true) then error() return end
if not lib.checkDependency('ox_lib', '3.13.0', true) then error() return end

local config = require 'config.server'
local logger = require '@qbx_core.modules.logger'
local JOBS = exports.qbx_core:GetJobs()
local GANGS = exports.qbx_core:GetGangs()
local playersClockedIn = {}
local menus = {}

for groupName, menuInfo in pairs(config.menus) do
    ---@diagnostic disable-next-line: inject-field
	menuInfo.groupName = groupName
	menus[#menus + 1] = menuInfo
end

local function getMenuEntries(groupName, groupType)
	local menuEntries = {}

    local groupEntries = exports.qbx_core:GetGroupMembers(groupName, groupType)
    for i = 1, #groupEntries do
        local citizenid = groupEntries[i].citizenid
        local grade = groupEntries[i].grade
        local player = exports.qbx_core:GetPlayerByCitizenId(citizenid) or exports.qbx_core:GetOfflinePlayer(citizenid)
        local namePrefix = player.Offline and '❌ ' or '🟢 '
		local playerActivityData = groupType == 'job' and GetPlayerActivityData(citizenid, groupName) or nil
        menuEntries[#menuEntries + 1] = {
            cid = citizenid,
			grade = grade,
			name = namePrefix..player.PlayerData.charinfo.firstname..' '..player.PlayerData.charinfo.lastname,
			hours = playerActivityData?.hours,
			last_checkin = playerActivityData?.last_checkin
        }
    end

	return menuEntries
end

-- Get a list of employees for a given group.
---@param groupName string Name of job/gang to get employees of
---@param groupType GroupType
---@return table?
lib.callback.register('qbx_management:server:getEmployees', function(source, groupName, groupType)
	local player = exports.qbx_core:GetPlayer(source)
	if not player.PlayerData[groupType].isboss then return end

	local menuEntries = getMenuEntries(groupName, groupType)
    table.sort(menuEntries, function(a, b)
		return a.grade > b.grade
	end)

	return menuEntries
end)

-- Callback for updating the grade information of online players
---@param source number
---@param citizenId string CitizenId of player who is being promoted/demoted
---@param oldGrade integer Old grade number of target employee
---@param newGrade integer New grade number of target employee
---@param groupType GroupType
lib.callback.register('qbx_management:server:updateGrade', function(source, citizenId, oldGrade, newGrade, groupType)
	local player = exports.qbx_core:GetPlayer(source)
	local employee = exports.qbx_core:GetPlayerByCitizenId(citizenId)
	local jobName = player.PlayerData[groupType].name
	local gradeLevel = player.PlayerData[groupType].grade.level

	if not player.PlayerData[groupType].isboss then return end

	if player.PlayerData.citizenid == citizenId then
		exports.qbx_core:Notify(source, locale('error.cant_promote_self'), 'error')
		return
	end

	if oldGrade >= gradeLevel or newGrade >= gradeLevel then
		exports.qbx_core:Notify(source, locale('error.cant_promote'), 'error')
		return
	end

    if groupType == 'job' then
        local success, errorResult = exports.qbx_core:AddPlayerToJob(citizenId, jobName, newGrade)
		assert(success, errorResult.message)
    else
        local success, errorResult = exports.qbx_core:AddPlayerToGang(citizenId, jobName, newGrade)
		assert(success, errorResult.message)
    end

    if employee then
	    local gradeName = groupType == 'gang' and GANGS[jobName].grades[newGrade].name or JOBS[jobName].grades[newGrade].name
        exports.qbx_core:Notify(employee.PlayerData.source, locale('success.promoted_to')..gradeName..'.', 'success')
    end
    exports.qbx_core:Notify(source, locale('success.promoted'), 'success')
end)

-- Callback to hire online player as employee of a given group
---@param employee integer Server ID of target employee to be hired
---@param groupType GroupType
lib.callback.register('qbx_management:server:hireEmployee', function(source, employee, groupType)
	local player = exports.qbx_core:GetPlayer(source)
	local target = exports.qbx_core:GetPlayer(employee)

    if not player.PlayerData[groupType].isboss then return end

    if not target then
        exports.qbx_core:Notify(source, locale('error.not_around'), 'error')
        return
    end

	local groupName = player.PlayerData[groupType].name
	local logArea = groupType == 'gang' and 'Gang' or 'Boss'

    if groupType == 'job' then
        local success, errorResult = exports.qbx_core:AddPlayerToJob(target.PlayerData.citizenid, groupName, 0)
		assert(success, errorResult.message)
        success, errorResult = exports.qbx_core:SetPlayerPrimaryJob(target.PlayerData.citizenid, groupName)
		assert(success, errorResult.message)
    else
        local success, errorResult = exports.qbx_core:AddPlayerToGang(target.PlayerData.citizenid, groupName, 0)
		assert(success, errorResult.message)
        success, errorResult = exports.qbx_core:SetPlayerPrimaryGang(target.PlayerData.citizenid, groupName)
		assert(success, errorResult.message)
    end

    local playerFullName = player.PlayerData.charinfo.firstname..' '..player.PlayerData.charinfo.lastname
    local targetFullName = target.PlayerData.charinfo.firstname..' '..target.PlayerData.charinfo.lastname
    local organizationLabel = player.PlayerData[groupType].label
    exports.qbx_core:Notify(source, locale('success.hired_into', targetFullName, organizationLabel), 'success')
    exports.qbx_core:Notify(target.PlayerData.source, locale('success.hired_to')..organizationLabel, 'success')
    logger.log({source = 'qbx_management', event = 'hireEmployee', message = string.format('%s | %s hired %s into %s at grade %s', logArea, playerFullName, targetFullName, organizationLabel, 0), webhook = config.discordWebhook})
end)

-- Returns playerdata for a given table of player server ids.
---@param closePlayers table Table of player data for possible hiring
---@return table
lib.callback.register('qbx_management:server:getPlayers', function(_, closePlayers)
	local players = {}
	for _, v in pairs(closePlayers) do
		local player = exports.qbx_core:GetPlayer(v.id)
		players[#players + 1] = {
			id = v.id,
			name = player.PlayerData.charinfo.firstname..' '..player.PlayerData.charinfo.lastname,
			citizenid = player.PlayerData.citizenid,
			job = player.PlayerData.job,
			gang = player.PlayerData.gang,
			source = player.PlayerData.source
		}
	end

	table.sort(players, function(a, b)
		return a.name < b.name
	end)

	return players
end)


---@param employeeCitizenId string
---@diagnostic disable-next-line: undefined-doc-name
---@param boss Player | table
---@param groupName string
---@param groupType GroupType
---@return boolean success
local function fireEmployee(employeeCitizenId, boss, groupName, groupType)
    local employee = exports.qbx_core:GetPlayerByCitizenId(employeeCitizenId) or exports.qbx_core:GetOfflinePlayer(employeeCitizenId)
    if employee.PlayerData.citizenid == boss.PlayerData.citizenid then
		local message = groupType == 'gang' and locale('error.kick_yourself') or locale('error.fire_yourself')
		exports.qbx_core:Notify(boss.PlayerData.source, message, 'error')
		return false
	end
    if not employee then
		exports.qbx_core:Notify(boss.PlayerData.source, locale('error.person_doesnt_exist'), 'error')
		return false
	end

    local employeeGrade = groupType == 'job' and employee.PlayerData.jobs?[groupName] or employee.PlayerData.gangs?[groupName]
    local bossGrade = groupType == 'job' and boss.PlayerData.jobs?[groupName] or boss.PlayerData.gangs?[groupName]
    if employeeGrade >= bossGrade then
		exports.qbx_core:Notify(boss.PlayerData.source, locale('error.fire_boss'), 'error')
		return false
	end

	if groupType == 'job' then
        local success, errorResult = exports.qbx_core:RemovePlayerFromJob(employee.PlayerData.citizenid, groupName)
		assert(success, errorResult.message)
	else
        local success, errorResult = exports.qbx_core:RemovePlayerFromGang(employee.PlayerData.citizenid, groupName)
		assert(success, errorResult.message)
	end

    if not employee.Offline then
        local message = groupType == 'gang' and locale('error.you_gang_fired', GANGS[groupName].label) or locale('error.you_job_fired', JOBS[groupName].label)
		exports.qbx_core:Notify(employee.PlayerData.source, message, 'error')
    end

    return true
end

-- Callback for firing a player from a given society.
---@param employee string citizenid of employee to be fired
---@param groupType GroupType
lib.callback.register('qbx_management:server:fireEmployee', function(source, employee, groupType)
	local player = exports.qbx_core:GetPlayer(source)
	local firedEmployee = exports.qbx_core:GetPlayerByCitizenId(employee) or exports.qbx_core:GetOfflinePlayer(employee)
	local playerFullName = player.PlayerData.charinfo.firstname..' '..player.PlayerData.charinfo.lastname
	local organizationLabel = player.PlayerData[groupType].label

	if not player.PlayerData[groupType].isboss then return end
    if not firedEmployee then lib.print.error("not able to find player with citizenid", employee) return end
    local success = fireEmployee(employee, player, player.PlayerData[groupType].name, groupType)
    local employeeFullName = firedEmployee.PlayerData.charinfo.firstname..' '..firedEmployee.PlayerData.charinfo.lastname

	if success then
		local logArea = groupType == 'gang' and 'Gang' or 'Boss'
		local logType = groupType == 'gang' and locale('error.gang_fired') or locale('error.job_fired')
		exports.qbx_core:Notify(source, logType, 'success')
		logger.log({source = 'qbx_management', event = 'fireEmployee', message = string.format('%s | %s fired %s from %s', logArea, playerFullName, employeeFullName, organizationLabel), webhook = config.discordWebhook})
	else
		exports.qbx_core:Notify(source, locale('error.unable_fire'), 'error')
	end
end)

-- Callback for giving a player a bonus from a given society.
---@param employee string citizenid of employee to get the bonus
---@param groupType GroupType
---@param groupName string
---@param amount number
lib.callback.register('qbx_management:server:bonusEmployee', function(source, employee, groupType, groupName, amount)
	local player = exports.qbx_core:GetPlayer(source)
	local bonusEmployee = exports.qbx_core:GetPlayerByCitizenId(employee) or exports.qbx_core:GetOfflinePlayer(employee)
	local playerFullName = player.PlayerData.charinfo.firstname..' '..player.PlayerData.charinfo.lastname
	local organizationLabel = player.PlayerData[groupType].label
	local societyAccount = config.getSocietyAccount(groupName)

	if not player.PlayerData[groupType].isboss then return end
	if not bonusEmployee then lib.print.error("not able to find player with citizenid", employee) return end
	if not amount or tonumber(amount) <= 0 then exports.qbx_core:Notify(source, locale('error.invalid_amount'), 'error') return end
	if not societyAccount or societyAccount < tonumber(amount) then exports.qbx_core:Notify(source, locale('error.invalid_balance'), 'error') return end
	local employeeFullName = bonusEmployee.PlayerData.charinfo.firstname..' '..bonusEmployee.PlayerData.charinfo.lastname

	config.removeSocietyMoney(groupName, tonumber(amount))
	bonusEmployee.Functions.AddMoney('bank', tonumber(amount), 'society-bonus')
	bonusEmployee.Functions.Save()

	exports.qbx_core:Notify(source, locale('success.amount_send', amount, employeeFullName), 'success')
	logger.log({source = 'qbx_management', event = 'bonusEmployee', message = string.format('%s | %s gave a bonus to %s from account %s with amount %s', 'Boss', playerFullName, employeeFullName, organizationLabel, amount), webhook = config.discordWebhook})
end)

lib.callback.register('qbx_management:server:getBossMenus', function()
	return menus
end)

---Creates a boss zone for the specified group
---@param menuInfo MenuInfo
local function registerBossMenu(menuInfo)
    menus[#menus + 1] = menuInfo
	TriggerClientEvent('qbx_management:client:bossMenuRegistered', -1, menuInfo)
end

exports('RegisterBossMenu', registerBossMenu)

---@param source number
---@param citizenid string
---@param job string
local function doPlayerCheckIn(source, citizenid, job)
	playersClockedIn[source] = { citizenid = citizenid, job = job }
	OnPlayerCheckIn(citizenid, job)
end

---@param source number
local function onPlayerUnload(source)
	if playersClockedIn[source] then
        OnPlayerCheckOut(playersClockedIn[source].citizenid)
		playersClockedIn[source] = nil
    end
end

---@param source number
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local player = exports.qbx_core:GetPlayer(source)
	if player == nil then return end
	if player.PlayerData.job.onduty then
		doPlayerCheckIn(player.PlayerData.source, player.PlayerData.citizenid, player.PlayerData.job.name)
	end
end)

---@param source number
---@param groupName string
---@param groupGrade number
AddEventHandler('qbx_core:server:onGroupUpdate', function(source, groupName, groupGrade)
	if playersClockedIn[source] then
		onPlayerUnload(source)
		return
	end
	local player = exports.qbx_core:GetPlayer(source)
	if player == nil then return end
	if player.PlayerData.job.onduty then
		doPlayerCheckIn(player.PlayerData.source, player.PlayerData.citizenid, groupName)
	end
end)

---@param source number
---@param duty boolean
AddEventHandler('QBCore:Server:SetDuty', function(source, duty)
	local player = exports.qbx_core:GetPlayer(source)
    if player == nil then return end
	if duty then
		doPlayerCheckIn(player.PlayerData.source, player.PlayerData.citizenid, player.PlayerData.job.name)
	else
		onPlayerUnload(player.PlayerData.source)
	end
end)

---@param source number
AddEventHandler('QBCore:Server:OnPlayerUnload', function()
    onPlayerUnload(source)
end)

---@param source number
AddEventHandler('playerDropped', function()
	onPlayerUnload(source)
end)