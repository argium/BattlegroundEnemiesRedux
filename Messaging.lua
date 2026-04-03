---@type string
local AddonName = ...
---@class Data
local Data = select(2, ...)
---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
local L = Data.L

---@class BattleGroundEnemiesAceComm: BattleGroundEnemies
LibStub("AceComm-3.0"):Embed(BattleGroundEnemies)

local CTimerNewTicker = C_Timer.NewTicker
local GetTime = GetTime
local max = math.max

local BGE_VERSION = "11.2.0.6"
local AddonPrefix = "BGE"
local VERSION_QUERY_MESSAGE = "Q^%s^%i"
local VERSION_RESPONSE_MESSAGE = "V^%s^%i"
local PROFILE_RESPONSE_MESSAGE = "PR^%s"
local MAX_GROUP_MESSAGE_LENGTH = 64
local MAX_PROFILE_MESSAGE_LENGTH = 50000

local highestVersion = BGE_VERSION
local playerData = {}

local function generateStrings()
  local shareActiveProfile = BattleGroundEnemies.db.profile.shareActiveProfile and 1 or 0
  return {
    vq = VERSION_QUERY_MESSAGE:format(BGE_VERSION, shareActiveProfile),
    vr = VERSION_RESPONSE_MESSAGE:format(BGE_VERSION, shareActiveProfile),
  }
end

local function encodeProfileResponse(profile)
  local encoded = BattleGroundEnemies:ExportDataCompressed(profile, false)
  if not encoded then
    return
  end
  return PROFILE_RESPONSE_MESSAGE:format(encoded)
end

--[[
LE_PARTY_CATEGORY_HOME will query information about your "real" group -- the group you were in on your Home realm, before entering any instance/battleground.
LE_PARTY_CATEGORY_INSTANCE will query information about your "fake" group -- the group created by the instance/battleground matching mechanism.
 ]]
