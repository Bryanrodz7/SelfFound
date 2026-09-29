-- SelfFound: self-found challenge tracker with tamper checks and peer verification.
-- Targets WotLK 3.3.5 and newer clients (uses compat shims where APIs differ).

local _, ns = ...
local PREFIX        = "SFv1"
local NET_CHANNEL   = "SFnet"        -- hidden chat channel all users join
local HB_INTERVAL   = 60             -- seconds between heartbeats
local GAP_TOLERANCE = 120            -- unexplained /played seconds allowed (crash/lag slack)
-- Obfuscation only; Lua source is readable. Never change this after release:
-- every existing save is signed with it and would turn BROKEN.
local SALT          = "change-me-each-release"

local RANK   = { SF = 1, UNVERIFIED = 2, SUSPECT = 3, BROKEN = 4 }
local COLORS = { SF = "33ff33", UNVERIFIED = "aaaaaa", SUSPECT = "ff9933", BROKEN = "ff4444" }

local SF = CreateFrame("Frame")
local me, myGUID
local playedBase, playedBaseAt
local ready, suppressPlayed = false, false
local onlineSince = {}
local pendingHB, pendingHello, lastRollCall = nil, nil, 0

local function network() return (SF_Settings and SF_Settings.network) or "guild" end

---------------------------------------------------------------- helpers
local SendAddon = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
elseif RegisterAddonMessagePrefix then
  RegisterAddonMessagePrefix(PREFIX)
end

local function say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99SelfFound:|r " .. msg) end
local function strip(name) return name and (name:gsub("%-.*", "")) end
local function color(status) return "|cff" .. (COLORS[status] or "ffffff") .. status .. "|r" end
local function clean(s) return (tostring(s or ""):gsub(";", ",")) end

