--[[
	BackupRespec
	==========================================
	Backup CP and skillpoints for a character, for easy restore in a respec.
	==========================================
]]--

BackupRespec                  = {}
-- If changing any of these, remember to upgrade the .txt file, too.
BackupRespec.name             = "BackupRespec"
BackupRespec.displayName      = "BackupRespec"
BackupRespec.author           = "Dewi Morgan @Farrier"
BackupRespec.shortName        = "LT" -- Not guaranteed unique, but OK for tagging messages, etc.
BackupRespec.version          = "1.0.0" -- Also change this in the .txt file, add changelog section.
BackupRespec.description      = "Backup CP and skillpoints for a character, for easy restore in a respec."

BackupRespec.SavedVarsVersion = "1" -- If this changes, older saved vars are WIPED.
BackupRespec.SavedVars        = {} -- The actual real data.

--- @type table
local BackupRespec_ButtonGroup
local defaultSavedVars = {} -- Will be created in save file if not found, but won't override existing values.
local cpProfileObj = {}

local DEBUG                   = true
local function dx(...)
    if DEBUG then
        d(...)
    end
end

-- Debugging helper: dump an object, table or variable to a string.
local function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        -- @var k any
        for k, v in pairs(o) do
            if type(k) ~= 'number' then
                k = '"' .. k .. '"'
            end
            s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end


-- Wrappers to send to chat window.
local function chatText(...)
    if BackupRespec.SavedVars.debugMessages then
        CHAT_SYSTEM:AddMessage(string.format("%s: %s", BackupRespec.shortName, zo_strformat(...)))
    end
end
local function chatError(...)
    if BackupRespec.SavedVars.debugMessages then
        CHAT_SYSTEM:AddMessage(string.format("|caf0000%s: %s|r", BackupRespec.shortName, zo_strformat(...)))
    end
end

-- Wrapper for ZO_Alert() to send to corner notifications.
local function zoAlertWrapper(...)
    if BackupRespec.SavedVars.alertMessages then
        ZO_Alert(nil, nil, string.format("%s: %s", BackupRespec.shortName, zo_strformat(...)))
    end
end

local function getCpProfileObj()
    local cpTable = {}

    for disciplineId = 1, GetNumChampionDisciplines() do
        cpTable[disciplineId] = {}
        for skillId = 1, GetNumChampionDisciplineSkills() - 4 do  -- 4 = number of perk skills.
            local numPoints = GetNumPointsSpentOnChampionSkill(disciplineId, skillId)
            cpTable[disciplineId][skillId] = numPoints
        end
    end
    return cpTable
end

--- Compare the existing backups to a new profile object.
--- @param newProfileObj table The new profile to compare to one in saved vars
--- @return number
---        -1 = no old backup exists.
---         0 = identical;
---         1 = newer (equal or more SP and CP spent);
---         2 = unfinished (fewer CP or SP spent);
---         3 = very unfinished (fewer CP and SP spent);
---         4 = empty (0 CP and SP spent)
local function compareToBackup(newProfileObj)
    local isEqual = true
    local newCpTotal = 0
    local oldCpTotal = 0

    local old = BackupRespec.SavedVars[GetCurrentCharacterId()]
    if nil == old or nil == old['CP'] then
        return -1
    end

    for disciplineId, disciplineTable in pairs(newProfileObj['CP']) do
        for skillId, skillValue in pairs(disciplineTable) do
            if nil == old['CP'][disciplineId] or old['CP'][disciplineId][skillId] then
                -- If old backup is corrupted, it doesn't exist to me.
                return -1;
            end
            newCpTotal = newCpTotal + skillValue
            oldCpTotal = oldCpTotal + old[disciplineId][skillId]
            if newCpTotal ~= oldCpTotal then
                isEqual = false
            end
        end
    end

    -- ToDo: SP calculation loop here.

    if isEqual then
        return 0
    elseif 0 == newCpTotal then
        return 4
    elseif newCpTotal < oldCpTotal then
        return 2
    else
        return 1
    end
end

local function onSaveBackupConfirmed()
    -- Perform the backup.
    BackupRespec.SavedVars[GetCurrentCharacterId()] = cpProfileObj
    BackupRespec.SavedVars[GetCurrentCharacterId()]['SaveState'] = 0
    chatText("Backup queued: will save to disk at next zone or reloadui.")
end

local function OnBackup()
    dx("Backup Button Pressed")

    cpProfileObj = getCpProfileObj()
    dx(dump(cpProfileObj))

    local comparison = compareToBackup(cpProfileObj)

    if -1 == comparison then -- No backup, save without question.
        onSaveBackupConfirmed()
    elseif 0 == comparison then
        d("Nothing to backup: no changes made since last backup.")
    elseif 1 == comparison then
        d("Overwriting older backup.")
        onSaveBackupConfirmed()
    elseif 2 == comparison or 3 == comparison then
        ZO_Dialogs_ShowDialog("BackupRespec_ConfirmOverwriteBackup")
    elseif 4 == comparison then
        d("Nothing to backup: you have not assigned any CP or SP to this character.")
    end
