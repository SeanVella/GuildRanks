-- Guild Ranks: rank-change alerts, weekly results popup, guild chat announcements
-- (level-ups, weekly MVP) and the "newer version available" notice.
local ADDON, ns = ...
local L = ns.L
local A = {}
ns.Alerts = A

local WATCHED = { "score", "gold", "xp", "levels", "damage", "healing", "quests", "kills" }
local ALERT_GAP = 120         -- at most one rank alert every 2 minutes
local lastAlert = -1000
local previous = {}           -- metric -> { rank = n, above = { key = true } }
local versionNoticed = false

---------------------------------------------------------------------------
-- Toast (short message at the top of the screen)
---------------------------------------------------------------------------
local toast
function A.Toast(msg)
	if not toast then
		toast = CreateFrame("Frame", "GuildRanksToast", UIParent, "BackdropTemplate")
		toast:SetSize(420, 34)
		toast:SetPoint("TOP", 0, -170)
		toast:SetFrameStrata("HIGH")
		toast:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		toast:SetBackdropColor(0, 0, 0, 0.85)
		toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		toast.text:SetPoint("CENTER")
		toast:EnableMouse(true)
		toast:SetScript("OnMouseUp", function() toast:Hide(); ns.UI.Toggle() end)
	end
	toast.text:SetText(msg)
	toast:SetWidth(math.max(300, (toast.text:GetStringWidth() or 380) + 30))
	toast:Show()
	toast.shownAt = GetTime()
	C_Timer.After(7, function()
		if toast.shownAt and GetTime() - toast.shownAt >= 6.9 then toast:Hide() end
	end)
	ns.Print(msg)
end

---------------------------------------------------------------------------
-- Rank-change alerts ("Kurt just passed you in Gold/h")
---------------------------------------------------------------------------
-- Check some (default: all) watched rankings; the background ticker checks one
-- ranking every few seconds so big guilds never cause a noticeable pause
function A.CheckRanks(onlyKey)
	local g = ns.G()
	if not g or g.solo or not ns.db.alerts or not ns.me then return end
	if UnitAffectingCombat("player") then return end
	local alert
	for _, key in ipairs(onlyKey and { onlyKey } or WATCHED) do
		local rows, _, metric = ns.BuildBoard(g, key, "week", true, 0)
		local myRank, above = nil, {}
		for i, r in ipairs(rows) do
			if r.key == ns.me then myRank = i break end
			above[r.key] = r
		end
		local prev = previous[key]
		-- losing first place gets its own lead card instead (when lead cards are on)
		local lostLead = ns.db.leadCards ~= false and prev and prev.rank == 1
		if myRank and prev and prev.rank and myRank > prev.rank and not alert and not lostLead then
			for k, r in pairs(above) do
				if not prev.above[k] then
					alert = string.format(L["%s just passed you in %s (you're now #%d)"], r.name,
						metric.short .. (metric.rate and "/h" or ""), myRank)
					break
				end
			end
		end
		previous[key] = { rank = myRank, above = above }
	end
	if alert and GetTime() - lastAlert >= ALERT_GAP then
		lastAlert = GetTime()
		A.Toast(alert)
	end
end

---------------------------------------------------------------------------
-- Lead cards: an achievement-style card when you take first place in a ranking
-- this week (gold, with a sound) or someone takes it from you (grey)
---------------------------------------------------------------------------
local LEAD = { "score", "gold", "loot", "xp", "levels", "damage", "healing", "kills", "quests", "bosses", "dungeons",
	"gathers", "crafts", "deaths" }
A.LEAD = LEAD
local ICONS = {
	score = "Interface\\Icons\\INV_Misc_Trophy_Gold", gold = "Interface\\Icons\\INV_Misc_Coin_01",
	loot = "Interface\\Icons\\INV_Misc_Bag_10", xp = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
	levels = "Interface\\Icons\\Spell_ChargePositive", damage = "Interface\\Icons\\Ability_DualWield",
	healing = "Interface\\Icons\\Spell_Holy_Heal", kills = "Interface\\Icons\\INV_Sword_04",
	quests = "Interface\\Icons\\INV_Misc_Note_01", bosses = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
	dungeons = "Interface\\Icons\\INV_Misc_Key_03", gathers = "Interface\\Icons\\INV_Misc_Flower_02",
	crafts = "Interface\\Icons\\Trade_BlackSmithing", deaths = "Interface\\Icons\\Spell_Holy_Resurrection",
}
local card, cardQueue = nil, {}

