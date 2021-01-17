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
local newProfileObj = {}

-- Info used to key the current saved data.
local accountName
local serverName
local characterName
local characterId
local numCharacters

local SAVE_EMPTY = 0
local SAVE_QUEUED = 1
local SAVE_DONE = 2

local COMPARE_NONEXISTENT = -1
local COMPARE_IDENTICAL = 0
local COMPARE_NEWER = 1
local COMPARE_UNFINISHED = 2
local COMPARE_VERY_UNFINISHED = 3
local COMPARE_NONE_SPENT = 4


local DEBUG = true
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

-- Create all missing dimensions of one leaf in a multidimensional table's hierarchy.
-- eg BackupRespec.SavedVars[accountName][serverName][characterId].CP
-- @param root table  The root of the table.
-- @param dimensions string[]  The list of dimension names.
local function buildTableToLeaf(root, dimensions)
    for i = 1, #dimensions do
        root[dimensions[i]] = root[dimensions[i]] or {}
        root = root[dimensions[i]]
    end
end

-- Since lua apparently can't give the size of a table without iterating over it...
-- @param tableToMeasure table - A table with non-integer keys.
-- @return number - the count of keys in the table.
local function getTableSize(tableToMeasure)
  local elements = 0
  for n in pairs(tableToMeasure) do
    elements = elements + 1
  end
  return elements
end


local function savedSkillValueToPoints(skillValue)
    local pointsSpent = 0;
    if skillValue < -1 then
        pointsSpent = 2 -- Skill plus morph costs two SP.
    elseif skillValue < 2 then
        pointsSpent = 1 -- -1, -0, 0, or 1 all means the skill was bought.
    else
        pointsSpent = skillValue
    end
    return pointsSpent
end

local function getBoolText(input)
    return input and "yes" or "no"
end
local function getNillableText(input)
    return input or "nil"
end

-- Wrappers to send to chat window. Mostly so that I know they aren't debugging lines and I shouldn't delete them.
local function chatText(...)
    CHAT_SYSTEM:AddMessage(string.format("%s: %s", BackupRespec.shortName, zo_strformat(...)))
end

-- Populate the CP part of the newProfileObj.
-- CP skills are arranged by attribute (health/mag/stam), then discipline/constellation, then skill/perk.
local function populateCpProfileObj()
    for disciplineId = 1, GetNumChampionDisciplines() do
        local attributeId = GetChampionDisciplineAttribute(disciplineId)
        buildTableToLeaf(newProfileObj, {'CP', attributeId, disciplineId})
        for skillId = 1, GetNumChampionDisciplineSkills() - 4 do  -- 4 = number of auto-added skills.
            local numPoints = GetNumPointsSpentOnChampionSkill(disciplineId, skillId)
            newProfileObj.CP[attributeId][disciplineId][skillId] = numPoints
        end
    end

    local cpSpentHealth = GetNumSpentChampionPoints(ATTRIBUTE_HEALTH)
    local cpSpentMagicka = GetNumSpentChampionPoints(ATTRIBUTE_MAGICKA)
    local cpSpentStamina = GetNumSpentChampionPoints(ATTRIBUTE_STAMINA)
    local cpSpentTotal = cpSpentHealth + cpSpentMagicka + cpSpentStamina
    newProfileObj.cpSpent = cpSpentTotal
    newProfileObj.cpAvailable = GetPlayerChampionPointsEarned() - cpSpentTotal
    newProfileObj.cpSpentByAttribute = {
        [ATTRIBUTE_HEALTH]  = cpSpentHealth,
        [ATTRIBUTE_MAGICKA] = cpSpentMagicka,
        [ATTRIBUTE_STAMINA] = cpSpentStamina,
    }
end

-- Populate the SP part of the newProfileObj.
-- SP skills are arranged by type, then line, then skill.
local function populateSpProfileObj()
    for typeId = 1, GetNumSkillTypes() do
        for lineId = 1, GetNumSkillLines(typeId) do
            for skillId = 1, GetNumSkillAbilities(typeId, lineId) do
                local abilityName, _, _, isPassive, _, isPurchased, progressionIndex, rank = GetSkillAbilityInfo(typeId, lineId, skillId)
                if (isPurchased) then
                    buildTableToLeaf(newProfileObj, {'SP', typeId, lineId})
                    local skillValue
                    if isPassive then
                        -- Passives with only one level have rank = 0.
                        skillValue = rank
                    else
                        -- Morphs have 0 (no morph yet), or 1 or 2 (whichever morph was chosen).
                        -- We negate this to -0, -1, -2 to differentiate morphs from passives.
                        local _, morphId, _ = GetAbilityProgressionInfo(progressionIndex)
                        skillValue = -morphId
                    end
                    newProfileObj.SP[typeId][lineId][skillId] = skillValue
                    newProfileObj.spSpent = (newProfileObj.spSpent or 0) + savedSkillValueToPoints(skillValue)
                end
            end
        end
    end
    newProfileObj.spAvailable = GetAvailableSkillPoints()
end

