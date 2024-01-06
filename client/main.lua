local config = require 'config.client'
local JOBS = exports.qbx_core:GetJobs()
local GANGS = exports.qbx_core:GetGangs()
local isLoggedIn = LocalPlayer.state.isLoggedIn

lib.locale()

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
                lib.callback.await('qbx_management:server:updateGrade', false, player.cid, tonumber(groupGrade), groupType)
                OpenBossMenu(groupType)
            end,
        }
    end

    employeeMenu[#employeeMenu + 1] = {
        title = groupType == 'gang' and locale('menu.expel_gang') or locale('menu.fire_employee'),
        icon = 'fa-solid fa-user-large-slash',
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

-- Presents a menu of employees the work for a job or gang.
-- Allows selection of an employee to perform further actions
---@param groupType GroupType
local function employeeList(groupType)
    local employeesMenu = {}
    local groupName = QBX.PlayerData[groupType].name
    local employees = lib.callback.await('qbx_management:server:getEmployees', false, groupName, groupType)
    for _, employee in pairs(employees) do
        employeesMenu[#employeesMenu + 1] = {
            title = employee.name,
            description = employee.grade.name,
            onSelect = function()
                manageEmployee(employee, groupName, groupType)
            end,
        }
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
        title = groupType == 'gang' and locale('menu.hire_gang') or locale('menu.hire_employees'),
        menu = 'openBossMenu',
        options = hireMenu,
    })

    lib.showContext('hireMenu')
end

-- Opens main boss menu changing function based on the group provided.
---@param groupType GroupType
function OpenBossMenu(groupType)
    if not QBX.PlayerData[groupType].name or not QBX.PlayerData[groupType].isboss then return end

    local bossMenu = {
        {
            title = groupType == 'gang' and locale('menu.manage_gang') or locale('menu.manage_employees'),
            description = groupType == 'gang' and locale('menu.check_gang') or locale('menu.check_employee'),
            icon = 'fa-solid fa-list',
            onSelect = function()
                employeeList(groupType)
            end,
        },
        {
            title = 'Hire Employees',
            description = groupType == 'gang' and locale('menu.hire_gang') or locale('menu.hire_civilians'),
            icon = 'fa-solid fa-hand-holding',
            onSelect = function()
                showHireMenu(groupType)
            end,
        },
    }

    lib.registerContext({
        id = 'openBossMenu',
        title = groupType == 'gang' and string.upper(QBX.PlayerData.gang.label) or string.upper(QBX.PlayerData.job.label),
        options = bossMenu,
    })
    lib.showContext('openBossMenu')
end

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
                    icon = 'fa-solid fa-right-to-bracket',
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

AddEventHandler('onClientResourceStart', function(resource)
    if cache.resource ~= resource then return end
    initZones()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    isLoggedIn = true
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    isLoggedIn = false
end)

CreateThread(function()
    if not isLoggedIn then return end
end)