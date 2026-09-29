-- SelfFound UI: classic Blizzard-style badge, player panel, settings, warnings and alerts.
local ADDON, ns = ...

local DEFAULTS = {
  badgeShown = true, badgeText = true, locked = false,
  badgeScale = 1, panelScale = 1,
  warnings = true, alerts = true, sound = true,
  network = "guild", view = "guild",
}
local S -- SF_Settings, filled on ADDON_LOADED

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local DIALOG = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
local SHIELD = "Interface\\Icons\\INV_Shield_06"
local CROSS  = "Interface\\RaidFrame\\ReadyCheck-NotReady"

---------------------------------------------------------------- helpers
local function fmtPlayed(sec)
  sec = math.floor(sec or 0)
  local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
  if d > 0 then return d .. "d " .. h .. "h" elseif h > 0 then return h .. "h " .. m .. "m" end
  return m .. "m"
end

local function fmtAgo(t)
  if not t then return "never" end
  local s = time() - t
  if s < 120 then return "just now" elseif s < 3600 then return math.floor(s / 60) .. " min ago"
  elseif s < 86400 then return math.floor(s / 3600) .. " h ago" end
  return math.floor(s / 86400) .. " d ago"
end

local function colorTex(tex, r, g, b, a)
  if tex.SetColorTexture then tex:SetColorTexture(r, g, b, a) else tex:SetTexture(r, g, b, a) end
end

local function styleIcon(icon, cross, status)
  icon:SetTexture(SHIELD)
  icon:SetDesaturated(status ~= "SF")
  if status == "SUSPECT" then icon:SetVertexColor(1, 0.7, 0.3)
  elseif status == "BROKEN" then icon:SetVertexColor(1, 0.35, 0.35)
  else icon:SetVertexColor(1, 1, 1) end
  if status == "BROKEN" then cross:Show() else cross:Hide() end
end

local function ding()
  if not S or not S.sound then return end
  if SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) else PlaySound("RaidWarning") end
end

local function alert(text)
  if not S or not S.alerts then return end
  if RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
  else
    UIErrorsFrame:AddMessage(text, 1, 0.3, 0.1)
  end
  ding()
end

local function myStatus()
  local d = SF_Char
  return d and d.status or "UNVERIFIED", d and d.reason
end

---------------------------------------------------------------- badge (minimap-style button)
local badge = CreateFrame("Button", "SelfFoundBadge", UIParent)
badge:SetSize(31, 31)
badge:SetFrameStrata("MEDIUM")
badge:SetMovable(true)
badge:SetClampedToScreen(true)
badge:RegisterForDrag("LeftButton")
badge:RegisterForClicks("LeftButtonUp", "RightButtonUp")
badge:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
badge:Hide()

local bBg = badge:CreateTexture(nil, "BACKGROUND")
bBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
bBg:SetSize(20, 20); bBg:SetPoint("TOPLEFT", 7, -5)
local bIcon = badge:CreateTexture(nil, "ARTWORK")
bIcon:SetSize(17, 17); bIcon:SetPoint("TOPLEFT", 7, -6)
bIcon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
local bCross = badge:CreateTexture(nil, "OVERLAY", nil, 1)
bCross:SetTexture(CROSS); bCross:SetSize(14, 14); bCross:SetPoint("CENTER", bIcon, "CENTER", 5, -5)
local bBorder = badge:CreateTexture(nil, "OVERLAY")
bBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
bBorder:SetSize(53, 53); bBorder:SetPoint("TOPLEFT")

local bStatus = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
bStatus:SetPoint("TOPLEFT", badge, "TOPRIGHT", 2, -5)
bStatus:SetJustifyH("LEFT")
local bSub = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
bSub:SetPoint("TOPLEFT", bStatus, "BOTTOMLEFT", 0, -1)
bSub:SetJustifyH("LEFT")