-- Check whether each CP skill has the same value as in the existing save.
local function isEqualCp()
    local old = BackupRespec.SavedVars[accountName][serverName][characterId]
    for attributeId, attributeTable in pairs(newProfileObj.CP) do
        for disciplineId, disciplineTable in pairs(attributeTable) do
            for skillId, skillValue in pairs(disciplineTable) do
                if nil == old.CP
                    or nil == old.CP[attributeId]
                    or nil == old.CP[attributeId][disciplineId]
                    or nil == old.CP[attributeId][disciplineId][skillId]
                    or skillValue ~= old.CP[attributeId][disciplineId][skillId]
                then
                    return false
                end
            end
        end
    end
    return true
end

-- Check whether each SP skill has the same value as in the existing save.
local function isEqualSp()
    local old = BackupRespec.SavedVars[accountName][serverName][characterId]
    for typeId, typeTable in pairs(newProfileObj.SP) do
        for lineId, lineTable in pairs(typeTable) do
            for skillId, skillValue in pairs(lineTable) do
                if nil == old.SP
                    or nil == old.SP[typeId]
                    or nil == old.SP[typeId][lineId]
                    or nil == old.SP[typeId][lineId][skillId]
                    or skillValue ~= old.SP[typeId][lineId][skillId]
                then
                    return false
                end
            end
        end
    end
    return true
end

--- Compare the existing backups to the new profile object.
--- @return number
local function compareProfileObjectsToBackup()
    local isEqual    = true
    local newSpTotal = 0
    local oldSpTotal = 0
    local oldValue

    buildTableToLeaf(BackupRespec.SavedVars, {accountName, serverName, characterId, 'cpSpentByAttribute'})
    local old = BackupRespec.SavedVars[accountName][serverName][characterId]

    if SAVE_EMPTY == old.saveState or nil == old.saveState then
        return COMPARE_NONEXISTENT
    end


    -- Return comparison result.
    if isEqualCp() and isEqualSp() then
        return COMPARE_IDENTICAL  --  identical
    elseif 0 == newProfileObj.cpSpent and 0 == newProfileObj.spSpent then
        return COMPARE_NONE_SPENT  --  empty (0 CP and SP spent)
    elseif newProfileObj.spSpent < old.spSpent
        and (newProfileObj.cpSpentByAttribute[ATTRIBUTE_HEALTH] or 0) < (old.cpSpentByAttribute[ATTRIBUTE_HEALTH] or 0)
        and (newProfileObj.cpSpentByAttribute[ATTRIBUTE_MAGICKA] or 0) < (old.cpSpentByAttribute[ATTRIBUTE_MAGICKA] or 0)
        and (newProfileObj.cpSpentByAttribute[ATTRIBUTE_STAMINA] or 0) < (old.cpSpentByAttribute[ATTRIBUTE_STAMINA] or 0)
    then
        return COMPARE_VERY_UNFINISHED  --  very unfinished (fewer CP and SP spent);
    elseif newProfileObj.spSpent < old.spSpent
        or (newProfileObj.cpSpentByAttribute[ATTRIBUTE_HEALTH] or 0) < (old.cpSpentByAttribute[ATTRIBUTE_HEALTH] or 0)
        or (newProfileObj.cpSpentByAttribute[ATTRIBUTE_MAGICKA] or 0) < (old.cpSpentByAttribute[ATTRIBUTE_MAGICKA] or 0)
        or (newProfileObj.cpSpentByAttribute[ATTRIBUTE_STAMINA] or 0) < (old.cpSpentByAttribute[ATTRIBUTE_STAMINA] or 0)
    then
        return COMPARE_UNFINISHED  --  unfinished (fewer CP or SP spent in at least one category);
    else
        d(dump(newProfileObj.cpSpentByAttribute))
        d(dump(old.cpSpentByAttribute))
        d(isEqualCp() and "CP evaluates as equal" or "CP evaluates as different.")
        d(isEqualSp() and "SP evaluates as equal" or "SP evaluates as different.")
        return COMPARE_NEWER  --  newer (equal or more SP and CP spent in every category);
    end
end

local function onSaveBackupConfirmed()
    -- Perform the backup.
    buildTableToLeaf(BackupRespec.SavedVars, {accountName, serverName, characterId})

    BackupRespec.SavedVars[accountName][serverName][characterId] = newProfileObj
    BackupRespec.SavedVars[accountName][serverName][characterId].saveState = SAVE_QUEUED
    BackupRespec.SavedVars[accountName][serverName][characterId].characterName = characterName

    chatText("Backup queued: will save to disk at next zone or reloadui.")
    d(dump(BackupRespec.SavedVars))
    d(dump(BackupRespec.SavedVars[accountName]))
end

local function OnBackup()
    dx("Backup Button Pressed")

    newProfileObj = {}
    populateCpProfileObj()
    populateSpProfileObj()

    local comparison = compareProfileObjectsToBackup()

    if COMPARE_NONEXISTENT == comparison then
        -- No backup, save without question.
        d("No previous backup found.")
        onSaveBackupConfirmed()
    elseif COMPARE_IDENTICAL == comparison then
        d("Nothing to backup: no changes made since last backup.")
    elseif COMPARE_NEWER == comparison then
        d("Overwriting older backup.")
        onSaveBackupConfirmed()
    elseif COMPARE_UNFINISHED == comparison or COMPARE_VERY_UNFINISHED == comparison then
        ZO_Dialogs_ShowDialog("BackupRespec_ConfirmOverwriteBackup")
    elseif COMPARE_NONE_SPENT == comparison then
        d("Nothing to backup: you have not assigned any CP or SP to this character.")
    end
