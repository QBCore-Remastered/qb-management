local config = require 'config.client'
local JOBS = exports.qbx_core:GetJobs()
local GANGS = exports.qbx_core:GetGangs()
local isLoggedIn = LocalPlayer.state.isLoggedIn
local dynamicMenuItems = {}

-- Adds item to the boss/gang menu.
---@param menuItem ContextMenuItem Requires args.type to be set to know which menu to place in.
---@return number? menuId ID of the menu item added
local function addMenuItem(menuItem)
    local menuId = #dynamicMenuItems + 1
    if not menuItem.args.type then return end
    dynamicMenuItems[menuId] = lib.table.deepclone(menuItem)
    return menuId
end
exports('AddBossMenuItem', addMenuItem)
exports('AddGangMenuItem', addMenuItem)

-- Remove menu item at particular id
---@param id number Menu ID to remove
local function removeMenuItem(id)
    dynamicMenuItems[id] = nil
end
exports('RemoveBossMenuItem', removeMenuItem)
exports('RemoveGangMenuItem', removeMenuItem)

-- Finds nearby players and returns a table of server ids
---@return table
local function findPlayers()
    local coords = GetEntityCoords(cache.ped)
    local closePlayers = lib.getNearbyPlayers(coords, 10, false)
    for _, v in pairs(closePlayers) do
        v.id = GetPlayerServerId(v.id)
    end
    return lib.callback.await('qbx_management:server:getPlayers', false, closePlayers)
end

-- Presents a menu to manage a specific employee including changing grade or firing them
---@param player table Player data for managing a specific employee
---@param groupName string Name of job/gang of employee being managed
---@param groupType GroupType
local function manageEmployee(player, groupName, groupType)
    local employeeMenu = {}
    local employeeLoop = groupType == 'gang' and GANGS[groupName].grades or JOBS[groupName].grades
    for groupGrade, gradeTitle in pairs(employeeLoop) do
        employeeMenu[#employeeMenu + 1] = {
            title = gradeTitle.name,
            description = locale('menu.grade')..groupGrade,
            onSelect = function()
                lib.callback.await('qbx_management:server:updateGrade', false, player.cid, player.grade, tonumber(groupGrade), groupType)
                OpenBossMenu(groupType)
            end,
        }
    end

    table.sort(employeeMenu, function(a, b)
        return a.description < b.description
    end)

    employeeMenu[#employeeMenu + 1] = {
        title = groupType == 'gang' and locale('menu.expel_gang') or locale('menu.fire_employee'),
        icon = 'user-large-slash',
        onSelect = function()
            lib.callback.await('qbx_management:server:fireEmployee', false, player.cid, groupType)
            OpenBossMenu(groupType)
        end,
    }

    lib.registerContext({
        id = 'memberMenu',
        title = player.name,
        menu = 'memberListMenu',
        options = employeeMenu,
    })

    lib.showContext('memberMenu')
end