local function split(s)
  local t = {}
  for part in (s .. ";"):gmatch("([^;]*);") do t[#t + 1] = part end
  return t
end

local function hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
  return h
end

local function sign(d)
  return hash(table.concat({ SALT, myGUID or "", d.status or "", d.reason or "",
    math.floor(d.played or 0), d.level or 0, d.seq or 0 }, ";"))
end

local function played()
  if not playedBase then return nil end
  return playedBase + (GetTime() - playedBaseAt)
end

local function groupChannel()
  if IsInRaid then
    if IsInRaid() then return "RAID" elseif IsInGroup() then return "PARTY" end
  else
    if GetNumRaidMembers() > 0 then return "RAID" elseif GetNumPartyMembers() > 0 then return "PARTY" end
  end
end

local function send(msg)
  if IsInGuild() then SendAddon(PREFIX, msg, "GUILD") end
  local g = groupChannel()
  if g then SendAddon(PREFIX, msg, g) end
  local id = GetChannelName(NET_CHANNEL)
  if network() == "everyone" and id and id > 0 then
    if C_ChatInfo then
      SendAddon(PREFIX, msg, "CHANNEL", tostring(id))
    elseif SendChatMessage then
      SendChatMessage(PREFIX .. msg, "CHANNEL", nil, id) -- older clients: plain text, hidden by filter
    end
  end
end

---------------------------------------------------------------- own status
local function save()
  local d = SF_Char
  if not d then return end
  local p = played()
  if p then d.played = p end
  d.level = UnitLevel("player")
  d.seq = (d.seq or 0) + 1
  d.sig = sign(d)
end

local function heartbeat()
  local d = SF_Char
  if not d then return end
  send(table.concat({ "HB", d.status, math.floor(played() or d.played or 0),
    UnitLevel("player"), d.seq or 0, clean(d.reason) }, ";"))
end

local function setStatus(status, reason)
  local d = SF_Char
  if not d or RANK[status] <= RANK[d.status] then return end -- never upgrade back to clean
  d.status, d.reason = status, reason
  d.violations = d.violations or {}
  table.insert(d.violations, { status = status, reason = reason, t = time(), played = math.floor(played() or 0) })
  save()
  say(color(status) .. " - " .. reason)
  heartbeat()
  if ns.OnSelfChange then ns.OnSelfChange(status, reason) end
end

local function newData(status, reason)
  SF_Char = { status = status, reason = reason, played = played() or 0,
              level = UnitLevel("player"), seq = 0, violations = {} }
  save()
end

-- Runs once per login after the server reports /played.
local function verify(total)
  local d = SF_Char
  if not d then
    if UnitLevel("player") <= 1 and total < 600 then
      newData("SF", nil)
      say("Self-Found run started. Good luck!")
    else
      newData("UNVERIFIED", "addon installed after character was played")
      say(color("UNVERIFIED") .. " - this character was played before the addon was installed.")
    end
    return
  end
  if d.sig ~= sign(d) then
    setStatus("BROKEN", "save file was edited")
  elseif total < (d.played or 0) - 5 then
    setStatus("BROKEN", "played time went backwards (old save file restored)")
  elseif total > (d.played or 0) + GAP_TOLERANCE then
    local mins = math.floor((total - d.played) / 60)
    setStatus("SUSPECT", mins .. " min played with addon off (or game crashed)")
  end
end

---------------------------------------------------------------- violation detection
local tradeTarget

local function witness(target, what)
  if target then send("WIT;" .. strip(target) .. ";" .. what) end
end

local function onMailTaken(i)
  local _, _, sender, _, money, _, _, itemCount = GetInboxHeaderInfo(i)
  if (money and money > 0) or (itemCount and itemCount ~= 0) then
    setStatus("BROKEN", "took mail from " .. (sender or "unknown"))
  end
end

hooksecurefunc("TakeInboxItem", onMailTaken)
hooksecurefunc("TakeInboxMoney", onMailTaken)
if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", onMailTaken) end

-- Outgoing mail: post-hook instead of replacing SendMail, so Blizzard's mail code stays untainted.
-- Attachments stay in their slots until the server confirms, so they are still readable here.
local pendingMail
hooksecurefunc("SendMail", function(recipient)
  local attached = (GetSendMailMoney() or 0) > 0
  for s = 1, (ATTACHMENTS_MAX_SEND or 12) do
    if GetSendMailItem(s) then attached = true end
  end
  pendingMail = attached and recipient or nil
end)

local function onAuctionBuy() setStatus("BROKEN", "bought from auction house") end
if PlaceAuctionBid then hooksecurefunc("PlaceAuctionBid", onAuctionBuy) end
if C_AuctionHouse then
  if C_AuctionHouse.PlaceBid then hooksecurefunc(C_AuctionHouse, "PlaceBid", onAuctionBuy) end
  if C_AuctionHouse.ConfirmCommoditiesPurchase then
    hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", onAuctionBuy)
  end
end

---------------------------------------------------------------- peer ledger
local function peer(name)
  local p = SF_Ledger[name]
  if not p then
    p = { status = "UNVERIFIED", played = 0, reports = {} }
    SF_Ledger[name] = p
  end
  return p
end

local function peerStatus(name, p, status, reason)
  if (RANK[status] or 0) > (RANK[p.status] or 0) then
    p.status, p.reason = status, reason
    if status == "BROKEN" or status == "SUSPECT" then
      say(name .. " is now " .. color(status) .. " - " .. reason)
    end
    if ns.OnPeerChange then ns.OnPeerChange(name, status, reason) end
  end
end

local function handle(sender, msg)
  sender = strip(sender)
  if not sender or sender == me then return end
  local f = split(msg)
  if f[1] == "HELLO" then
    -- someone asked for a roll call; answer after a random delay so replies don't flood
    if not pendingHB then pendingHB = GetTime() + 1 + math.random() * 5 end
    return
  elseif f[1] == "HB" then
    local status, pl = f[2], tonumber(f[3]) or 0
    if not RANK[status] then return end
    local p = peer(sender)
    if pl < (p.played or 0) - 30 then
      peerStatus(sender, p, "BROKEN", "played time went backwards (rolled-back save)")
    end
    if RANK[status] < RANK[p.status] then
      p.liar = true -- claims cleaner than our record; keep our record
    else
      peerStatus(sender, p, status, f[6] ~= "" and f[6] or "reported by self")
    end
    p.claim, p.played, p.level, p.lastSeen = status, math.max(pl, p.played or 0), tonumber(f[4]), time()
  elseif f[1] == "WIT" and f[2] and f[2] ~= "" then
    local target = f[2]
    if target == me then return end -- your own addon already judged you
    local p = peer(target)
    p.reports[sender] = f[3]
    local n = 0
    for _ in pairs(p.reports) do n = n + 1 end
    -- One report = SUSPECT (stops a single troll from framing people); 2+ independent = BROKEN.
    if n >= 2 then
      peerStatus(target, p, "BROKEN", "reported by " .. n .. " players")
    else
      peerStatus(target, p, "SUSPECT", "reported by " .. sender .. ": " .. f[3])
    end
  end
end

-- Flag guildmates who have used the addon but are online without heartbeats.
local function scanGuild()
  if not IsInGuild() then return end
  if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
  local now = time()
  for i = 1, GetNumGuildMembers() do
    local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
    name = strip(name)
    if name and name ~= me then
      if online then
        onlineSince[name] = onlineSince[name] or now
        local p = SF_Ledger[name]
        if p and p.claim and now - onlineSince[name] > 300 and now - (p.lastSeen or 0) > 300 then
          peerStatus(name, p, "SUSPECT", "online without the addon running")
        end
      else
        onlineSince[name] = nil
      end
    end
  end
end

---------------------------------------------------------------- tooltip
local function tipLine(tt)
  if not tt.GetUnit then return end
  local _, unit = tt:GetUnit()
  if issecretvalue and issecretvalue(unit) then return end -- 12.0+: restricted during encounters
  if not unit or not UnitIsPlayer(unit) then return end
  local name = UnitName(unit)
  if issecretvalue and issecretvalue(name) then return end
  name = strip(name)
  if not name or not SF_Ledger then return end
  local status, reason
  if name == me and SF_Char then
    status, reason = SF_Char.status, SF_Char.reason
  elseif SF_Ledger[name] then
    status, reason = SF_Ledger[name].status, SF_Ledger[name].reason
  end
  if status then
    tt:AddLine("Self-Found: " .. color(status))
    if reason and status ~= "SF" then tt:AddLine(reason, 0.8, 0.8, 0.8, true) end
    tt:Show()
  end
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
    if tt == GameTooltip then tipLine(tt) end
  end)