local function IsFirstNewerThanSecond(versionString1, versionString2)
  --versionString can be "9.2.0.10" for example, another player can have "9.2.0.9"
  -- we cant make a simple comparison like "9.2.0.10" > "9.2.0.9" because this would result in false

  local firstVersion = { strsplit(".", versionString1) }
  local secondVersion = { strsplit(".", versionString2) }

  for i = 1, max(#firstVersion, #secondVersion) do
    local firstVersionNumber = tonumber(firstVersion[i]) or 0
    local secondVersionNumber = tonumber(secondVersion[i]) or 0

    if firstVersionNumber > secondVersionNumber then
      return true
    elseif firstVersionNumber < secondVersionNumber then --otherwise its equal and we compare the next table item
      return false
    end
  end
  return false --we didnt return anything yet since all numbers where equal, we are at the end of the arrays so both versions are equal
end

SLASH_BattleGroundEnemiesVersion1 = "/bgev"
SLASH_BattleGroundEnemiesVersion2 = "/BGEV"
SlashCmdList.BattleGroundEnemiesVersion = function()
  if not IsInGroup() then
    BattleGroundEnemies:Information(L.MyVersion, BGE_VERSION)
    return
  end

  local function coloredNameVersion(allyButton, version)
    local coloredName = BattleGroundEnemies:GetColoredName(allyButton)
    if version ~= "" then
      version = ("|cFFCCCCCC(%s%s)|r"):format(version, "")
    end
    return (coloredName .. version)
  end

  local results = {
    current = {}, --users of the current version
    old = {}, -- users of an old version
    none = {}, -- no BGE detected
  }
  local texts = {
    current = L.CurrentVersion,
    old = L.OldVersion,
    none = L.NoVersion,
  }

  --loop through all of the BattleGroundEnemies.Allies.Players to find out which one of them send us their addon version
  local t, v
  for allyName, allyButton in pairs(BattleGroundEnemies.Allies.Players) do
    t, v = results.none, ""
    if playerData[allyName] then
      if IsFirstNewerThanSecond(highestVersion, playerData[allyName].version) then
        t = results.old
      else
        t = results.current
      end
      v = playerData[allyName].version
    end
    table.insert(t, coloredNameVersion(allyButton, v))
  end

  for state, names in pairs(results) do
    if #names > 0 then
      BattleGroundEnemies:Information(texts[state] .. ":", table.concat(names, ", "))
    end
  end
end

local timers = {}
--[[
  we use timers to broadcast information, we do this because it may happen that
many players request the same information in a short time due to
 ingame events like GROUP_ROSTER_UPDATE, this way we only send out the information
once when requested in a 3 second time frame, every new request resets the timer
 ]]

function BattleGroundEnemies:QueryVersions(channel)
  BattleGroundEnemies:SendCommMessage(AddonPrefix, generateStrings().vq, channel)
end

local wasInGroup = nil
function BattleGroundEnemies:RequestEverythingFromGroupmembers()
  local groupType = (IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and 3) or (IsInRaid() and 2) or (IsInGroup() and 1)
  if (not wasInGroup and groupType) or (wasInGroup and groupType and wasInGroup ~= groupType) then
    wasInGroup = groupType
    -- local iWantToDoTargetcalling = self.db.profile.targetCallingVolunteer
    local channel = groupType == 3 and "INSTANCE_CHAT" or "RAID"
    --self:QueryTargetCallCaller(channel)
    --self:QueryTargetCallVolunteers(channel)
    self:QueryVersions(channel)
  elseif wasInGroup and not groupType then
    wasInGroup = nil
    playerData = {}
  end
end

function BattleGroundEnemies:ProfileReceived(sender, data)
  if type(data) ~= "table" then
    return
  end
  playerData[sender] = playerData[sender] or {}
  data.receivedAt = GetTime()
  playerData[sender].profileData = data
end

function BattleGroundEnemies:SendCurrentProfileTo(sender)
  if not sender then
    return
  end

  local encoded = encodeProfileResponse({ version = BGE_VERSION, profile = BattleGroundEnemies.db.profile })
  if not encoded then
    return
  end
  BattleGroundEnemies:SendCommMessage(AddonPrefix, encoded, "WHISPER", sender)
end

function BattleGroundEnemies:UpdatePlayerData(sender, prefix, version, profileSharingEnabled)
  if prefix == "Q" then
    if timers.VersionCheck then
      timers.VersionCheck:Cancel()
    end
    timers.VersionCheck = CTimerNewTicker(3, function()
      if IsInGroup() then
        BattleGroundEnemies:SendCommMessage(
          AddonPrefix,
          generateStrings().vr,
          IsInGroup(2) and "INSTANCE_CHAT" or "RAID"
        ) -- LE_PARTY_CATEGORY_INSTANCE = 2
      end
      timers.VersionCheck = nil
    end, 1)
  end
  if prefix == "V" or prefix == "Q" then -- V = version response, Q = version query
    playerData[sender] = playerData[sender] or {}
    if version then
      playerData[sender].version = version
      if IsFirstNewerThanSecond(version, highestVersion) then
        if timers.outdatedTimer then
          timers.outdatedTimer:Cancel()
        end
        timers.outdatedTimer = CTimerNewTicker(3, function()
          BattleGroundEnemies:OnetimeInformation(L.NewVersionAvailable .. ": ", highestVersion)
          timers.outdatedTimer = nil
        end, 1)

        highestVersion = version
      end
    end
    if profileSharingEnabled then
      profileSharingEnabled = profileSharingEnabled == "1"
      playerData[sender].profileSharingEnabled = profileSharingEnabled
    end
  end
end

function BattleGroundEnemies:CHAT_MSG_ADDON(addonPrefix, message, channel, sender) --the sender always contains the realm of the player, even when from same realm
  if addonPrefix ~= AddonPrefix then
    return
  end
  if type(message) ~= "string" then
    return
  end

  sender = Ambiguate(sender, "none")

  if channel == "RAID" or channel == "PARTY" or channel == "INSTANCE_CHAT" then
    if #message > MAX_GROUP_MESSAGE_LENGTH then
      return
    end

    local msgPrefix, version, profileSharingEnabled = strsplit("^", message) --try if there is already a msgPrefix and version, if so we got old addon version response

    if (msgPrefix == "V" or msgPrefix == "Q") and version then
      --info 2 is whether or not that player got profile sharing enabled
      self:UpdatePlayerData(sender, msgPrefix, version, profileSharingEnabled)
    end
  elseif channel == "WHISPER" then
    if #message > MAX_PROFILE_MESSAGE_LENGTH then
      return
    end

    local msgPrefix, payload = strsplit("^", message, 2)
    if not msgPrefix or not payload then
      return
    end

    if msgPrefix == "PQ" then
      local requestFromPlayerName = Ambiguate(payload, "none") -- name of the player he wants that profile from

      if
        requestFromPlayerName == BattleGroundEnemies.UserDetails.PlayerName
        and BattleGroundEnemies.db.profile.shareActiveProfile
      then --sender wants my profile
        self:SendCurrentProfileTo(sender)
      end
    elseif msgPrefix == "PR" then --someone send us their profile
      local decoded = BattleGroundEnemies:DecodeReceivedData(payload, false)
      if not decoded or type(decoded) ~= "table" or type(decoded.profile) ~= "table" then
        return
      end

      self:ProfileReceived(sender, decoded)
    end
  end
end

BattleGroundEnemies:RegisterComm(AddonPrefix, "CHAT_MSG_ADDON")