local function MetricName(metric)
	if metric.key == "score" then return metric.short end
	if metric.lowerIsBetter then return metric.label end
	return metric.label .. (metric.rate and (" " .. L["per hour"]) or "")
end

local function ShowNextCard()
	local item = table.remove(cardQueue, 1)
	if not item then return end
	if not card then
		card = CreateFrame("Button", "GuildRanksLeadCard", UIParent, "BackdropTemplate")
		card:SetSize(430, 64)
		card:SetPoint("TOP", 0, -120)
		card:SetFrameStrata("HIGH")
		card:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		card.icon = card:CreateTexture(nil, "ARTWORK")
		card.icon:SetPoint("LEFT", 10, 0); card.icon:SetSize(44, 44)
		card.kicker = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		card.kicker:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, 0); card.kicker:SetJustifyH("LEFT")
		card.title = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		card.title:SetPoint("LEFT", card.icon, "RIGHT", 10, 0); card.title:SetJustifyH("LEFT"); card.title:SetWidth(356)
		card.sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		card.sub:SetPoint("BOTTOMLEFT", card.icon, "BOTTOMRIGHT", 10, 0); card.sub:SetJustifyH("LEFT"); card.sub:SetWidth(356)
		card:SetScript("OnClick", function(self)
			self:Hide()
			if self.metric then
				ns.db.view.metric, ns.db.view.period = self.metric, "week"
				ns.db.view.guild = nil
				ns.UI.Show("list")
			end
		end)
	end
	card.metric = item.metric
	card.icon:SetTexture(ICONS[item.metric] or ICONS.score)
	card.icon:SetDesaturated(not item.won)
	card.kicker:SetText(item.kicker or (item.won and L["New leader  ·  this week"]) or "")
	card.title:SetText(item.title)
	card.sub:SetText(item.sub)
	if item.won then
		card:SetBackdropColor(0.09, 0.08, 0.04, 0.95)
		card:SetBackdropBorderColor(0.79, 0.64, 0.15, 1)
		card.title:SetTextColor(1, 1, 1)
		if PlaySound then
			local kit = (SOUNDKIT and (SOUNDKIT.UI_ACHIEVEMENT_AWARDED or SOUNDKIT.ACHIEVEMENT_MENU_OPEN)) or 12891
			pcall(PlaySound, kit)
		end
	else
		card:SetBackdropColor(0.07, 0.07, 0.07, 0.95)
		card:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
		card.title:SetTextColor(0.85, 0.85, 0.85)
	end
	card:Show()
	local shownAt = GetTime()
	card.shownAt = shownAt
	ns.Print(item.title .. "  ·  " .. item.sub)
	C_Timer.After(6, function()
		if card.shownAt == shownAt then card:Hide() end
		ShowNextCard()
	end)
end

