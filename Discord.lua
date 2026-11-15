-- Guild Ranks: "Copy for Discord" — builds the results as Discord-formatted text
-- in a box the player copies with Ctrl+C. No setup or external service needed.
local ADDON, ns = ...
local L = ns.L

local DISCORD_LIMIT = 1900 -- Discord allows 2000 characters per message
local TOP_N = 3

local function TopLine(label, rows, metric, useRate)
	local parts = {}
	for i = 1, math.min(TOP_N, #rows) do
		local r = rows[i]
		parts[#parts + 1] = string.format("%d. %s %s", i, r.name, ns.FormatValue(metric, r.value, useRate, true))
	end
	return string.format("**%s:** %s", label, table.concat(parts, " · "))
end

-- Returns a list of message chunks, each under Discord's limit
function ns.BuildDiscordText(g, period)
	local per = ns.PERIOD_BY_KEY[period] or ns.PERIODS[2]
	local lines = {}
	lines[#lines + 1] = string.format("**<%s> %s: %s** (%s)", g.name, L["Guild Ranks"], per.label, ns.PeriodDescription(period, g))

	local scores = ns.ComputeScores(g, period, 0)
	lines[#lines + 1] = string.format(L["%d members ranked (at least %d min played)"], #scores, g.rules.minMinutes or 0)
	if #scores == 0 then
		lines[#lines + 1] = L["Nobody qualified yet."]
	else
		local best, worst = scores[1], scores[#scores]
		if period == "lastweek" then
			lines[#lines + 1] = string.format(":trophy: **%s:** %s (%d)", L["MVP of the week"], best.name, best.score)
			if g.rules.showSpoon and #scores >= 2 then
				lines[#lines + 1] = string.format(":spoon: **%s:** %s (%d)", L["Wooden spoon"], worst.name, worst.score)
			end
		else
			lines[#lines + 1] = string.format(":trophy: **%s:** %s (%d)", L["Leading"], best.name, best.score)
		end
		lines[#lines + 1] = TopLine(L["Guild score"], scores, ns.METRIC_BY_KEY.score, false)
		local leader, cmetric = ns.ChallengeLeader(g, period)
		if leader then
			local prize = g.rules.challengePrize and (" (" .. L["prize"] .. ": " .. g.rules.challengePrize .. ")") or ""
			lines[#lines + 1] = string.format(":dart: **%s %s:** %s, %s%s", period == "lastweek" and L["Challenge winner"] or L["Challenge leader"],
				cmetric.short .. "/h", leader.name, ns.FormatValue(cmetric, leader.value, true, true), prize)
		end
		local cur, target, gmetric = ns.GoalProgress(g, period)
		if cur then
			lines[#lines + 1] = string.format(":dart: **%s (%s):** %s / %s (%d%%)", L["Guild goal"], gmetric.short,
				ns.FormatValue(gmetric, cur, false, true), ns.FormatValue(gmetric, target, false, true), math.floor(100 * cur / target))
		end
		for _, metric in ipairs(ns.METRICS) do
			if metric.key ~= "score" then
				local rows, _, _, useRate = ns.BuildBoard(g, metric.key, period, true, 0)
				-- Skip rankings with nothing to show (e.g. nobody died)
				local differs = false
				for _, r in ipairs(rows) do
					if r.value ~= rows[1].value or (r.value > 0 and not metric.lowerIsBetter) then differs = true end
				end
				if #rows > 0 and differs then
					lines[#lines + 1] = TopLine(metric.short .. (useRate and "/h" or ""), rows, metric, useRate)
				end
			end
		end
	end
	lines[#lines + 1] = "-# " .. L["Tracked with the Guild Ranks addon"]

	local chunks, cur = {}, ""
	for _, line in ipairs(lines) do
		if #cur + #line + 1 > DISCORD_LIMIT then
			chunks[#chunks + 1] = cur
			cur = ""
		end
		cur = (cur == "") and line or (cur .. "\n" .. line)
	end
	if cur ~= "" then chunks[#chunks + 1] = cur end
	return chunks
end

---------------------------------------------------------------------------
-- Copy dialog
---------------------------------------------------------------------------
local dialog

local function CreateDialog()
	dialog = CreateFrame("Frame", "GuildRanksCopyFrame", UIParent, "BackdropTemplate")
	dialog:SetSize(520, 360)
	dialog:SetPoint("CENTER")
	dialog:SetFrameStrata("DIALOG")
	dialog:EnableMouse(true)
	dialog:SetMovable(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
	dialog:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	tinsert(UISpecialFrames, "GuildRanksCopyFrame")

	local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	dialog.title:SetPoint("TOP", 0, -18)

	local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOP", 0, -36)
	hint:SetText(L["The text is selected: press Ctrl+C, then paste it in Discord."])

	local ok, sf = pcall(CreateFrame, "ScrollFrame", nil, dialog, "ScrollFrameTemplate")
	if not ok or not sf then sf = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate") end
	sf:SetPoint("TOPLEFT", 22, -56)
	sf:SetPoint("BOTTOMRIGHT", -40, 52)

	local eb = CreateFrame("EditBox", nil, sf)
	eb:SetMultiLine(true)
	eb:SetFontObject(ChatFontNormal)
	eb:SetWidth(450)
	eb:SetAutoFocus(false)
	eb:SetScript("OnEscapePressed", function() dialog:Hide() end)
	-- Keep the text read-only: put it back if the player types
	eb:SetScript("OnTextChanged", function(self, userInput)
		if userInput and dialog.chunks then
			self:SetText(dialog.chunks[dialog.index])
			self:HighlightText()
		end
	end)
	sf:SetScrollChild(eb)
	dialog.edit = eb

	dialog.prev = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	dialog.prev:SetSize(110, 22)
	dialog.prev:SetPoint("BOTTOMLEFT", 20, 18)
	dialog.prev:SetText(L["Previous part"])
	dialog.prev:SetScript("OnClick", function() ns.ShowDiscordPart(dialog.index - 1) end)

	dialog.next = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	dialog.next:SetSize(110, 22)
	dialog.next:SetPoint("BOTTOMRIGHT", -20, 18)
	dialog.next:SetText(L["Next part"])
	dialog.next:SetScript("OnClick", function() ns.ShowDiscordPart(dialog.index + 1) end)

	dialog.part = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	dialog.part:SetPoint("BOTTOM", 0, 24)
end

function ns.ShowDiscordPart(i)
	local chunks = dialog.chunks
	i = math.max(1, math.min(#chunks, i))
	dialog.index = i
	dialog.edit:SetText(chunks[i])
	dialog.edit:SetFocus()
	dialog.edit:HighlightText()
	dialog.part:SetText(#chunks > 1 and string.format(L["Part %d of %d (paste each part as its own message)"], i, #chunks) or "")
	if #chunks > 1 and i > 1 then dialog.prev:Enable() else dialog.prev:Disable() end
	if #chunks > 1 and i < #chunks then dialog.next:Enable() else dialog.next:Disable() end
	dialog.prev:SetShown(#chunks > 1)
	dialog.next:SetShown(#chunks > 1)
end

function ns.ShowDiscordCopy(g, period)
	if not g then return end
	if not dialog then CreateDialog() end
	dialog.chunks = ns.BuildDiscordText(g, period)
	dialog.title:SetText(L["Copy for Discord"])
	dialog:Show()
	ns.ShowDiscordPart(1)
end