---Opens a menu to edit a grade
---@param groupType GroupType
---@param groupData Job|Gang
---@param grade integer
local function editGrade(groupType, groupData, grade)
    local gradeData = groupData.grades[grade]
    local rows = {
        { type = 'input', label = locale('grade.label'), default = gradeData.name, required = true },
    }
    if groupType == 'job' then
        rows[#rows+1] = { type = 'number', label = locale('grade.pay'), default = gradeData.payment }
        rows[#rows+1] = { type = 'checkbox', label = locale('grade.boss'), checked = gradeData.isboss }
        rows[#rows+1] = { type = 'checkbox', label = locale('grade.bank'), checked = gradeData.bankAuth }
    end
    local data = lib.inputDialog(("%s: %s"):format(groupData.label, gradeData.name), rows)

    if data then
        gradeData.name = data[1]
        if groupType == 'job' then
            gradeData.payment = data[2]
            gradeData.isboss = data[3]
            gradeData.bankAuth = data[4]
        end
        lib.callback.await('qbx_management:server:modifyGrade', nil, groupType, grade, gradeData)
    end

    lib.showContext('openBossMenu')
end

-- Presents a menu of employees the work for a job or gang.
-- Allows selection of an employee to perform further actions
---@param groupType GroupType
local function employeeList(groupType)
    local employeesMenu = {}
    local groupName = QBX.PlayerData[groupType].name
    local employees = lib.callback.await('qbx_management:server:getEmployees', false, groupName, groupType)
    for _, employee in pairs(employees) do
        local employeesData = {
            title = employee.name,
            description = groupType == 'job' and JOBS[groupName].grades[employee.grade].name or GANGS[groupName].grades[employee.grade].name,
            onSelect = function()
                manageEmployee(employee, groupName, groupType)
            end,
        }
        if employee.hours and employee.last_checkin then
            employeesData.metadata = {
                { label = locale('menu.employee_status'), value = employee.onduty and locale('menu.on_duty') or locale('menu.off_duty') },
                { label = locale('menu.hours_in_days'), value = employee.hours },
                { label = locale('menu.last_checkin'), value = employee.last_checkin },
            }
        end
        employeesMenu[#employeesMenu + 1] = employeesData
    end

    lib.registerContext({
        id = 'memberListMenu',
        title = groupType == 'gang' and locale('menu.manage_gang') or locale('menu.manage_employees'),
        menu = 'openBossMenu',
        options = employeesMenu,
    })

    lib.showContext('memberListMenu')
end

-- Presents a list of possible employees to hire for a job or gang.
---@param groupType GroupType
local function showHireMenu(groupType)
    local hireMenu = {}
    local players = findPlayers()
    local hireName = QBX.PlayerData[groupType].name
    for _, player in pairs(players) do
        if player[groupType].name ~= hireName then
            hireMenu[#hireMenu + 1] = {
                title = player.name,
                description = locale('menu.citizen_id')..player.citizenid..' - '..locale('menu.id')..player.source,
                onSelect = function()
                    lib.callback.await('qbx_management:server:hireEmployee', false, player.source, groupType)
                    OpenBossMenu(groupType)
                end,
            }
        end
    end

    lib.registerContext({
        id = 'hireMenu',
        title = groupType == 'gang' and locale('menu.hire_gang') or locale('menu.hire_civilians'),
        menu = 'openBossMenu',
        options = hireMenu,
    })

    lib.showContext('hireMenu')
end

---Opens grade management menu
---@param groupType GroupType
local function showGradeMenu(groupType)
    local gradeOpts = {}
    local groupName = QBX.PlayerData[groupType].name
    local groupData = groupType == 'gang' and GANGS[groupName] or JOBS[groupName]

    for i = 1, #groupData.grades do
        local grade = groupData.grades[i]
        gradeOpts[#gradeOpts+1] = {
            title = grade.name,
            description = locale(("menu.manage_%s_grade"):format(groupType)),
            icon = 'pen-to-square',
            disabled = QBX.PlayerData[groupType].grade.level < i,
            onSelect = function()
                editGrade(groupType, groupData, i)
            end,
        }
    end

    lib.registerContext({
        id = 'gradeMenu',
        title = locale(("menu.manage_%s_grades"):format(groupType)),
        menu = 'openBossMenu',
        options = gradeOpts,
    })

    lib.showContext('gradeMenu')
end

-- Opens main boss menu changing function based on the group provided.
---@param groupType GroupType
function OpenBossMenu(groupType)
    if groupType ~= 'gang' and groupType ~= 'job' or not QBX.PlayerData[groupType].name or not QBX.PlayerData[groupType].isboss then return end

    local bossMenu = {
        {
            title = groupType == 'gang' and locale('menu.manage_gang') or locale('menu.manage_employees'),
            description = groupType == 'gang' and locale('menu.check_gang') or locale('menu.check_employee'),
            icon = 'list',
            onSelect = function()
                employeeList(groupType)
            end,
        },
        {
            title = groupType == 'gang' and locale('menu.hire_members') or locale('menu.hire_employees'),
            description = groupType == 'gang' and locale('menu.hire_gang') or locale('menu.hire_civilians'),
            icon = 'hand-holding',
            onSelect = function()
                showHireMenu(groupType)
            end,
        },
    }

    if GetConvar('qbx:enableGroupManagement', 'false') == 'true' then
        bossMenu[#bossMenu+1] = {
            title = locale(("menu.manage_%s_grades"):format(groupType)),
            description = locale(("menu.manage_%s_grades_desc"):format(groupType)),
            icon = 'clipboard-list',
            onSelect = function()
                showGradeMenu(groupType)
            end,
        }
    end

    for _, menuItem in pairs(dynamicMenuItems) do
        if string.lower(menuItem.args.type) == groupType then
            bossMenu[#bossMenu + 1] = menuItem
        end
    end

    lib.registerContext({
        id = 'openBossMenu',
        title = groupType == 'gang' and string.upper(QBX.PlayerData.gang.label) or string.upper(QBX.PlayerData.job.label),
        options = bossMenu,
        onExit = function()
            lib.showTextUI(groupType == 'gang' and locale('menu.gang_management') or locale('menu.boss_management'))
        end,
    })

    lib.showContext('openBossMenu')
end

exports('OpenBossMenu', OpenBossMenu)

local function createZone(zoneInfo)
    if config.useTarget then
        exports.ox_target:addBoxZone({
            coords = zoneInfo.coords,
            size = zoneInfo.size or vec3(1.5, 1.5, 1.5),
            rotation = zoneInfo.rotation or 0.0,
            debug = config.debugPoly,
            options = {
                {
                    name = zoneInfo.groupName..'_menu',
                    icon = 'right-to-bracket',
                    label = zoneInfo.type == 'gang' and locale('menu.gang_menu') or locale('menu.boss_menu'),
                    canInteract = function()
                        return zoneInfo.groupName == QBX.PlayerData[zoneInfo.type].name and QBX.PlayerData[zoneInfo.type].isboss
                    end,
                    onSelect = function()
                        OpenBossMenu(zoneInfo.type)
                    end
                }
            }
        })
    else
        lib.zones.box({
            coords = zoneInfo.coords,
            size = zoneInfo.size or vec3(1.5, 1.5, 1.5),
            rotation = zoneInfo.rotation or 0.0,
            debug = config.debugPoly,
            onEnter = function()
                if zoneInfo.groupName == QBX.PlayerData[zoneInfo.type].name and QBX.PlayerData[zoneInfo.type].isboss then
                    lib.showTextUI(zoneInfo.type == 'gang' and locale('menu.gang_management') or locale('menu.boss_management'))
                end
            end,
            onExit = function()
                lib.hideTextUI()
            end,
            inside = function()
                if IsControlJustPressed(0, 51) then -- E
                    if zoneInfo.groupName == QBX.PlayerData[zoneInfo.type].name and QBX.PlayerData[zoneInfo.type].isboss then
                        OpenBossMenu(zoneInfo.type)
                        lib.hideTextUI()
                    end
                end
            end
        })
    end
end

local function initZones()
    local menus = lib.callback.await('qbx_management:server:getBossMenus', false)
    for _, menuInfo in pairs(menus) do
        createZone(menuInfo)
    end
end

RegisterNetEvent('qbx_management:client:bossMenuRegistered', function(menuInfo)
    createZone(menuInfo)
end)

if GetConvar('qbx:enablebridge', 'true') == 'true' then
    RegisterNetEvent('qb-bossmenu:client:OpenMenu', function()
        OpenBossMenu('job')
    end)
    RegisterNetEvent('qb-gangmenu:client:OpenMenu', function()
        OpenBossMenu('gang')
    end)
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    isLoggedIn = true
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    isLoggedIn = false
end)

---Receive job updates from core
---@param jobName string
---@param job Job
RegisterNetEvent('qbx_core:client:onJobUpdate', function(jobName, job)
    JOBS[jobName] = job
end)

---Receive gang updates from core
---@param gangName string
---@param gang Gang
RegisterNetEvent('qbx_core:client:onGangUpdate', function(gangName, gang)
    GANGS[gangName] = gang
end)

CreateThread(function()
    initZones()
    if not isLoggedIn then return end
end)
