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
		if myRank and prev and prev.rank and myRank > prev.rank and not alert then
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

function A.WeeklySummaryLines(g)
	local thisStart = ns.WeekStart(g)
	local from = ns.ShiftDay(thisStart, -7)
	local range = { from = from, to = thisStart }
	local scores = ns.ComputeScores(g, range, 0)
	if #scores < 2 then return nil end
	local lines = {}
	lines[#lines + 1] = string.format(L["MVP: %s (%d)"], scores[1].name, scores[1].score)
	if g.rules.showSpoon then lines[#lines + 1] = string.format(L["Wooden spoon: %s (%d)"], scores[#scores].name, scores[#scores].score) end
	for i, e in ipairs(scores) do
		if e.key == ns.me then
			local prevRank = ns.Hall.PreviousRank(g, ns.me, from)
			local change = ""
			if prevRank and prevRank ~= i then
				change = prevRank > i and string.format(L[", up %d places"], prevRank - i) or string.format(L[", down %d places"], i - prevRank)
			end
			lines[#lines + 1] = string.format(L["You finished #%d of %d (%d)%s"], i, #scores, e.score, change)
			local best = BestRanking(g, ns.me, range)
			if best then lines[#lines + 1] = string.format(L["Your best ranking: #%d in %s"], best.rank, best.metric.short .. "/h") end
		end
	end
	local leader, cmetric = ns.ChallengeLeader(g, range)
	if leader then
		lines[#lines + 1] = string.format(L["Challenge winner (%s): %s"], cmetric.short .. "/h", leader.name)
			.. (g.rules.challengePrize and (" - " .. g.rules.challengePrize) or "")
	end
	return lines, from, scores
end

function A.ShowWeeklyPopup(g)
	local lines, from = A.WeeklySummaryLines(g)
	if not lines then return false end
	if not popup then
		popup = CreateFrame("Frame", "GuildRanksWeekly", UIParent, "BackdropTemplate")
		popup:SetSize(420, 220)
		popup:SetPoint("CENTER", 0, 120)
		popup:SetFrameStrata("DIALOG")
		popup:EnableMouse(true)
		popup:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 } })
		tinsert(UISpecialFrames, "GuildRanksWeekly")
		popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		popup.title:SetPoint("TOP", 0, -20)
		popup.body = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		popup.body:SetPoint("TOP", 0, -50)
		popup.body:SetWidth(380)
		popup.body:SetSpacing(4)
		local open = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		open:SetSize(120, 22); open:SetPoint("BOTTOMLEFT", 20, 18); open:SetText(L["Leaderboard"])
		open:SetScript("OnClick", function() popup:Hide(); ns.db.view.period = "lastweek"; ns.UI.Toggle("list") end)
		local copy = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		copy:SetSize(140, 22); copy:SetPoint("BOTTOM", 0, 18); copy:SetText(L["Copy for Discord"])
		copy:SetScript("OnClick", function() popup:Hide(); ns.ShowDiscordCopy(ns.G(), "lastweek") end)
		local close = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		close:SetSize(90, 22); close:SetPoint("BOTTOMRIGHT", -20, 18); close:SetText(CLOSE or L["Close"])
		close:SetScript("OnClick", function() popup:Hide() end)
	end
	local t = ns.KeyToTime(from)
	popup.title:SetText(string.format(L["The week of %s is over!"], t and date("%d %b", t) or from))
	popup.body:SetText(table.concat(lines, "\n"))
	popup:Show()
	return true
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
end)

ns.OnGuildChanged(function()
	previous = {}
	C_Timer.After(25, A.WeeklyCheck)
end)

ns.OnLogin(function()
	local idx = 0
	C_Timer.NewTicker(8, function()
		idx = idx % #WATCHED + 1
		A.CheckRanks(WATCHED[idx])
	end)
	-- Also catch the weekly reset while you're online
	C_Timer.NewTicker(900, A.WeeklyCheck)
end)
