lib.versionCheck('Qbox-project/qbx_management')
if not lib.checkDependency('qbx_core', '1.3.0', true) then error() return end

local config = require 'config.server'
local logger = require '@qbx_core.modules.logger'
local JOBS = exports.qbx_core:GetJobs()
local GANGS = exports.qbx_core:GetGangs()
local menus = {}

for groupName, menuInfo in pairs(config.menus) do
	menuInfo.groupName = groupName
	menus[#menus + 1] = menuInfo
end

-- Get a list of employees for a given group. Currently uses MySQL queries to return offline players.
-- Once an export is available to reliably return offline players this can rewriten.
---@param groupName string Name of job/gang to get employees of
---@param groupType 'job'|'gang'
---@return table?
lib.callback.register('qbx_management:server:getEmployees', function(source, groupName, groupType)
	local player = exports.qbx_core:GetPlayer(source)

	if not player.PlayerData[groupType].isboss then return end

	local employees = {}
	local players = FetchPlayerEntitiesByGroup(groupName, groupType)
	if not players then return {} end
	for _, employee in pairs(players) do
		local isOnline = exports.qbx_core:GetPlayerByCitizenId(employee.citizenid)
		local isOffline = json.decode(employee[groupType])
		if isOnline then
			employees[#employees + 1] = {
			cid = isOnline.PlayerData.citizenid,
			grade = isOnline.PlayerData[groupType].grade,
			isboss = isOnline.PlayerData[groupType].isboss,
			name = '🟢 '..isOnline.PlayerData.charinfo.firstname..' '..isOnline.PlayerData.charinfo.lastname
			}
		elseif isOffline.name == groupName then
			employees[#employees + 1] = {
			cid = employee.citizenid,
			grade =  isOffline.grade,
			isboss = isOffline.isboss,
			name = '❌ '..json.decode(employee.charinfo).firstname..' '..json.decode(employee.charinfo).lastname
			}
		end
	end
    table.sort(employees, function(a, b)
		return a.grade.level > b.grade.level
	end)
	return employees
end)

-- Callback for updating the grade information of online players
---@param cid string CitizenId of player who is being promoted/demoted
---@param grade integer Grade number target for target employee
---@param groupType 'job'|'gang'
lib.callback.register('qbx_management:server:updateGrade', function(source, cid, grade, groupType)
	local player = exports.qbx_core:GetPlayer(source)
	local employee = exports.qbx_core:GetPlayerByCitizenId(cid)
	local jobName = player.PlayerData[groupType].name

	if not player.PlayerData[groupType].isboss then return end
	if grade > player.PlayerData[groupType].grade.level then exports.qbx_core:Notify(source, locale('error.cant_promote'), 'error') return end

	if not employee then
        exports.qbx_core:Notify(source, locale('error.not_around'), 'error')
        return
    end

    local success, gradeName
    if groupType == 'gang' then
        success = employee.Functions.SetGang(jobName, grade)
		gradeName = GANGS[jobName].grades[grade].name
    else
        success = employee.Functions.SetJob(jobName, grade)
		gradeName = JOBS[jobName].grades[grade].name
    end

    if success then
        exports.qbx_core:Notify(source, locale('success.promoted'), 'success')
        exports.qbx_core:Notify(employee.PlayerData.source, locale('success.promoted_to')..gradeName..'.', 'success')
    else
        exports.qbx_core:Notify(source, locale('error.grade_not_exist'), 'error')
    end
	return nil
end)

-- Callback to hire online player as employee of a given group
---@param employee integer Server ID of target employee to be hired
---@param groupType 'job'|'gang'
lib.callback.register('qbx_management:server:hireEmployee', function(source, employee, groupType)
	local player = exports.qbx_core:GetPlayer(source)
	local target = exports.qbx_core:GetPlayer(employee)
	
    if not player.PlayerData[groupType].isboss then return end
	
    if not target then
        exports.qbx_core:Notify(source, locale('error.not_around'), 'error')
        return
    end

	local jobName = player.PlayerData[groupType].name
	local logArea = groupType == 'gang' and 'Gang' or 'Boss'

    local success = groupType == 'gang' and target.Functions.SetGang(jobName, groupType) or target.Functions.SetJob(jobName, groupType)
    local grade = groupType == 'gang' and GANGS[jobName].grades[0].name or JOBS[jobName].grades[0].name
	
    if success then
        local playerFullName = player.PlayerData.charinfo.firstname..' '..player.PlayerData.charinfo.lastname
        local targetFullName = target.PlayerData.charinfo.firstname..' '..target.PlayerData.charinfo.lastname
        local organizationLabel = player.PlayerData[groupType].label
		exports.qbx_core:Notify(source, locale('success.hired_into', {who = targetFullName, where = organizationLabel}), 'success')
        exports.qbx_core:Notify(target.PlayerData.source, locale('success.hired_to')..organizationLabel, 'success')
		logger.log({source = 'qbx_management', event = 'hireEmployee', message = string.format('%s | %s hired %s into %s at grade %s', logArea, playerFullName, targetFullName, organizationLabel, grade), webhook = config.discordWebhook})
    else
        exports.qbx_core:Notify(source, locale('error.couldnt_hire'), 'error')
    end
	return nil
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

-- Function to fire an online player from a given group
-- Should be merged with the offline player function once an export from the core is available
---@param source integer
---@param employee Player Player object of player being fired
---@param player Player Player object of player initiating firing action
---@param groupType 'job'|'gang'
local function fireOnlineEmployee(source, employee, player, groupType)
	if employee.PlayerData.citizenid == player.PlayerData.citizenid then
		local message = groupType == 'gang' and locale('error.kick_yourself') or locale('error.fire_yourself')
		exports.qbx_core:Notify(source, message, 'error')
		return false
	end

	if employee.PlayerData[groupType].grade.level > player.PlayerData[groupType].grade.level then
		exports.qbx_core:Notify(source, locale('error.kick_boss'), 'error')
		return false
	end

	local success = groupType == 'gang' and employee.Functions.SetGang('none', 0) or employee.Functions.SetJob('unemployed', 0)
	if success then
		local notifyMessage = groupType == 'gang' and locale('error.you_gang_fired') or locale('error.you_job_fired')
		exports.qbx_core:Notify(employee.PlayerData.source, notifyMessage, 'error')
		return true
	end
	exports.qbx_core:Notify(source, locale('error.unable_fire'), 'error')
	return false
end

-- Function to fire an offline player from a given group
-- Should be merged with the online player function once an export from the core is available
---@param source integer
---@param employee string citizenid of player to be fired
---@param player Player Player object of player initiating firing action
---@param groupType 'job'|'gang'
local function fireOfflineEmployee(source, employee, player, groupType)
	local offlineEmployee = FetchPlayerEntityByCitizenId(employee)
	if not offlineEmployee[1] then
		exports.qbx_core:Notify(source, locale('error.person_doesnt_exist'), 'error')
		return false, nil
	end

	employee = offlineEmployee[1]
	employee[groupType] = json.decode(employee[groupType])
	employee.charinfo = json.decode(employee.charinfo)

	if employee[groupType].grade.level > player.PlayerData[groupType].grade.level then
		exports.qbx_core:Notify(source, locale('error.fire_boss'), 'error')
		return false, nil
	end

	local role = {
		name = groupType == 'gang' and 'none' or 'unemployed',
		label = groupType == 'gang' and GANGS['none'].label or JOBS['unemployed'].label,
		payment = groupType == 'gang' and 0 or JOBS['unemployed'].grades[0].payment,
		onduty = groupType ~= 'gang',
		isboss = false,
		grade = {
			name = groupType == 'gang' and GANGS['none'].grades[0].name or JOBS['unemployed'].grades[0].name,
			level = 0
		}
	}

	local updateColumn = groupType == 'gang' and 'gang' or 'job'
	local employeeFullName = employee.charinfo.firstname..' '..employee.charinfo.lastname
	local success = UpdatePlayerJob(updateColumn, role, employee.citizenid)
	if success > 0 then
		return true, employeeFullName
	end
	return false, nil
end

-- Callback for firing a player from a given society.
-- Branches to online and offline functions depending on if the target is available.
-- Once an export is available this should be rewritten to remove the MySQL queries.
---@param employee string citizenid of employee to be fired
---@param groupType 'job'|'gang'
lib.callback.register('qbx_management:server:fireEmployee', function(source, employee, groupType)
	local player = exports.qbx_core:GetPlayer(source)
	local firedEmployee = exports.qbx_core:GetPlayerByCitizenId(employee) or nil
	local playerFullName = player.PlayerData.charinfo.firstname..' '..player.PlayerData.charinfo.lastname
	local organizationLabel = player.PlayerData[groupType].label
	
	if not player.PlayerData[groupType].isboss then return end
	
	local success, employeeFullName
	if firedEmployee then
		employeeFullName = firedEmployee.PlayerData.charinfo.firstname..' '..firedEmployee.PlayerData.charinfo.lastname
		success = fireOnlineEmployee(source, firedEmployee, player, groupType)
	else
		success, employeeFullName = fireOfflineEmployee(source, employee, player, groupType)
	end
	
	if success then
		local logArea = groupType == 'gang' and 'Gang' or 'Boss'
		local logType = groupType == 'gang' and locale('error.gang_fired') or locale('error.job_fired')
		exports.qbx_core:Notify(source, logType, 'success')
		logger.log({source = 'qbx_management', event = 'fireEmployee', message = string.format('%s | %s fired %s from %s', logArea, playerFullName, employeeFullName, organizationLabel), webhook = config.discordWebhook})
	else
		exports.qbx_core:Notify(source, locale('error.unable_fire'), 'error')
	end
	return nil
end)

lib.callback.register('qbx_management:server:getBossMenus', function()
	return menus
end)

---Creates a boss zone for the specified group
---@class MenuInfo
---@field groupName string Name of the group
---@field type 'job'|'gang' Type of group
---@field coords vector3 Coordinates of the zone
---@field size? vector3 uses vec3(1.5, 1.5, 1.5) if not set
---@field rotation? number uses 0.0 if not set
---@field stashSlots? number uses 40 if not set
---@field stashWeight? number uses 400000 if not set

---@param menuInfo MenuInfo
local function registerBossMenu(menuInfo)
    menus[#menus + 1] = menuInfo
	TriggerClientEvent('qbx_management:client:bossMenuRegistered', -1, menuInfo)
	local prefix = menuInfo.type == 'gang' and 'gang_' or 'boss_'
	exports.ox_inventory:RegisterStash(prefix..menuInfo.groupName, 'Stash: '..menuInfo.groupName, (menuInfo.stashSlots or 40), (menuInfo.stashWeight or 400000), false)
end

exports('RegisterBossMenu', registerBossMenu)

-- Event Handlers
-- Sets up inventory stashes for all groups (Used by the config boss menu creation)
AddEventHandler('onServerResourceStart', function(resource)
	if resource ~= 'ox_inventory' and resource ~= cache.resource then return end
	local data = config.menus
	for groupName, menuInfo in pairs(data) do
		local prefix = menuInfo.type == 'gang' and 'gang_' or 'boss_'
		exports.ox_inventory:RegisterStash(prefix..groupName, 'Stash: '..groupName, (menuInfo.slots or 40), (menuInfo.weight or 400000), false)
	end
end)
