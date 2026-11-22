-- Guild Ranks: player card (beside the main window), invite dialog, first-time welcome
local ADDON, ns = ...
local L = ns.L

local function H() return ns.UI.H end

---------------------------------------------------------------------------
-- Player card: click a name on the leaderboard
---------------------------------------------------------------------------
local Card = {}
ns.Card = Card
local card, body
local pool = { fs = {}, tex = {} }
local used = { fs = 0, tex = 0 }
local y = 0
local CARD_W, INNER_W = 300, 250

local function NextFS(font, justify)
	used.fs = used.fs + 1
	local f = pool.fs[used.fs]
	if not f then
		f = H().FS(body, font)
		pool.fs[used.fs] = f
	end
	f:SetFontObject(font or "GameFontHighlight")
	f:SetJustifyH(justify or "LEFT")
	f:SetTextColor(1, 1, 1)
	f:SetWordWrap(false)
	f:ClearAllPoints()
	f:Show()
	return f
end

local function NextTex()
	used.tex = used.tex + 1
	local t = pool.tex[used.tex]
	if not t then
		t = body:CreateTexture(nil, "ARTWORK")
		pool.tex[used.tex] = t
	end
	t:ClearAllPoints()
	t:Show()
	return t
end

local function Section(text, right)
	y = y - 8
	local f = NextFS("GameFontNormalSmall")
	f:SetPoint("TOPLEFT", 0, y); f:SetWidth(INNER_W); f:SetText(text)
	if right then
		local r = NextFS("GameFontDisableSmall", "RIGHT")
		r:SetPoint("TOPRIGHT", body, "TOPLEFT", INNER_W, y); r:SetWidth(140); r:SetText(right)
	end
	y = y - 16
end

local function Pair(left, right)
	local l = NextFS("GameFontHighlightSmall")
	l:SetPoint("TOPLEFT", 0, y); l:SetWidth(120); l:SetText(left)
	local r = NextFS("GameFontHighlightSmall", "RIGHT")
	r:SetPoint("TOPRIGHT", body, "TOPLEFT", INNER_W, y); r:SetWidth(INNER_W - 110); r:SetText(right)
	y = y - 15
end

local function Bar(label, value)
	local l = NextFS("GameFontHighlightSmall")
	l:SetPoint("TOPLEFT", 0, y); l:SetWidth(96); l:SetText(label)
	local bg = NextTex()
	bg:SetPoint("TOPLEFT", 100, y - 4); bg:SetSize(118, 6)
	bg:SetColorTexture(0.16, 0.17, 0.2, 1)
	local fill = NextTex()
	fill:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0); fill:SetSize(math.max(1, 118 * math.min(1, (value or 0) / 100)), 6)
	fill:SetColorTexture(0.79, 0.64, 0.15, 1)
	local v = NextFS("GameFontHighlightSmall", "RIGHT")
	v:SetPoint("TOPRIGHT", body, "TOPLEFT", INNER_W, y); v:SetWidth(28); v:SetText(tostring(math.floor((value or 0) + 0.5)))
	y = y - 16
end

local function Text(text, font)
	local f = NextFS(font or "GameFontHighlightSmall")
	f:SetPoint("TOPLEFT", 0, y); f:SetWidth(INNER_W); f:SetWordWrap(true); f:SetText(text)
	y = y - math.max(14, (f:GetStringHeight() or 14) + 2)
end

local function Tile(x, label, value, extra)
	local l = NextFS("GameFontDisableSmall")
	l:SetPoint("TOPLEFT", x, y); l:SetText(label)
	local v = NextFS("GameFontHighlightLarge")
	v:SetPoint("TOPLEFT", x, y - 14); v:SetText(value .. (extra and ("  " .. extra) or ""))
end

local function CreateCard()
	local main = ns.UI.Frame()
	card = CreateFrame("Frame", "GuildRanksCard", main, "BackdropTemplate")
	card:SetSize(CARD_W, 660)
	card:SetPoint("TOPLEFT", main, "TOPRIGHT", -6, 0)
	card:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	card:EnableMouse(true)
	card:SetClampedToScreen(true)
	card:Hide()
	local close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function() Card.Hide() end)
	card.name = H().FS(card, "GameFontNormalLarge")
	card.name:SetPoint("TOPLEFT", 22, -18); card.name:SetWidth(230)
	card.sub = H().FS(card, "GameFontDisableSmall")
	card.sub:SetPoint("TOPLEFT", 22, -38); card.sub:SetWidth(170)
	card.rival = H().MakeButton(card, L["Set as rival"], 96, function()
		if not Card.key then return end
		local P = ns.Personal
		P.SetRival(P.Rival() == Card.key and nil or Card.key)
		Card.Refresh()
	end)
	card.rival:SetHeight(18)
	card.rival:SetPoint("TOPRIGHT", -30, -36)
	card.versus = H().MakeButton(card, L["Challenge"], 80, function()
		if Card.key and ns.VersusUI then ns.VersusUI.ShowDialog(Card.key) end
	end)
	card.versus:SetHeight(18)
	card.versus:SetPoint("RIGHT", card.rival, "LEFT", -4, 0)
	local sf, child = H().MakeScroll(card, -56, INNER_W)
	sf:ClearAllPoints()
	sf:SetPoint("TOPLEFT", 22, -60)
	sf:SetPoint("BOTTOMRIGHT", -30, 16)
	body = child