local function UpdateBadge()
  if not S then return end
  local status = myStatus()
  styleIcon(bIcon, bCross, status)
  bStatus:SetText(status == "SF" and ns.color("SF"):gsub("SF", "Self-Found") or ns.color(status))
  local p = ns.played and ns.played()
  bSub:SetText("Lv " .. UnitLevel("player") .. (p and ("  ·  " .. fmtPlayed(p)) or ""))
  if S.badgeText then bStatus:Show(); bSub:Show() else bStatus:Hide(); bSub:Hide() end
end

local function ApplyBadge()
  badge:SetScale(S.badgeScale)
  badge:ClearAllPoints()
  if S.point then
    badge:SetPoint(S.point[1], UIParent, S.point[2], S.point[3], S.point[4])
  else
    badge:SetPoint("TOPRIGHT", Minimap, "BOTTOMLEFT", 10, 0)
  end
  if S.badgeShown then badge:Show() else badge:Hide() end
  UpdateBadge()
end

badge:SetScript("OnDragStart", function(self) if not S.locked then self:StartMoving() end end)
badge:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint()
  S.point = { p, rp, x, y }
end)

local elapsedBadge = 0
badge:SetScript("OnUpdate", function(_, e)
  elapsedBadge = elapsedBadge + e
  if elapsedBadge > 5 then elapsedBadge = 0; UpdateBadge() end
end)

badge:SetScript("OnEnter", function(self)
  local status, reason = myStatus()
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Self-Found")
  GameTooltip:AddLine(ns.color(status))
  if reason and status ~= "SF" then GameTooltip:AddLine(reason, 0.8, 0.8, 0.8, true) end
  local p = ns.played and ns.played()
  if p then GameTooltip:AddDoubleLine("Played", fmtPlayed(p), 0.8, 0.8, 0.8, 1, 1, 1) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Left-click: players", 0.5, 0.8, 1)
  GameTooltip:AddLine("Right-click: settings", 0.5, 0.8, 1)
  if not S.locked then GameTooltip:AddLine("Drag: move", 0.5, 0.8, 1) end
  GameTooltip:Show()
end)
badge:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------- main panel
local panel = CreateFrame("Frame", "SelfFoundPanel", UIParent, BACKDROP_TEMPLATE)
panel:SetSize(320, 504)
panel:SetPoint("CENTER")
panel:SetBackdrop(DIALOG)
panel:SetFrameStrata("DIALOG")
panel:SetMovable(true)
panel:SetClampedToScreen(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
panel:Hide()
tinsert(UISpecialFrames, "SelfFoundPanel") -- Escape closes it

local header = panel:CreateTexture(nil, "ARTWORK")
header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
header:SetSize(256, 64); header:SetPoint("TOP", 0, 12)
local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", header, "TOP", 0, -14)
title:SetText("Self-Found")

local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -4, -4)

-- your status block
local pIcon = panel:CreateTexture(nil, "ARTWORK")
pIcon:SetSize(36, 36); pIcon:SetPoint("TOPLEFT", 22, -32)
local pCross = panel:CreateTexture(nil, "OVERLAY")
pCross:SetTexture(CROSS); pCross:SetSize(20, 20); pCross:SetPoint("BOTTOMRIGHT", pIcon, 4, -4)
local pStatus = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
pStatus:SetPoint("TOPLEFT", pIcon, "TOPRIGHT", 10, -1)
local pReason = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pReason:SetPoint("TOPLEFT", pStatus, "BOTTOMLEFT", 0, -3)
pReason:SetWidth(220); pReason:SetJustifyH("LEFT")

local divider = panel:CreateTexture(nil, "ARTWORK")
colorTex(divider, 1, 0.82, 0, 0.35)
divider:SetHeight(1)
divider:SetPoint("TOPLEFT", 20, -80); divider:SetPoint("TOPRIGHT", -20, -80)

local footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
footer:SetPoint("BOTTOMLEFT", 22, 22)
footer:SetWidth(118); footer:SetJustifyH("LEFT")
if footer.SetWordWrap then footer:SetWordWrap(false) end