local function QueueCard(item)
	cardQueue[#cardQueue + 1] = item
	if not (card and card:IsShown()) then ShowNextCard() end
end
A.QueueCard = QueueCard

function A.CardText() -- for the automated tests
	return card and card:IsShown() and (card.title:GetText() .. " | " .. card.sub:GetText()) or nil
end

-- Check who leads one ranking this week; cards when that changes to or from you
function A.CheckLead(key)
	local g = ns.G()
	if not g or g.solo or not ns.me then return end
	local week = ns.WeekStart(g)
	if g.leadWeek ~= week then g.leadWeek, g.lead, g.leadShown = week, {}, {} end
	g.lead, g.leadShown = g.lead or {}, g.leadShown or {}
	local rows, _, metric, useRate = ns.BuildBoard(g, key, "week", true, 0)
	if #rows < 2 then return end
	local top = rows[1]
	if rows[2].value == top.value then return end -- a tie: nobody leads alone
	if not metric.lowerIsBetter and (top.value or 0) <= 0 then return end
	local before = g.lead[key]
	g.lead[key] = top.key
	if not before or before == top.key or ns.db.leadCards == false then return end
	local today = ns.Today()
	local function fmt(v) return ns.FormatValue(metric, v, useRate) end
	local name = MetricName(metric)
	if top.key == ns.me then
		if g.leadShown[key .. "+"] == today then return end
		g.leadShown[key .. "+"] = today
		local old
		for _, r in ipairs(rows) do if r.key == before then old = r end end
		QueueCard({ won = true, metric = key, title = string.format(L["You're #1 in %s"], name),
			sub = fmt(top.value) .. (old and ("  ·  " .. string.format(L["you passed %s (%s)"], old.name, fmt(old.value))) or "") })
	elseif before == ns.me then
		if g.leadShown[key .. "-"] == today then return end
		g.leadShown[key .. "-"] = today
		local myRank, mine
		for i, r in ipairs(rows) do if r.key == ns.me then myRank, mine = i, r end end
		local gap = mine and math.abs(top.value - mine.value) or nil
		QueueCard({ won = false, metric = key, title = string.format(L["%s took the lead in %s"], top.name, name),
			sub = (myRank and string.format(L["You're #%d"], myRank) or "") .. (gap and ("  ·  " .. string.format(L["%s behind"], fmt(gap))) or "") })
	end
end

---------------------------------------------------------------------------
-- Chat helpers
---------------------------------------------------------------------------
local function CanChat()
	if not IsInGuild() or IsInInstance() then return false end
	if C_ChatInfo.InChatMessagingLockdown then
		local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
		if ok and locked then return false end
	end
	return true
end

local function GuildChat(msg)
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	if send then pcall(send, msg, "GUILD") end
end
A.GuildChat = GuildChat
A.CanChat = CanChat

---------------------------------------------------------------------------
-- Weekly results popup + MVP announcement (first login after the reset)
---------------------------------------------------------------------------
local popup

local function BestRanking(g, key, range)
	local best
	for _, mk in ipairs(WATCHED) do
		if mk ~= "score" then
			local rows, _, metric = ns.BuildBoard(g, mk, range, true, 0)
			for i, r in ipairs(rows) do
				if r.key == key then
					if not best or i < best.rank then best = { rank = i, metric = metric } end
					break
				end
			end
		end
	end
	return best
end

-- Last week's results, for the popup and the announcement (nil with fewer than 2 ranked)
function A.WeeklySummary(g)
	local thisStart = ns.WeekStart(g)
	local from = ns.ShiftDay(thisStart, -7)
	local range = { from = from, to = thisStart }
	local scores = ns.ComputeScores(g, range, 0)
	if #scores < 2 then return nil end
	local sum = { from = from, scores = scores }
	for i, e in ipairs(scores) do
		if e.key == ns.me then
			local prevRank = ns.Hall.PreviousRank(g, ns.me, from)
			sum.me = { rank = i, total = #scores, score = e.score, change = prevRank and (prevRank - i) or nil }
			sum.best = BestRanking(g, ns.me, range)
		end
	end
	local leader, cmetric = ns.ChallengeLeader(g, range)
	if leader then sum.challenge = { name = leader.name, class = leader.class, metric = cmetric } end
	return sum
end

local function MeLine(me)
	local change = ""
	if me.change and me.change > 0 then change = string.format(L[", up %d places"], me.change)
	elseif me.change and me.change < 0 then change = string.format(L[", down %d places"], -me.change) end
	return string.format(L["You finished #%d of %d (%d)%s"], me.rank, me.total, me.score, change)
end

function A.WeeklySummaryLines(g)
	local sum = A.WeeklySummary(g)
	if not sum then return nil end
	local scores, lines = sum.scores, {}
	lines[#lines + 1] = string.format(L["MVP: %s (%d)"], scores[1].name, scores[1].score)
	if g.rules.showSpoon then lines[#lines + 1] = string.format(L["Wooden spoon: %s (%d)"], scores[#scores].name, scores[#scores].score) end
	if sum.me then
		lines[#lines + 1] = MeLine(sum.me)
		if sum.best then lines[#lines + 1] = string.format(L["Your best ranking: #%d in %s"], sum.best.rank, sum.best.metric.short .. "/h") end
	end
	if sum.challenge then
		lines[#lines + 1] = string.format(L["Challenge winner (%s): %s"], sum.challenge.metric.short .. "/h", sum.challenge.name)
			.. (g.rules.challengePrize and (" - " .. g.rules.challengePrize) or "")
	end
	return lines, sum.from, scores
end

local function WeekLabel(from)
	local t = ns.KeyToTime(from)
	return t and date("%d %b", t) or from
end

-- One line for guild chat: your result, or the MVP if you weren't ranked
function A.WeeklyPostText(g)
	local sum = A.WeeklySummary(g)
	if not sum then return nil end
	local week = WeekLabel(sum.from)
	local text
	if sum.me then
		text = string.format(L["Week of %s: I finished #%d of %d"], week, sum.me.rank, sum.me.total)
		if sum.best then text = text .. "  ·  " .. string.format(L["best ranking #%d in %s"], sum.best.rank, sum.best.metric.short .. "/h") end
	else
		text = string.format(L["Week of %s: MVP %s (%d)"], week, sum.scores[1].name, sum.scores[1].score)
	end
	return text .. " (Guild Ranks)"
end

local PODIUM = { -- place, x offset, block height, colour
	{ 1, 0, 48, { 0.66, 0.53, 0.12 } }, { 2, -86, 34, { 0.36, 0.36, 0.38 } }, { 3, 86, 26, { 0.48, 0.31, 0.15 } },
}

local function CreatePopup()
	local FS = ns.UI.H.FS
	popup = CreateFrame("Frame", "GuildRanksWeekly", UIParent, "BackdropTemplate")
	popup:SetSize(440, 290)
	popup:SetPoint("CENTER", 0, 120)
	popup:SetFrameStrata("DIALOG")
	popup:EnableMouse(true)
	popup:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 } })
	tinsert(UISpecialFrames, "GuildRanksWeekly")
	local x = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
	x:SetPoint("TOPRIGHT", -6, -6)
	popup.title = FS(popup, "GameFontNormalLarge", "CENTER")
	popup.title:SetPoint("TOP", 0, -20)
	popup.places = {}
	for _, pl in ipairs(PODIUM) do
		local place, dx, h, col = pl[1], pl[2], pl[3], pl[4]
		local block = popup:CreateTexture(nil, "ARTWORK")
		block:SetSize(76, h)
		block:SetPoint("BOTTOM", popup, "TOP", dx, -112)
		block:SetColorTexture(col[1], col[2], col[3], 1)
		local num = FS(popup, place == 1 and "GameFontNormalLarge" or "GameFontHighlightLarge", "CENTER")
		num:SetPoint("CENTER", block, "CENTER", 0, 0)
		num:SetText(tostring(place))
		local name = FS(popup, "GameFontHighlight", "CENTER")
		name:SetPoint("BOTTOM", block, "TOP", 0, 4)
		name:SetWidth(100)
		popup.places[place] = { block = block, num = num, name = name }
	end
	popup.me = FS(popup, "GameFontHighlight", "CENTER")
	popup.me:SetPoint("TOP", 0, -124)
	popup.me:SetWidth(400)
	popup.extra = FS(popup, "GameFontDisableSmall", "CENTER")
	popup.extra:SetPoint("TOP", 0, -146)
	popup.extra:SetWidth(400)
	popup.extra:SetSpacing(3)
	local open = ns.UI.H.MakeButton(popup, L["Leaderboard"], 110, function()
		popup:Hide(); ns.db.view.period = "lastweek"; ns.UI.Show("list")
	end)
	open:SetPoint("BOTTOMLEFT", 20, 18)
	popup.post = ns.UI.H.MakeButton(popup, L["Post to guild chat"], 150, function()
		if not CanChat() then ns.Print(L["Guild chat isn't available right now."]); return end
		local text = A.WeeklyPostText(popup.guild)
		if text then GuildChat(text) end
		popup.post:Disable()
	end)
	popup.post:SetPoint("BOTTOM", 0, 18)
	local copy = ns.UI.H.MakeButton(popup, L["Copy for Discord"], 130, function()
		popup:Hide(); ns.ShowDiscordCopy(popup.guild, "lastweek")
	end)
	copy:SetPoint("BOTTOMRIGHT", -20, 18)
end

function A.ShowWeeklyPopup(g)
	local sum = A.WeeklySummary(g)
	if not sum then return false end
	if not popup then CreatePopup() end
	popup.guild = g
	local cc = ns.UI.H.ClassColored
	popup.title:SetText(string.format(L["The week of %s is over!"], WeekLabel(sum.from)))
	for place, p in ipairs(popup.places) do
		local e = sum.scores[place]
		p.block:SetShown(e ~= nil); p.num:SetShown(e ~= nil); p.name:SetShown(e ~= nil)
		if e then p.name:SetText(cc(e.name, e.class) .. (place == 1 and (" |cffffd100" .. L["MVP"] .. "|r") or "")) end
	end
	popup.me:SetText(sum.me and MeLine(sum.me):gsub("(, [%w ]+ places)", "|cff40ff40%1|r") or L["You weren't ranked last week."])
	local extra = {}
	if sum.best then extra[#extra + 1] = string.format(L["Your best ranking: #%d in %s"], sum.best.rank, sum.best.metric.short .. "/h") end
	if sum.challenge then
		extra[#extra + 1] = string.format(L["Challenge winner (%s): %s"], sum.challenge.metric.short .. "/h", cc(sum.challenge.name, sum.challenge.class))
			.. (g.rules.challengePrize and (" - " .. g.rules.challengePrize) or "")
	end
	if g.rules.showSpoon then
		local last = sum.scores[#sum.scores]
		extra[#extra + 1] = string.format(L["Wooden spoon: %s (%d)"], cc(last.name, last.class), last.score)
	end
	popup.extra:SetText(table.concat(extra, "\n"))
	popup.post:Enable()
	popup:Show()
	return true
end

function A.WeeklyPopupText() -- for the automated tests
	if not (popup and popup:IsShown()) then return nil end
	local out = { popup.title:GetText(), popup.me:GetText(), popup.extra:GetText() }
	for place, p in ipairs(popup.places) do if p.name:IsShown() then out[#out + 1] = place .. ". " .. p.name:GetText() end end
	return table.concat(out, "\n")
end

-- Once per week, after the reset: popup for me, MVP announcement for the guild
function A.WeeklyCheck()
	local g = ns.G()
	if not g or g.solo then return end
	local ws = ns.WeekStart(g)
	if g.popupWeek ~= ws then
		g.popupWeek = ws
		if ns.db.weeklyPopup ~= false then A.ShowWeeklyPopup(g) end
	end
	if g.rules.announceMVP and g.announcedWeek ~= ws then
		C_Timer.After(5 + math.random() * 30, function()
			if g.announcedWeek == ws or not CanChat() then return end
			local _, _, scores = A.WeeklySummaryLines(g)
			if not scores then return end
			g.announcedWeek = ws
			ns.Comm.SendClaim("W", ws) -- tell the other addons this week is announced
			local msg = string.format(L["Guild Ranks: last week's MVP is %s (score %d)!"], scores[1].name, scores[1].score)
			if g.rules.showSpoon then msg = msg .. " " .. string.format(L["Wooden spoon: %s."], scores[#scores].name) end
			GuildChat(msg)
		end)
	end
end

---------------------------------------------------------------------------
-- Level-up announcement (personal, opt-in)
---------------------------------------------------------------------------
ns.On("PLAYER_LEVEL_UP", function(newLevel)
	if not ns.db.announceLevel or not ns.Readable(newLevel) then return end
	C_Timer.After(1, function()
		if CanChat() then GuildChat(string.format(L["I just reached level %d!"], newLevel)) end
	end)
end)

---------------------------------------------------------------------------
-- Newer version notice
---------------------------------------------------------------------------
local function ParseVersion(v)
	local a, b, c = tostring(v or ""):match("^v?(%d+)%.(%d+)%.?(%d*)")
	if not a then return nil end
	return tonumber(a) * 1e6 + tonumber(b) * 1e3 + (tonumber(c) or 0)
end
A.ParseVersion = ParseVersion

function ns.NoteVersion(v)
	local theirs, mine = ParseVersion(v), ParseVersion(ns.VERSION)
	if not theirs or not mine or theirs <= mine then return end
	if not ns.newerVersion or ParseVersion(ns.newerVersion) < theirs then ns.newerVersion = v end
	if not versionNoticed then
		versionNoticed = true
		ns.Print(string.format(L["A newer version of Guild Ranks (%s) is used in your guild. Update from CurseForge, Wago or GitHub."], v))
	end
end

---------------------------------------------------------------------------
-- Schedule
---------------------------------------------------------------------------
ns.OnInit(function()
	if ns.db.alerts == nil then ns.db.alerts = true end
	if ns.db.weeklyPopup == nil then ns.db.weeklyPopup = true end
	if ns.db.announceLevel == nil then ns.db.announceLevel = false end
	if ns.db.leadCards == nil then ns.db.leadCards = true end
end)

ns.OnGuildChanged(function()
	previous = {}
	C_Timer.After(25, A.WeeklyCheck)
end)

ns.OnLogin(function()
	if ns.IsTrial() then
		C_Timer.After(15, function()
			ns.Print(L["Trial accounts can't send addon messages, so your guild won't see your stats. You'll still see theirs."])
		end)
	end
	local idx, leadIdx = 0, 0
	C_Timer.NewTicker(8, function()
		idx = idx % #WATCHED + 1
		A.CheckRanks(WATCHED[idx])
		if not UnitAffectingCombat("player") then
			leadIdx = leadIdx % #LEAD + 1
			A.CheckLead(LEAD[leadIdx])
		end
	end)
	-- Also catch the weekly reset while you're online
	C_Timer.NewTicker(900, A.WeeklyCheck)
end)