end

local function ClassName(class)
	local names = LOCALIZED_CLASS_NAMES_MALE
	return (class and names and names[class]) or ""
end

function Card.Refresh()
	if not card or not card:IsShown() or not Card.key then return end
	local g = ns.V()
	local key = Card.key
	local p = g and g.players[key]
	if not p then Card.Hide(); return end
	local view = ns.db.view
	local period = ns.PERIOD_BY_KEY[view.period] or ns.PERIODS[2]
	for _, f in ipairs(pool.fs) do f:Hide() end
	for _, t in ipairs(pool.tex) do t:Hide() end
	used.fs, used.tex, y = 0, 0, 0

	card.name:SetText(H().ClassColored(ns.ShortName(key), p.class))
	local cls = ClassName(p.class)
	local title = ns.Personal and ns.Personal.ShownTitle(g, key)
	card.sub:SetText((title and ("|cffffd100<" .. title.name .. ">|r  ") or "") .. (cls ~= "" and (cls .. "  ·  ") or "")
		.. string.format(L["level %d"], p.level or 0))
	local canRival = ns.Personal.CanBeRival(key) and not g.solo and not g.demo
	card.rival:SetShown(canRival)
	if canRival then card.rival:SetText(ns.Personal.Rival() == key and L["Your rival"] or L["Set as rival"]) end
	card.versus:SetShown(ns.Versus.CanChallenge(key) and not g.demo)

	local b = ns.Aggregate(p, view.period, g)
	local secs = b.playtime or 0
	local scores = ns.ComputeScores(g, view.period, view.bracket)
	local entry, rank
	for i, e in ipairs(scores) do if e.key == key then entry, rank = e, i end end
	local change = entry and ns.RankChanges(g, scores, "score", view.period, false, view.bracket)[key]
	local changeText = ""
	if change == "new" then changeText = "|cff5ac8fa" .. L["new"] .. "|r"
	elseif change and change > 0 then changeText = "|cff40ff40+" .. change .. "|r"
	elseif change and change < 0 then changeText = "|cffff5050" .. change .. "|r" end

	Tile(0, period.label, rank and ("|cffffd100#" .. rank .. "|r") or "-", rank and ("|cff808080" .. string.format(L["of %d"], #scores) .. "|r") or nil)
	Tile(96, L["Guild score"], entry and tostring(entry.score) or "-", changeText ~= "" and changeText or nil)
	Tile(184, L["MVP"], "|TInterface\\Icons\\INV_Misc_Trophy_Gold:16:16|t " .. ns.Hall.MVPCount(g, key))
	y = y - 40

	if entry then
		Section(L["Score breakdown"])
		for _, cat in ipairs(ns.SCORE_CATEGORIES) do Bar(cat.label, entry.cats[cat.key]) end
	else
		Section(L["Score breakdown"])
		Text(string.format(L["Not ranked yet: %s of %d min played in this period."],
			ns.PlaytimeShownFor(g, key) and ns.FormatTime(secs) or L["hidden"], g.rules.minMinutes))
	end

	local hours = secs / 3600
	Section(string.format(L["Stats (%s)"], period.label:lower()), L["total  ·  per hour"])
	for _, m in ipairs(ns.METRICS) do
		if m.key ~= "score" and m.key ~= "playtime" then
			local total = ns.MetricTotal(b, m.key, g)
			if total > 0 or m.lowerIsBetter then
				local right = ns.FormatValue(m, total, false)
				if hours > 0 and m.rate then right = right .. "  |cff999999" .. ns.FormatValue(m, total / hours, true) .. "|r" end
				Pair(m.short, right)
			end
		end
	end
	if ns.PlaytimeShownFor(g, key) then Pair(L["Played"], ns.FormatTime(secs)) end

	local any = false
	for _, src in ipairs(ns.GOLD_SOURCES) do
		local v = b["g_" .. src] or 0
		if v > 0 then
			if not any then Section(L["Gold by source"]); any = true end
			local label = ns.GOLD_SOURCE_LABELS[src]
			if not g.rules.gold[src] then label = label .. " |cff999999(" .. L["not counted"] .. ")|r" end
			Pair(label, ns.FormatMoney(v))
		end
	end

	local history = ns.Hall.History(g, key, 6)
	if #history > 0 then
		Section(L["Recent weeks"])
		for _, hw in ipairs(history) do
			local t = ns.KeyToTime(hw.from)
			Pair(t and date("%d %b", t) or hw.from, string.format(L["#%d of %d  ·  score %d"], hw.rank, hw.n, hw.score))
		end
	end
	if p.version then
		y = y - 8
		Text("|cff808080" .. L["Guild Ranks"] .. " " .. p.version .. "|r")
	end
	body:SetHeight(math.max(1, -y + 8))
end

function Card.Show(key)
	if not ns.UI.Frame() then return end
	if not card then CreateCard() end
	Card.key = key
	card:Show()
	Card.Refresh()
	ns.UI.Refresh()
end

function Card.Hide()
	local was = Card.key
	Card.key = nil
	if card then card:Hide() end
	if was and ns.UI.Frame() and ns.UI.Frame():IsShown() then ns.UI.Refresh() end
end

function Card.Toggle(key)
	if Card.key == key and card and card:IsShown() then Card.Hide() else Card.Show(key) end
end

function Card.IsShown() return card ~= nil and card:IsShown() end
function Card.Texts() -- for the automated tests
	local out = {}
	for i = 1, used.fs do out[#out + 1] = pool.fs[i]:GetText() or "" end
	return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- Invite guildmates: a message to post in guild chat or copy for Discord
---------------------------------------------------------------------------
local Invite = {}
ns.Invite = Invite
local dlg

local function CreateInvite()
	dlg = CreateFrame("Frame", "GuildRanksInvite", UIParent, "BackdropTemplate")
	dlg:SetSize(460, 196)
	dlg:SetPoint("CENTER", 0, 120)
	dlg:SetFrameStrata("DIALOG")
	dlg:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	dlg:EnableMouse(true)
	dlg:SetMovable(true)
	dlg:RegisterForDrag("LeftButton")
	dlg:SetScript("OnDragStart", dlg.StartMoving)
	dlg:SetScript("OnDragStop", dlg.StopMovingOrSizing)
	dlg:Hide()
	tinsert(UISpecialFrames, "GuildRanksInvite")
	local close = CreateFrame("Button", nil, dlg, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)
	local title = H().FS(dlg, "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 22, -18)
	title:SetText(L["Invite guildmates"])
	dlg.count = H().FS(dlg, "GameFontDisableSmall")
	dlg.count:SetPoint("TOPLEFT", 22, -40)
	dlg.edit = CreateFrame("EditBox", nil, dlg, "InputBoxTemplate")
	dlg.edit:SetSize(410, 24)
	dlg.edit:SetPoint("TOPLEFT", 26, -62)
	dlg.edit:SetAutoFocus(false)
	dlg.edit:SetScript("OnEscapePressed", function() dlg:Hide() end)
	dlg.edit:SetScript("OnTextChanged", function(self, user) if user then self:SetText(dlg.msg); self:HighlightText() end end)
	dlg.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	local hint = H().FS(dlg, "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", 22, -92)
	hint:SetText(L["To copy for Discord: click the text, press Ctrl+C, then paste in Discord."])
	dlg.post = H().MakeButton(dlg, L["Post in guild chat"], 160, function()
		local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
		if IsInGuild() and dlg.msg and send then
			send(dlg.msg, "GUILD")
			ns.Print(L["Invite posted in guild chat."])
			dlg:Hide()
		end
	end)
	dlg.post:SetPoint("BOTTOMLEFT", 20, 18)
	local copy = H().MakeButton(dlg, L["Select text to copy"], 150, function()
		dlg.edit:SetFocus()
		dlg.edit:HighlightText()
	end)
	copy:SetPoint("LEFT", dlg.post, "RIGHT", 6, 0)
	local done = H().MakeButton(dlg, L["Close"], 80, function() dlg:Hide() end)
	done:SetPoint("BOTTOMRIGHT", -20, 18)
end

function Invite.Show()
	if not dlg then CreateInvite() end
	dlg.msg = ns.InviteMessage()
	dlg.edit:SetText(dlg.msg)
	local g = ns.G()
	local with, total = ns.UI.AddonUsers(g)
	dlg.count:SetText(with and string.format(L["%d of %d members use Guild Ranks"], with, total) or "")
	if IsInGuild() then dlg.post:Enable() else dlg.post:Disable() end
	dlg:Show()
	dlg.edit:SetFocus()
	dlg.edit:HighlightText()
end

function Invite.Message() return dlg and dlg.msg end
function Invite.Post() if dlg then dlg.post:GetScript("OnClick")(dlg.post) end end

---------------------------------------------------------------------------
-- Welcome: shown once, the first time the leaderboard opens
---------------------------------------------------------------------------
local Welcome = {}
ns.Welcome = Welcome
local wf

local loadedAt = GetTime() -- about when you logged in

-- Which welcome to show:
--   "joined"  guildmates already use Guild Ranks: "You're #9 in Froga!"
--   "first"   nobody else in the guild has it (after a minute and a half of listening)
--   "generic" not in a guild, sample data, or the guild's data hasn't arrived yet
function Welcome.Variant(g)
	if not g or g.solo or g.demo then return "generic" end
	local others = 0
	for key in pairs(g.players) do if key ~= ns.me then others = others + 1 end end
	if others > 0 then return "joined", others end
	if GetTime() - loadedAt >= 90 then return "first", 0 end
	return "generic", 0
end

local function Guildmates(g, max)
	local list = {}
	for key, p in pairs(g.players) do if key ~= ns.me then list[#list + 1] = { key = key, p = p } end end
	table.sort(list, function(a, b)
		if (a.p.seen or 0) ~= (b.p.seen or 0) then return (a.p.seen or 0) > (b.p.seen or 0) end
		return a.key < b.key
	end)
	local names = {}
	for i = 1, math.min(max, #list) do names[i] = H().ClassColored(ns.ShortName(list[i].key), list[i].p.class) end
	local text = table.concat(names, ", ")
	if #list > max then text = text .. "  |cff8a8a8a" .. string.format(L["and %d more"], #list - max) .. "|r" end
	return text
end

local function CreateWelcome()
	local main = ns.UI.Frame()
	wf = CreateFrame("Frame", nil, main)
	wf:SetPoint("TOPLEFT", 12, -66)
	wf:SetPoint("BOTTOMRIGHT", -12, 12)
	wf:SetFrameLevel(100)
	wf:EnableMouse(true)
	local shade = wf:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(0, 0, 0, 0.88)
	wf.title = H().FS(wf, "GameFontNormalHuge", "CENTER")
	wf.title:SetPoint("TOP", 0, -90)
	wf.title:SetWidth(540)
	-- generic: three numbered lines
	local lines = {
		L["Play as usual. Your gold, XP, damage and more are counted per hour."],
		L["Guildmates with the addon show up here by themselves."],
		L["Every week the best Guild score becomes MVP."],
	}
	wf.steps = {}
	for i, text in ipairs(lines) do
		local n = H().FS(wf, "GameFontNormalLarge", "RIGHT")
		n:SetPoint("TOPLEFT", 70, -130 - (i - 1) * 34)
		n:SetWidth(20)
		n:SetText(tostring(i))
		local t = H().FS(wf, "GameFontHighlight")
		t:SetPoint("LEFT", n, "RIGHT", 12, 0)
		t:SetWidth(380)
		t:SetWordWrap(true)
		t:SetText(text)
		wf.steps[#wf.steps + 1] = n
		wf.steps[#wf.steps + 1] = t
	end
	-- joined / first: a lead line, the guildmates, what happens next
	wf.lead = H().FS(wf, "GameFontHighlight", "CENTER")
	wf.lead:SetPoint("TOP", 0, -132); wf.lead:SetWidth(480); wf.lead:SetWordWrap(true)
	wf.names = H().FS(wf, "GameFontHighlight", "CENTER")
	wf.names:SetPoint("TOP", 0, -156); wf.names:SetWidth(480); wf.names:SetWordWrap(true)
	wf.tip = H().FS(wf, "GameFontDisableSmall", "CENTER")
	wf.tip:SetPoint("TOP", 0, -248)
	wf.tip:SetWidth(460)
	wf.tip:SetWordWrap(true)
	wf.left = H().MakeButton(wf, "", 150, function() if wf.leftAction then wf.leftAction() end end)
	wf.left:SetPoint("TOP", -80, -290)
	wf.right = H().MakeButton(wf, "", 150, function() if wf.rightAction then wf.rightAction() end end)
	wf.right:SetPoint("TOP", 80, -290)
	wf:Hide()
end

-- Fill in the welcome for the guild being viewed (called again when guildmates' data arrives)
function Welcome.Update()
	if not wf then return end
	local g = ns.V()
	local variant, others = Welcome.Variant(g)
	wf.variant = variant
	local generic = variant == "generic"
	for _, el in ipairs(wf.steps) do el:SetShown(generic) end
	wf.lead:SetShown(not generic); wf.names:SetShown(variant == "joined")
	if variant == "joined" then
		wf.title:SetText(string.format(L["You're #%d in %s!"], others + 1, g.name))
		wf.lead:SetText(string.format(others == 1 and L["%d guildmate already uses Guild Ranks:"] or L["%d guildmates already use Guild Ranks:"], others))
		wf.names:SetText(Guildmates(g, 5))
		wf.tip:SetText(string.format(L["Your stats count from now. You'll show up on the leaderboard after %d min of play."], g.rules.minMinutes or 0))
		wf.left:SetText(L["See the leaderboard"]); wf.leftAction = function() Welcome.Done() end
		wf.right:SetText(L["Open your Me tab"]); wf.rightAction = function() Welcome.Done(); ns.UI.Show("me") end
	elseif variant == "first" then
		wf.title:SetText(string.format(L["You're the first in %s"], g.name))
		wf.lead:SetText(L["Guild Ranks is more fun with guildmates. Invite them and they'll show up here by themselves."])
		wf.tip:SetText(L["Your stats count from now. Officers set the guild's rules in Settings."])
		wf.left:SetText(L["Invite"]); wf.leftAction = function() Welcome.Done(); if ns.Invite then ns.Invite.Show() end end
		wf.right:SetText(L["Show sample data"]); wf.rightAction = function() Welcome.Done(); ns.Tools.Demo(true) end
	else
		wf.title:SetText(L["Welcome to Guild Ranks"])
		wf.tip:SetText(L["Click a name for details. Officers set the guild's rules in Settings."])
		wf.left:SetText(L["Show sample data"]); wf.leftAction = function() Welcome.Done(); ns.Tools.Demo(true) end
		wf.right:SetText(L["Got it"]); wf.rightAction = function() Welcome.Done() end
	end
end

function Welcome.Texts() -- for the automated tests
	if not (wf and wf:IsShown()) then return nil end
	local out = { wf.title:GetText(), wf.left:GetText(), wf.right:GetText() }
	if wf.lead:IsShown() then out[#out + 1] = wf.lead:GetText() end
	if wf.names:IsShown() then out[#out + 1] = wf.names:GetText() end
	out[#out + 1] = wf.tip:GetText()
	return table.concat(out, "\n")
end
function Welcome.Click(which) -- for the automated tests: "left" or "right"
	local b = wf and wf[which]
	if b then b:GetScript("OnClick")(b) end
end

-- Shows the welcome the first time (or always, when force is true)
local open = false -- shown and not dismissed yet (survives switching tabs)
function Welcome.Show(force)
	if not ns.UI.Frame() then return end
	if force then open = true end
	if not open and ns.db.ui.welcomed then return end
	open = true
	if not wf then CreateWelcome() end
	Welcome.Update()
	wf:Show()
end

-- Step aside while another tab is open (it comes back on the leaderboard until dismissed)
function Welcome.Hide()
	if wf then wf:Hide() end
end

function Welcome.Done()
	open = false
	ns.db.ui.welcomed = true
	if wf then wf:Hide() end
	ns.UI.Refresh()
end

function Welcome.IsShown() return wf ~= nil and wf:IsShown() end

---------------------------------------------------------------------------
-- 1v1 challenges: the challenge dialog, the Accept/Decline popup and the race bar
---------------------------------------------------------------------------
local VersusUI = {}
ns.VersusUI = VersusUI
local dialog, invite, bar

local function Dialog(name, w, h)
	local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	f:SetSize(w, h)
	f:SetFrameStrata("DIALOG")
	f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
	f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	return f
end

local function ChipRow(parent, x, y, options, getter, setter)
	local chips = {}
	for _, o in ipairs(options) do
		local c = CreateFrame("Button", nil, parent)
		c:SetSize(o[3] or 60, 20)
		c:SetPoint("TOPLEFT", x, y)
		c.bg = c:CreateTexture(nil, "BACKGROUND"); c.bg:SetAllPoints()
		c.text = H().FS(c, "GameFontHighlightSmall", "CENTER"); c.text:SetPoint("CENTER"); c.text:SetText(o[2])
		c.value = o[1]
		c:SetScript("OnClick", function() setter(o[1]); VersusUI.RefreshDialog() end)
		chips[#chips + 1] = c
		x = x + (o[3] or 60) + 4
	end
	return function()
		for _, c in ipairs(chips) do
			if getter() == c.value then c.bg:SetColorTexture(0.45, 0.36, 0.08, 0.9); c.text:SetTextColor(1, 0.82, 0)
			else c.bg:SetColorTexture(0.16, 0.16, 0.18, 0.9); c.text:SetTextColor(0.85, 0.82, 0.75) end
		end
	end
end

function VersusUI.ShowDialog(key)
	if not dialog then
		dialog = Dialog("GuildRanksChallenge", 300, 196)
		dialog:SetPoint("CENTER", 0, 120)
		tinsert(UISpecialFrames, "GuildRanksChallenge")
		local x = CreateFrame("Button", nil, dialog, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT", -6, -6)
		local title = H().FS(dialog, "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 22, -18); title:SetText(L["Challenge a guildmate"])
		local who = H().FS(dialog, "GameFontHighlightSmall"); who:SetPoint("TOPLEFT", 22, -54); who:SetText(L["Who"])
		dialog.who = ns.UI.MakeDropdown(dialog, 170, function()
			local o = {}
			for _, k in ipairs(ns.Versus.Opponents()) do o[#o + 1] = { value = k, text = ns.ShortName(k) } end
			if #o == 0 then o[1] = { value = "", text = L["nobody online with Guild Ranks"] } end
			return o
		end, function() return dialog.target end, function(val) dialog.target = val ~= "" and val or nil; VersusUI.RefreshDialog() end)
		dialog.who:SetPoint("TOPLEFT", 90, -48)
		local what = H().FS(dialog, "GameFontHighlightSmall"); what:SetPoint("TOPLEFT", 22, -86); what:SetText(L["What"])
		dialog.refreshMetric = ChipRow(dialog, 90, -82, { { "gold", L["Gold"], 50 }, { "xp", L["XP"], 40 }, { "kills", L["Kills"], 50 } },
			function() return dialog.metric end, function(v) dialog.metric = v end)
		local long = H().FS(dialog, "GameFontHighlightSmall"); long:SetPoint("TOPLEFT", 22, -116); long:SetText(L["How long"])
		dialog.refreshSecs = ChipRow(dialog, 90, -112, { { 1800, L["30 min"], 60 }, { 3600, L["1 hour"], 60 } },
			function() return dialog.secs end, function(v) dialog.secs = v end)
		dialog.send = H().MakeButton(dialog, L["Send challenge"], 140, function()
			if dialog.target and ns.Versus.Challenge(dialog.target, dialog.metric, dialog.secs) then dialog:Hide() end
		end)
		dialog.send:SetPoint("BOTTOMLEFT", 20, 18)
		local cancel = H().MakeButton(dialog, L["Cancel"], 80, function() dialog:Hide() end)
		cancel:SetPoint("BOTTOMRIGHT", -20, 18)
		dialog.metric, dialog.secs = "gold", 3600
	end
	dialog.target = (key and ns.Versus.CanChallenge(key)) and key or ns.Versus.Opponents()[1]
	dialog:Show()
	VersusUI.RefreshDialog()
	return true
end

function VersusUI.RefreshDialog()
	if not dialog or not dialog:IsShown() then return end
	if dialog.who.Refresh then dialog.who:Refresh() end
	dialog.refreshMetric(); dialog.refreshSecs()
	if dialog.target then dialog.send:Enable() else dialog.send:Disable() end
end
function VersusUI.DialogState() return dialog and dialog:IsShown() and dialog.target, dialog and dialog.metric, dialog and dialog.secs end -- tests
function VersusUI.SendFromDialog() if dialog then dialog.send:GetScript("OnClick")(dialog.send) end end -- tests

-- "Joe Mario challenges you to a 1-hour gold race!"
function ns.UI.ShowVersusInvite(inc)
	if not invite then
		invite = Dialog("GuildRanksChallengeInvite", 340, 120)
		invite:SetPoint("TOP", 0, -160)
		invite.text = H().FS(invite, "GameFontHighlight", "CENTER")
		invite.text:SetPoint("TOP", 0, -24); invite.text:SetWidth(300); invite.text:SetWordWrap(true)
		local yes = H().MakeButton(invite, L["Accept"], 110, function() ns.Versus.Answer(true) end)
		yes:SetPoint("BOTTOMLEFT", 24, 18)
		local no = H().MakeButton(invite, L["Decline"], 110, function() ns.Versus.Answer(false) end)
		no:SetPoint("BOTTOMRIGHT", -24, 18)
	end
	local length = inc.secs >= 3600 and L["1-hour"] or string.format(L["%d-minute"], math.floor(inc.secs / 60))
	invite.text:SetText(string.format(L["%s challenges you to a %s %s race!"], "|cffffd100" .. ns.ShortName(inc.opponent) .. "|r",
		length, (ns.Versus.METRICS[inc.metric] or inc.metric):lower()))
	invite:Show()
	if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960) end
end
function ns.UI.HideVersusInvite() if invite then invite:Hide() end end
function VersusUI.InviteText() return invite and invite:IsShown() and invite.text:GetText() or nil end -- tests

-- The race bar: both players' progress, time left, then the result
local function CreateBar()
	bar = Dialog("GuildRanksRace", 300, 128)
	bar:SetPoint("TOP", 0, -200)
	bar.title = H().FS(bar, "GameFontNormal"); bar.title:SetPoint("TOPLEFT", 20, -18); bar.title:SetWidth(260)
	local function Line(y)
		local l = {}
		l.name = H().FS(bar, "GameFontHighlightSmall"); l.name:SetPoint("TOPLEFT", 20, y); l.name:SetWidth(150)
		l.value = H().FS(bar, "GameFontHighlightSmall", "RIGHT"); l.value:SetPoint("TOPRIGHT", -20, y); l.value:SetWidth(110)
		l.bg = bar:CreateTexture(nil, "ARTWORK"); l.bg:SetPoint("TOPLEFT", 20, y - 14); l.bg:SetSize(260, 6); l.bg:SetColorTexture(0.16, 0.17, 0.2, 1)
		l.fill = bar:CreateTexture(nil, "OVERLAY"); l.fill:SetPoint("LEFT", l.bg, "LEFT"); l.fill:SetSize(1, 6)
		return l
	end
	bar.me, bar.them = Line(-40), Line(-66)
	bar.me.fill:SetColorTexture(0.79, 0.64, 0.15, 1)
	bar.them.fill:SetColorTexture(0.55, 0.55, 0.58, 1)
	bar.left = H().MakeButton(bar, L["Give up"], 110, function()
		local r = ns.Versus.Current()
		if r and r.done then ns.Versus.PostResult(); VersusUI.Refresh() else ns.Versus.GiveUp() end
	end)
	bar.left:SetPoint("BOTTOMLEFT", 20, 14); bar.left:SetHeight(20)
	bar.right = H().MakeButton(bar, L["Hide"], 80, function()
		local r = ns.Versus.Current()
		if r and r.done then ns.Versus.Close() end
		bar:Hide()
	end)
	bar.right:SetPoint("BOTTOMRIGHT", -20, 14); bar.right:SetHeight(20)
end

function VersusUI.Refresh()
	local r = ns.Versus.Current()
	if not bar or not bar:IsShown() or not r then return end
	local fmt = function(v) return ns.Versus.Format(r.metric, v) end
	local label = (ns.Versus.METRICS[r.metric] or r.metric)
	local opp = ns.ShortName(r.opponent)
	if r.done then
		local result = r.draw and L["It's a draw!"] or (r.won and ("|cff40ff40" .. L["You won!"] .. "|r") or (string.format(L["%s won"], opp)))
		bar.title:SetText(string.format(L["%s race vs %s"], label, opp) .. "  ·  " .. result)
		bar.left:SetText(L["Post to guild chat"])
		bar.left:SetShown(r.won and not r.posted)
		bar.right:SetText(L["Close"])
	else
		local left = math.max(0, r.secs - (GetTime() - r.startedAt))
		bar.title:SetText(string.format(L["%s race vs %s"], label, opp) .. "  ·  " .. string.format(L["%s left"], ns.FormatTime(left)))
		bar.left:SetText(L["Give up"]); bar.left:Show()
		bar.right:SetText(L["Hide"])
	end
	local top = math.max(r.mine, r.theirs, 1)
	bar.me.name:SetText(L["You"]); bar.me.value:SetText("+" .. fmt(r.mine))
	bar.them.name:SetText(H().ClassColored(opp, (ns.G() and ns.G().players[r.opponent] or {}).class)); bar.them.value:SetText("+" .. fmt(r.theirs))
	bar.me.fill:SetWidth(math.max(1, 260 * r.mine / top))
	bar.them.fill:SetWidth(math.max(1, 260 * r.theirs / top))
end

function ns.UI.ShowVersus()
	if not bar then CreateBar() end
	bar:Show()
	VersusUI.Refresh()
end
ns.UI.RefreshVersus = VersusUI.Refresh
function VersusUI.BarText() -- tests
	if not (bar and bar:IsShown()) then return nil end
	return bar.title:GetText() .. " | " .. bar.me.value:GetText() .. " | " .. bar.them.value:GetText()
end
function VersusUI.ClickLeft() if bar then bar.left:GetScript("OnClick")(bar.left) end end -- tests

---------------------------------------------------------------------------
-- Guild vs Guild: the invite popup for officers and the "challenge by name" box
---------------------------------------------------------------------------
local LeagueUI = {}
ns.LeagueUI = LeagueUI
local leagueInvite, nameDialog

function ns.UI.ShowLeagueInvite(id, from)
	if not leagueInvite then
		leagueInvite = Dialog("GuildRanksLeagueInvite", 360, 132)
		leagueInvite:SetPoint("TOP", 0, -150)
		leagueInvite.text = H().FS(leagueInvite, "GameFontHighlight", "CENTER")
		leagueInvite.text:SetPoint("TOP", 0, -22); leagueInvite.text:SetWidth(320); leagueInvite.text:SetWordWrap(true)
		local yes = H().MakeButton(leagueInvite, L["Accept"], 110, function() ns.League.Answer(leagueInvite.id, true) end)
		yes:SetPoint("BOTTOMLEFT", 24, 18)
		local no = H().MakeButton(leagueInvite, L["Decline"], 110, function() ns.League.Answer(leagueInvite.id, false) end)
		no:SetPoint("BOTTOMRIGHT", -24, 18)
	end
	leagueInvite.id = id
	leagueInvite.text:SetText(string.format(L["%s challenges your guild to a weekly Guild vs Guild rivalry!"], "|cffffd100<" .. from .. ">|r")
		.. "\n|cff9d9d9d" .. L["Both guilds see each other's top-5 averages per category, never names. Any officer can end it later."] .. "|r")
	leagueInvite:Show()
	if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960) end
end
function ns.UI.HideLeagueInvite() if leagueInvite then leagueInvite:Hide() end end
function LeagueUI.InviteText() return leagueInvite and leagueInvite:IsShown() and leagueInvite.text:GetText() or nil end -- tests
function LeagueUI.ClickInvite(yes) -- tests
	if leagueInvite and leagueInvite:IsShown() then ns.League.Answer(leagueInvite.id, yes) end
end

function LeagueUI.ShowNameDialog()
	if not nameDialog then
		nameDialog = Dialog("GuildRanksLeagueByName", 340, 150)
		nameDialog:SetPoint("CENTER", 0, 120)
		tinsert(UISpecialFrames, "GuildRanksLeagueByName")
		local x = CreateFrame("Button", nil, nameDialog, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT", -6, -6)
		local title = H().FS(nameDialog, "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 22, -18); title:SetText(L["Challenge a guild by name"])
		local hint = H().FS(nameDialog, "GameFontDisableSmall"); hint:SetPoint("TOPLEFT", 22, -42); hint:SetWidth(296); hint:SetWordWrap(true)
		hint:SetText(L["Type a character in that guild who uses Guild Ranks (same faction). Their officers get the request."])
		nameDialog.edit = CreateFrame("EditBox", nil, nameDialog, "InputBoxTemplate")
		nameDialog.edit:SetSize(200, 24)
		nameDialog.edit:SetPoint("TOPLEFT", 28, -76)
		nameDialog.edit:SetAutoFocus(true)
		nameDialog.edit:SetScript("OnEscapePressed", function() nameDialog:Hide() end)
		nameDialog.edit:SetScript("OnEnterPressed", function() LeagueUI.SendByName() end)
		nameDialog.send = H().MakeButton(nameDialog, L["Send challenge"], 140, function() LeagueUI.SendByName() end)
		nameDialog.send:SetPoint("BOTTOMLEFT", 20, 18)
		local cancel = H().MakeButton(nameDialog, L["Cancel"], 80, function() nameDialog:Hide() end)
		cancel:SetPoint("BOTTOMRIGHT", -20, 18)
	end
	nameDialog.edit:SetText("")
	nameDialog:Show()
	return true
end
function LeagueUI.SendByName(text)
	if not nameDialog then return false end
	local name = strtrim and strtrim(text or nameDialog.edit:GetText() or "") or (text or nameDialog.edit:GetText() or ""):match("^%s*(.-)%s*$")
	if name == "" then return false end
	local okay, err = ns.League.Challenge(nil, name)
	if okay then nameDialog:Hide() elseif err then ns.Print(err) end
	return okay
end
