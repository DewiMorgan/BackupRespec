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

local BackupRespec_ButtonGroup

local DEBUG                   = true
local function dx(...)
    if DEBUG then
        d(...)
    end
end

local defaultSavedVars = { -- Will be created in save file if not found, but won't override existing values.
    -- Saved Points.
    CP = {},
    SP = {},
}

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

local function OnBackup()
    dx("Backup Button Pressed")
end

local function OnRestore()
    dx("Restore Button Pressed")
end

function OnSceneStateChange(oldState, newState)
    if (newState == SCENE_SHOWING) then
        KEYBIND_STRIP:AddKeybindButtonGroup(BackupRespec_ButtonGroup)
        dx("Showing")
    elseif (newState == SCENE_HIDDEN) then
        KEYBIND_STRIP:RemoveKeybindButtonGroup(BackupRespec_ButtonGroup)
        dx("Hiding")
    end
end

-- Initialize on ADD_ON_LOADED Event
-- Register for other events. Must be below the fns that are registered for the events.
local function OnAddOnLoaded(_, addOnName)
    if (addOnName == BackupRespec.name) then
        -- set up the various callbacks.
        EVENT_MANAGER:UnregisterForEvent(string.format("%s_%s", BackupRespec.name, "ADDON_LOADED"), EVENT_ADD_ON_LOADED)

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
    end
end

EVENT_MANAGER:RegisterForEvent(string.format("%s_%s", BackupRespec.name, "ADDON_LOADED"), EVENT_ADD_ON_LOADED,
    OnAddOnLoaded)