end

local function OnRestore()
    d("Dumping saved vars:")
    d(dump(BackupRespec.SavedVars))

    --dx("Restore Button Pressed")
    --local active, activeReason = AreChampionPointsActive()
    --if not active then
    --    d("Cannot restore CP at the moment: " .. GetString("SI_CHAMPIONPOINTACTIVEREASON", activeReason))
    --    return
    --else
    --    d("Can restore CP.")
    --end
    --if 9 ~= GetNumChampionDisciplines() then
    --    d("The number of CP disciplines has changed. Please wait for an update of this addon before trying to restore CP.")
    --    return
    --end
    --for disciplineId = 1, GetNumChampionDisciplines() do
    --    if 8 ~= GetNumChampionDisciplineSkills() then
    --        d("The number of CP skills has changed. Please wait for an update of this addon before trying to restore CP.")
    --        return
    --    end
    --end

    -- Possibly relevant fns:
    -- [protected] PickupAbility(number abilityIndex)
    -- [protected] PickupAbilityBySkillLine(number SkillType skillType, number skillLineIndex, number skillIndex)
    -- AddActiveChangeToAllocationRequest(number skillLineId, number progressionId, number MorphSlot morphSlot, boolean isPurchased)
    -- AddPassiveChangeToAllocationRequest(number skillLineId, number abilityId, boolean isRemoval)
    -- ChooseSkillProgressionMorphSlot(number progressionId, number MorphSlot morphSlot)

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

local function initCurrentCharacter()
    accountName = GetUnitDisplayName("player")
    serverName = GetWorldName()
    characterName = zo_strformat("<<1>>", GetRawUnitName("player"))
    characterId = GetCurrentCharacterId()
    numCharacters = GetNumCharacters()

    -- Build out the datastructure.
    buildTableToLeaf(BackupRespec.SavedVars, {accountName, serverName, characterId})
    -- Even if non-nil, we overwrite the name, as it can change.
    BackupRespec.SavedVars[accountName][serverName][characterId].characterName = characterName
    if nil == BackupRespec.SavedVars[accountName][serverName][characterId].saveState then
        BackupRespec.SavedVars[accountName][serverName][characterId].saveState = SAVE_EMPTY
    end
    -- Return the current node.
    return BackupRespec.SavedVars[accountName][serverName][characterId]
end

local function OnPlayerLoaded()
    zo_callLater(function()
        local currentSave = initCurrentCharacter()
        if SAVE_EMPTY == currentSave.saveState then
            -- Saved vars did not already exist for this character. Queue a backup.
            populateCpProfileObj()
            populateSpProfileObj()
            if COMPARE_NONEXISTENT == compareProfileObjectsToBackup() then
                currentSave.CP = cpProfileObj
                currentSave.SP = spProfileObj
                currentSave.saveState = SAVE_QUEUED
                chatText("Auto-backup queued: will save to disk at next zone, reloadui or logout.")
            end
        elseif SAVE_QUEUED == currentSave.saveState then
            -- Saved vars exist and were just saved for this character.
            currentSave.saveState = SAVE_DONE
            d(string.format("Backup saved OK: %s/%s chars saved for account %s on %s.", getTableSize(BackupRespec.SavedVars[accountName][serverName]), numCharacters, accountName, serverName))
        end
    end, 2300)
end

-- Initialize on ADD_ON_LOADED Event
-- Register for other events. Must be below the fns that are registered for the events.
local function BackupRespec_OnAddOnLoaded(_, addOnName)
    if (addOnName == BackupRespec.name) then
        -- set up the various callbacks.
        EVENT_MANAGER:UnregisterForEvent(string.format("%s_%s", BackupRespec.name, "ADDON_LOADED"), EVENT_ADD_ON_LOADED)
        EVENT_MANAGER:RegisterForEvent(string.format("%s_%s", BackupRespec.name, "PLAYER_LOADED"),
            EVENT_PLAYER_ACTIVATED, OnPlayerLoaded)

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

        local confirmDialog      = {
            title    = { text = "Overwrite backup" },
            mainText = { text = "This will update your previous backup, replacing with your current values." },
            buttons  = {
                { text = SI_DIALOG_ACCEPT, callback = onSaveBackupConfirmed },
                { text = SI_DIALOG_CANCEL }
            }
        }
        ZO_Dialogs_RegisterCustomDialog("BackupRespec_ConfirmOverwriteBackup", confirmDialog)

    end
end

EVENT_MANAGER:RegisterForEvent(string.format("%s_%s", BackupRespec.name, "ADDON_LOADED"), EVENT_ADD_ON_LOADED,
    BackupRespec_OnAddOnLoaded)