local toggle = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
toggle:SetSize(90, 22); toggle:SetPoint("BOTTOMRIGHT", -18, 16)

---------------------------------------------------------------- players view
local players = CreateFrame("Frame", nil, panel)
players:SetPoint("TOPLEFT", 16, -88); players:SetPoint("BOTTOMRIGHT", -16, 44)

local RefreshList -- defined below

-- Guild / Everyone tabs
local tabs = {}
local function Tab(label, view, x)
  local b = CreateFrame("Button", nil, players, "UIPanelButtonTemplate")
  b:SetSize(90, 20); b:SetPoint("TOPLEFT", x, 0); b:SetText(label)
  b:SetScript("OnClick", function() S.view = view; RefreshList() end)
  b.view = view
  tabs[#tabs + 1] = b
end
Tab("Guild", "guild", 6)
Tab("Everyone", "all", 100)

local function colHeader(text, x)
  local f = players:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f:SetPoint("TOPLEFT", x, -28); f:SetText(text)
end
colHeader("Player", 8); colHeader("Lv", 138); colHeader("Status", 176)

local ROWS, offset, rows, list = 13, 0, {}, {}
local empty = players:CreateFontString(nil, "OVERLAY", "GameFontDisable")
empty:SetPoint("CENTER", 0, -10)
empty:SetWidth(260)

for i = 1, ROWS do
  local r = CreateFrame("Button", nil, players)
  r:SetSize(288, 20)
  r:SetPoint("TOPLEFT", 0, -44 - (i - 1) * 20)
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetPoint("LEFT", 8, 0); r.name:SetWidth(126); r.name:SetJustifyH("LEFT")
  r.level = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.level:SetPoint("LEFT", 138, 0)
  r.status = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.status:SetPoint("LEFT", 176, 0); r.status:SetWidth(110); r.status:SetJustifyH("LEFT")
  r:SetScript("OnEnter", function(self)
    local e = self.entry
    if not e then return end
    local p = e.p
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.name)
    if e.guild then GameTooltip:AddLine("Guild member" .. (e.online and " · online" or " · offline"), 0.25, 1, 0.25) end
    if p then
      GameTooltip:AddLine(ns.color(p.status))
      if p.reason and p.status ~= "SF" then GameTooltip:AddLine(p.reason, 0.8, 0.8, 0.8, true) end
      if p.liar then GameTooltip:AddLine("Their addon still claims a clean run.", 1, 0.3, 0.3, true) end
      if p.played and p.played > 0 then GameTooltip:AddDoubleLine("Played", fmtPlayed(p.played), 0.8, 0.8, 0.8, 1, 1, 1) end
      GameTooltip:AddDoubleLine("Last seen", fmtAgo(p.lastSeen), 0.8, 0.8, 0.8, 1, 1, 1)
    else
      GameTooltip:AddLine("Not running SelfFound (or not seen yet).", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
end

local function requestRoster()
  if not IsInGuild() then return end
  if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
end

local function guildMembers()
  local out, set = {}, {}
  if not IsInGuild() then return out, set end
  for i = 1, GetNumGuildMembers() do
    local name, _, _, level, _, _, _, _, online, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
    if name then
      name = name:gsub("%-.*", "")
      set[name] = true
      local p = ns.Find(name, guid)
      local isMe = ns.IsMe(name, guid)
      if isMe and SF_Char then p = SF_Char end
      out[#out + 1] = { name = name, p = p, level = level, online = online and true, guild = true, isMe = isMe }
    end
  end
  return out, set
end

local function statusText(e)
  local p = e.p
  if e.isMe and SF_Char then p = { status = SF_Char.status } end
  if not p then return "|cff777777No addon|r" end
  local s = p.status == "SF" and ns.color("SF"):gsub("SF", "Self-Found") or ns.color(p.status)
  return s .. (p.liar and " |cffff4444!|r" or "")
end

RefreshList = function()
  wipe(list)
  local members, guildSet = guildMembers()
  if S.view == "guild" then
    for _, e in ipairs(members) do list[#list + 1] = e end
  else
    for name, p in pairs(SF_Ledger or {}) do
      list[#list + 1] = { name = name, p = p, level = p.level, guild = guildSet[name], online = guildSet[name] and nil }
    end
  end
  table.sort(list, function(a, b)
    local ra = a.p and ns.RANK[a.p.status] or 9
    local rb = b.p and ns.RANK[b.p.status] or 9
    if ra ~= rb then return ra < rb end
    if (a.online and 1 or 0) ~= (b.online and 1 or 0) then return a.online and true or false end
    return a.name < b.name
  end)

  offset = math.max(0, math.min(offset, #list - ROWS))
  for i = 1, ROWS do
    local r, e = rows[i], list[i + offset]
    r.entry = e
    if e then
      local dot = ""
      if e.guild then dot = e.online and "|cff40ff40•|r " or "|cff555555•|r " end
      r.name:SetText(dot .. e.name)
      if e.guild and not e.online and S.view == "guild" then r.name:SetTextColor(0.6, 0.6, 0.6) else r.name:SetTextColor(1, 1, 1) end
      r.level:SetText(e.level or "?")
      r.status:SetText(statusText(e))
      r:Show()
    else
      r:Hide()
    end
  end

  for _, t in ipairs(tabs) do
    if t.view == S.view then t:LockHighlight() else t:UnlockHighlight() end
  end

  local count, sf = #list, 0
  for _, e in ipairs(list) do if e.p and e.p.status == "SF" then sf = sf + 1 end end
  if S.view == "guild" then
    empty:SetText(IsInGuild() and "Loading guild roster..." or "You're not in a guild.\nTry the Everyone tab.")
    footer:SetText(S.network == "off" and "Solo mode" or (sf .. " of " .. count .. " Self-Found"))
  else
    empty:SetText(S.network == "everyone" and "Nobody seen yet.\nPress Refresh to call out to the server."
      or "Only guild and party players show here.\nTurn on \"Everyone on the server\" in Settings to see more.")
    footer:SetText(count .. " seen")
  end
  if count == 0 then empty:Show() else empty:Hide() end
end

players:EnableMouseWheel(true)
players:SetScript("OnMouseWheel", function(_, delta)
  offset = offset - delta * 3
  RefreshList()
end)

local refresh = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
refresh:SetSize(72, 22); refresh:SetPoint("RIGHT", toggle, "LEFT", -4, 0)
refresh:SetText("Refresh")
refresh:SetScript("OnClick", function()
  requestRoster()
  if not ns.RollCall() then ns.say("Just refreshed - try again in a few seconds.") end
  RefreshList()
end)

---------------------------------------------------------------- settings view
local settings = CreateFrame("Frame", nil, panel)
settings:SetPoint("TOPLEFT", 16, -88); settings:SetPoint("BOTTOMRIGHT", -16, 44)
settings:Hide()

local function Check(label, key, y, onChange)
  local cb = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
  cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", 4, y)
  local t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  t:SetPoint("LEFT", cb, "RIGHT", 2, 1); t:SetText(label)
  cb:SetScript("OnShow", function(self) self:SetChecked(S[key]) end)
  cb:SetScript("OnClick", function(self)
    S[key] = self:GetChecked() and true or false
    if onChange then onChange() end
  end)
end

local sliderCount = 0
local function Slider(label, key, minV, maxV, y, onChange, applyOnRelease)
  sliderCount = sliderCount + 1
  local name = "SelfFoundSlider" .. sliderCount
  local s = CreateFrame("Slider", name, settings, "OptionsSliderTemplate")
  s:SetWidth(230); s:SetPoint("TOPLEFT", 26, y)
  s:SetMinMaxValues(minV, maxV); s:SetValueStep(0.05)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  local low, high = s.Low or _G[name .. "Low"], s.High or _G[name .. "High"]
  local text = s.Text or _G[name .. "Text"]
  if low then low:SetText(math.floor(minV * 100) .. "%") end
  if high then high:SetText(math.floor(maxV * 100) .. "%") end
  local function setLabel()
    if text then text:SetText(label .. ": " .. math.floor(S[key] * 100 + 0.5) .. "%") end
  end
  s:SetScript("OnShow", function(self) self:SetValue(S[key]); setLabel() end)
  s:SetScript("OnValueChanged", function(_, v)
    S[key] = math.floor(v * 20 + 0.5) / 20
    setLabel()
    if not applyOnRelease and onChange then onChange() end
  end)
  if applyOnRelease then s:SetScript("OnMouseUp", onChange) end
end

local function ApplyPanel() panel:SetScale(S.panelScale) end

Check("Show badge", "badgeShown", 0, ApplyBadge)
Check("Show status text next to badge", "badgeText", -24, UpdateBadge)
Check("Lock badge position", "locked", -48)
Check("Warn before trade, mail and auction house", "warnings", -72)
Check("Big alert when a player breaks", "alerts", -96)
Check("Play sound with alerts", "sound", -120)
-- Network: radio-style pair
local netLabel = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal")
netLabel:SetPoint("TOPLEFT", 8, -152); netLabel:SetText("Connect with")
local radios = {}
local function Radio(label, mode, y)
  local rb = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
  rb:SetSize(24, 24); rb:SetPoint("TOPLEFT", 4, y)
  local t = rb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  t:SetPoint("LEFT", rb, "RIGHT", 2, 1); t:SetText(label)
  rb.mode = mode
  rb:SetScript("OnShow", function(self) self:SetChecked(S.network == self.mode) end)
  rb:SetScript("OnClick", function(self)
    ns.SetNetwork(self.mode)
    for _, r in ipairs(radios) do r:SetChecked(S.network == r.mode) end
  end)
  radios[#radios + 1] = rb
end
Radio("My guild (and party)", "guild", -170)
Radio("Everyone on the server", "everyone", -194)
Radio("Nobody (only track me)", "off", -218)

Slider("Badge size", "badgeScale", 0.5, 2, -264, ApplyBadge)
Slider("Window size", "panelScale", 0.7, 1.5, -308, ApplyPanel, true)

local reset = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
reset:SetSize(150, 22); reset:SetPoint("TOPLEFT", 26, -348)
reset:SetText("Reset badge position")
reset:SetScript("OnClick", function() S.point = nil; ApplyBadge() end)

---------------------------------------------------------------- panel logic
local function RefreshHeader()
  local status, reason = myStatus()
  styleIcon(pIcon, pCross, status)
  pStatus:SetText(status == "SF" and ns.color("SF"):gsub("SF", "Self-Found") or ns.color(status))
  if status == "SF" then
    pReason:SetText("Clean run  ·  " .. fmtPlayed(ns.played and ns.played()) .. " played")
  else
    pReason:SetText(reason or "")
  end
end

local function ShowView(which)
  if which == "settings" then
    players:Hide(); settings:Show(); toggle:SetText("Players"); footer:Hide(); refresh:Hide()
  else
    settings:Hide(); players:Show(); toggle:SetText("Settings"); footer:Show(); refresh:Show()
    requestRoster()
    RefreshList()
  end
end

toggle:SetScript("OnClick", function()
  ShowView(settings:IsShown() and "players" or "settings")
end)
panel:SetScript("OnShow", function() RefreshHeader(); RefreshList() end)

local function OpenPanel(view)
  panel:Show()
  ShowView(view)
end

badge:SetScript("OnClick", function(_, button)
  if panel:IsShown() and ((button == "RightButton") == settings:IsShown()) then
    panel:Hide()
  else
    OpenPanel(button == "RightButton" and "settings" or "players")
  end
end)

---------------------------------------------------------------- warnings
StaticPopupDialogs["SELFFOUND_TRADE"] = {
  text = "|cffffd100Self-Found|r\n\nCompleting this trade with %s ends your Self-Found run. Everyone with the addon will see it.",
  button1 = "Trade anyway", button2 = "Cancel trade",
  OnCancel = function() CancelTrade() end,
  timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
}
StaticPopupDialogs["SELFFOUND_MAIL"] = {
  text = "|cffffd100Self-Found|r\n\nTaking items or gold sent by another player ends your run. Mail from NPCs and auction sales is fine.",
  button1 = "Got it", button2 = "Close mailbox",
  OnCancel = function() CloseMail() end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
StaticPopupDialogs["SELFFOUND_AH"] = {
  text = "|cffffd100Self-Found|r\n\nBuying from the auction house ends your run. Selling is fine.",
  button1 = "Got it", button2 = "Leave",
  OnCancel = function()
    if C_AuctionHouse and C_AuctionHouse.CloseAuctionHouse then C_AuctionHouse.CloseAuctionHouse()
    elseif CloseAuctionHouse then CloseAuctionHouse() end
  end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local warnedMail, warnedAH = false, false
local function shouldWarn()
  return S and S.warnings and SF_Char and SF_Char.status ~= "BROKEN"
end

---------------------------------------------------------------- hooks from core
ns.OnReady = function() UpdateBadge() end

ns.OnSelfChange = function(status, reason)
  UpdateBadge()
  if panel:IsShown() then RefreshHeader() end
  if status == "BROKEN" then alert("Your Self-Found run has ended") end
end

ns.OnPeerChange = function(name, status, reason)
  if panel:IsShown() then RefreshList() end
  if status == "BROKEN" then alert(name .. " is no longer Self-Found") end
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("GUILD_ROSTER_UPDATE")
ev:RegisterEvent("TRADE_SHOW")
ev:RegisterEvent("TRADE_CLOSED")
ev:RegisterEvent("MAIL_SHOW")
ev:RegisterEvent("MAIL_CLOSED")
ev:RegisterEvent("AUCTION_HOUSE_SHOW")
ev:RegisterEvent("AUCTION_HOUSE_CLOSED")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    SF_Settings = SF_Settings or {}
    S = SF_Settings
    for k, v in pairs(DEFAULTS) do if S[k] == nil then S[k] = v end end
    ApplyBadge(); ApplyPanel()
  elseif event == "PLAYER_LEVEL_UP" then
    UpdateBadge()
  elseif event == "GUILD_ROSTER_UPDATE" then
    if players:IsShown() and panel:IsShown() then RefreshList() end
  elseif event == "TRADE_SHOW" and shouldWarn() then
    StaticPopup_Show("SELFFOUND_TRADE", UnitName("NPC") or "this player")
  elseif event == "TRADE_CLOSED" then
    StaticPopup_Hide("SELFFOUND_TRADE")
  elseif event == "MAIL_SHOW" and shouldWarn() and not warnedMail then
    warnedMail = true
    StaticPopup_Show("SELFFOUND_MAIL")
  elseif event == "MAIL_CLOSED" then
    StaticPopup_Hide("SELFFOUND_MAIL")
  elseif event == "AUCTION_HOUSE_SHOW" and shouldWarn() and not warnedAH then
    warnedAH = true
    StaticPopup_Show("SELFFOUND_AH")
  elseif event == "AUCTION_HOUSE_CLOSED" then
    StaticPopup_Hide("SELFFOUND_AH")
  end
end)

---------------------------------------------------------------- slash commands
local coreSlash = SlashCmdList.SELFFOUND
SlashCmdList.SELFFOUND = function(arg)
  arg = (arg or ""):lower()
  if arg == "" then
    if panel:IsShown() then panel:Hide() else OpenPanel("players") end
  elseif arg == "settings" or arg == "config" then
    OpenPanel("settings")
  elseif arg == "reset" then
    if S then S.point = nil; ApplyBadge() end
  else
    coreSlash(arg)
  end
end