end

local function OnRestore()
    dx("Restore Button Pressed")
    local active, activeReason = AreChampionPointsActive()
    if not active then
        d("Cannot restore CP at the moment: " .. GetString("SI_CHAMPIONPOINTACTIVEREASON", activeReason))
        return
    else
        d("Can restore CP.")
    end
    if 9 ~= GetNumChampionDisciplines() then
        d("The number of CP disciplines has changed. Please wait for an update of this addon before trying to restore CP.")
        return
    end
    for disciplineId = 1, GetNumChampionDisciplines() do
        if 8 ~= GetNumChampionDisciplineSkills() then
            d("The number of CP skills has changed. Please wait for an update of this addon before trying to restore CP.")
            return
        end
    end
end

local function OnSceneStateChange(oldState, newState)
    if (newState == SCENE_SHOWING) then
        KEYBIND_STRIP:AddKeybindButtonGroup(BackupRespec_ButtonGroup)
        dx("Showing")
    elseif (newState == SCENE_HIDDEN) then
        KEYBIND_STRIP:RemoveKeybindButtonGroup(BackupRespec_ButtonGroup)
        dx("Hiding")
    end
end

local function OnPlayerLoaded()
    zo_callLater(function()
        if nil == BackupRespec.SavedVars[GetCurrentCharacterId()]
            or nil == BackupRespec.SavedVars[GetCurrentCharacterId()]['SaveState']
        then
            cpProfileObj = getCpProfileObj()
            if -1 == compareToBackup(cpProfileObj) then
                BackupRespec.SavedVars[GetCurrentCharacterId()] = cpProfileObj
                BackupRespec.SavedVars[GetCurrentCharacterId()]['SaveState'] = 0
                chatText("Auto-backup queued: will save to disk at next zone or reloadui.")
            end
        elseif 0 == BackupRespec.SavedVars[GetCurrentCharacterId()]['SaveState'] then
            BackupRespec.SavedVars[GetCurrentCharacterId()]['SaveState'] = 1
            d("Backup saved OK")
        end
	end, 2300)
end

-- Initialize on ADD_ON_LOADED Event
-- Register for other events. Must be below the fns that are registered for the events.
local function BackupRespec_OnAddOnLoaded(_, addOnName)
    if (addOnName == BackupRespec.name) then
        -- set up the various callbacks.
        EVENT_MANAGER:UnregisterForEvent(string.format("%s_%s", BackupRespec.name, "ADDON_LOADED"), EVENT_ADD_ON_LOADED)
        EVENT_MANAGER:RegisterForEvent(string.format("%s_%s", BackupRespec.name, "PLAYER_LOADED"), EVENT_PLAYER_ACTIVATED, OnPlayerLoaded)

        -- Saved vars.
        -- Nil param here is optional string namespace to separate from other saved things within "BackupRespec_SavedVars".
        BackupRespec.SavedVars = ZO_SavedVars:NewAccountWide("BackupRespec_SavedVars", BackupRespec.SavedVarsVersion,
            nil, defaultSavedVars)

        -- Key bindings, for the keybind strip buttons.
        ZO_CreateStringId("SI_BINDING_NAME_BACKUPRESPEC_BACKUP", "Backup")
        ZO_CreateStringId("SI_BINDING_NAME_BACKUPRESPEC_RESTORE", "Restore")

        SCENE_MANAGER:GetScene("skills"):RegisterCallback("StateChange", OnSceneStateChange);
        SCENE_MANAGER:GetScene("championPerks"):RegisterCallback("StateChange", OnSceneStateChange);

        BackupRespec_ButtonGroup = {
            {
                name     = "Backup",
                keybind  = "BACKUPRESPEC_BACKUP",
                callback = function() OnBackup() end,
            }, {
                name     = "Restore",
                keybind  = "BACKUPRESPEC_RESTORE",
                callback = function() OnRestore() end,
            },
            alignment = KEYBIND_STRIP_ALIGN_CENTER,
        }

       local confirmDialog = {
          title = { text = "Overwrite backup" },
          mainText = { text = "This will update your previous backup, replacing with your current values." },
          buttons = {
             { text = SI_DIALOG_ACCEPT, callback = onSaveBackupConfirmed},
             { text = SI_DIALOG_CANCEL }
          }
       }
       ZO_Dialogs_RegisterCustomDialog("BackupRespec_ConfirmOverwriteBackup", confirmDialog)

    end
end

EVENT_MANAGER:RegisterForEvent(string.format("%s_%s", BackupRespec.name, "ADDON_LOADED"), EVENT_ADD_ON_LOADED, BackupRespec_OnAddOnLoaded)