else
  GameTooltip:HookScript("OnTooltipSetUnit", tipLine)
end

---------------------------------------------------------------- chat plumbing
-- Hide our automatic /played from chat by briefly unregistering the event on the chat frames,
-- rather than replacing ChatFrame_DisplayTimePlayed (which taints and no longer exists everywhere).
local mutedFrames = {}
local function requestPlayedQuietly()
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local f = _G["ChatFrame" .. i]
    if f and f.IsEventRegistered and f:IsEventRegistered("TIME_PLAYED_MSG") then
      f:UnregisterEvent("TIME_PLAYED_MSG")
      mutedFrames[#mutedFrames + 1] = f
    end
  end
  suppressPlayed = true
  RequestTimePlayed()
end

local function unmutePlayed()
  suppressPlayed = false
  for i = #mutedFrames, 1, -1 do
    mutedFrames[i]:RegisterEvent("TIME_PLAYED_MSG")
    mutedFrames[i] = nil
  end
end

local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if addFilter then
  addFilter("CHAT_MSG_CHANNEL", function(_, _, msg)
    if issecretvalue and issecretvalue(msg) then return end
    if msg and msg:sub(1, #PREFIX) == PREFIX then return true end
  end)
end

---------------------------------------------------------------- events
SF:RegisterEvent("ADDON_LOADED")
SF:RegisterEvent("PLAYER_LOGIN")
SF:RegisterEvent("PLAYER_LOGOUT")
SF:RegisterEvent("TIME_PLAYED_MSG")
SF:RegisterEvent("PLAYER_LEVEL_UP")
SF:RegisterEvent("TRADE_SHOW")
SF:RegisterEvent("UI_INFO_MESSAGE")
SF:RegisterEvent("CHAT_MSG_ADDON")
SF:RegisterEvent("CHAT_MSG_CHANNEL")
SF:RegisterEvent("MAIL_SEND_SUCCESS")
SF:RegisterEvent("MAIL_FAILED")

local loginTimer, hbTimer, playedTimeout = nil, 0, nil

SF:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    SF_Ledger = SF_Ledger or {}
  elseif event == "PLAYER_LOGIN" then
    me, myGUID = UnitName("player"), UnitGUID("player")
    loginTimer = 5 -- join channel and request /played after the world settles
  elseif event == "TIME_PLAYED_MSG" then
    local total = ...
    playedBase, playedBaseAt = total, GetTime()
    if suppressPlayed then playedTimeout = 0 end -- re-register chat frames next frame, after this event
    if not ready then
      ready = true
      verify(total)
      heartbeat()
      pendingHello = GetTime() + 4 -- give the channel time to join
      if ns.OnReady then ns.OnReady() end
    end
  elseif event == "PLAYER_LOGOUT" then
    if ready then save() end
  elseif event == "PLAYER_LEVEL_UP" then
    if ready then heartbeat() end
  elseif event == "TRADE_SHOW" then
    tradeTarget = UnitName("NPC")
  elseif event == "UI_INFO_MESSAGE" then
    for i = 1, select("#", ...) do
      if select(i, ...) == ERR_TRADE_COMPLETE then
        setStatus("BROKEN", "traded with " .. (tradeTarget or "unknown"))
        witness(tradeTarget, "trade")
      end
    end
  elseif event == "MAIL_SEND_SUCCESS" then
    if pendingMail then witness(pendingMail, "mail") end
    pendingMail = nil
  elseif event == "MAIL_FAILED" then
    pendingMail = nil
  elseif event == "CHAT_MSG_ADDON" then
    local prefix, msg, _, sender = ...
    if prefix == PREFIX then handle(sender, msg) end
  elseif event == "CHAT_MSG_CHANNEL" and not C_ChatInfo then
    local msg, sender = ...
    if type(msg) == "string" and msg:sub(1, #PREFIX) == PREFIX then handle(sender, msg:sub(#PREFIX + 1)) end
  end
end)

SF:SetScript("OnUpdate", function(self, elapsed)
  if loginTimer then
    loginTimer = loginTimer - elapsed
    if loginTimer <= 0 then
      loginTimer = nil
      ns.SetNetwork(network())
      playedTimeout = 10 -- unmute chat frames even if the server never answers
      requestPlayedQuietly()
    end
  end
  if playedTimeout then
    playedTimeout = playedTimeout - elapsed
    if playedTimeout <= 0 then
      playedTimeout = nil
      unmutePlayed()
    end
  end
  if ready then
    local now = GetTime()
    if pendingHB and now >= pendingHB then pendingHB = nil; heartbeat() end
    if pendingHello and now >= pendingHello then pendingHello = nil; ns.RollCall() end
    hbTimer = hbTimer + elapsed
    if hbTimer >= HB_INTERVAL then
      hbTimer = 0
      heartbeat()
      scanGuild()
    end
  end
end)

---------------------------------------------------------------- shared with UI
ns.RANK, ns.COLORS, ns.color, ns.played, ns.say = RANK, COLORS, color, played, say
ns.GetMe = function() return me end

-- "guild": talk over guild/party only. "everyone": also join the server-wide hidden channel.
ns.SetNetwork = function(mode)
  if SF_Settings then SF_Settings.network = mode end
  if mode == "everyone" then
    JoinChannelByName(NET_CHANNEL)
    local removeChannel = (ChatFrameUtil and ChatFrameUtil.RemoveChannel) or ChatFrame_RemoveChannel
    if removeChannel then removeChannel(DEFAULT_CHAT_FRAME, NET_CHANNEL) end
    if ready then lastRollCall = 0; pendingHello = GetTime() + 4 end
  elseif (GetChannelName(NET_CHANNEL) or 0) > 0 then
    LeaveChannelByName(NET_CHANNEL)
  end
end

-- Ask everyone listening to report in right away (throttled to once per 30s).
ns.RollCall = function()
  if not ready or GetTime() - lastRollCall < 30 then return false end
  lastRollCall = GetTime()
  send("HELLO")
  return true
end

---------------------------------------------------------------- slash commands
SLASH_SELFFOUND1 = "/sf"
SlashCmdList.SELFFOUND = function(arg)
  if arg == "list" then
    for name, p in pairs(SF_Ledger) do
      say(name .. " (" .. (p.level or "?") .. "): " .. color(p.status) ..
        (p.reason and (" - " .. p.reason) or "") .. (p.liar and " |cffff4444[claims clean]|r" or ""))
    end
  elseif SF_Char then
    say("You are " .. color(SF_Char.status) .. (SF_Char.reason and (" - " .. SF_Char.reason) or ""))
  else
    say("Still loading...")
  end
end
