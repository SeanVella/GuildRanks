-- The redesigned window: tabs, award strip, ranking chips, bars and rank changes,
-- player card, invite, settings split and welcome

-- Last week (gold): Kurt 1st, Sean 2nd, Maria 3rd.
-- This week (gold): Joe 1st (new), Kurt 2nd, Maria 3rd, Sean 4th.
local function TwoWeeks()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	sean:Login()
	local g, ns = sean:G(), sean.ns
	local today = ns.Today()
	local lastWeek = ns.ShiftDay(ns.WeekStart(g), -3)
	local function day(key, d, mult)
		local p = ns.GetPlayer(g, key, true)
		p.days[d] = { playtime = 3600, g_loot = 10000 * mult, xp = 1000 * mult, mlevels = 100 * mult, damage = 50000 * mult,
			kills = 10 * mult, quests = mult, deaths = 1, bosses = mult, gathers = mult, crafts = mult }
	end
	day(kurt.key, lastWeek, 3); day(sean.key, lastWeek, 2); day(maria.key, lastWeek, 1)
	day(kurt.key, today, 3); day(maria.key, today, 2); day(sean.key, today, 1)
	w:AddRosterMember("Froga", "Joe-Firemaw", 4, 30, "ROGUE")
	day("Joe-Firemaw", today, 4)
	ns.GetPlayer(g, kurt.key).class = "WARRIOR"
	ns.GetPlayer(g, maria.key).class = "PRIEST"
	ns.ReadRoster()
	return w, kurt, sean, maria, g
end

local function Controls(client) return client.ns.UI.Internals() end
function UI_Summary(client) return client.ns.UI.RulesSummary(client:G()) end

test("rank changes compare with the previous period: up, down, same and new", function()
	local w, kurt, sean, maria, g = TwoWeeks()
	local ns = sean.ns
	local rows = ns.BuildBoard(g, "gold", "week", true, 0)
	local ch = ns.RankChanges(g, rows, "gold", "week", true, 0)
	eq(rows[1].name, "Joe", "Joe tops this week")
	eq(ch["Joe-Firemaw"], "new", "Joe is new")
	eq(ch[kurt.key], -1, "Kurt 1st -> 2nd")
	eq(ch[maria.key], 0, "Maria stays 3rd")
	eq(ch[sean.key], -2, "Sean 2nd -> 4th")
	eq(next(ns.RankChanges(g, rows, "gold", "all", true, 0)), nil, "nothing to compare with for all time")
	eq(ns.PreviousPeriod("month", g).from, "2026-10-01", "previous month")
	eq(ns.PreviousPeriod("today", g).from, "2026-11-17", "yesterday")
end)

test("tabs switch pages; the award strip only shows what's set", function()
	local w, kurt, sean, maria, g = TwoWeeks()
	local ns = sean.ns
	ns.db.ui.welcomed = true
	sean:Slash("")
	local controls, wi, tabs = Controls(sean)
	eq(ns.UI.Current(), "list", "opens on the leaderboard")
	-- last week's MVP exists, no challenge or goal: one box
	ok(controls.awardBox:IsShown(), "MVP box shown")
	ok(not controls.challengeBox:IsShown() and not controls.goalBox:IsShown(), "no empty challenge or goal boxes")
	contains(controls.award:GetText(), "MVP last week", "award text")
	contains(controls.award:GetText(), "Kurt", "Kurt was MVP")
	g.rules.challengeMetric, g.rules.goalMetric, g.rules.goalTarget = "quests", "gold", 100000
	ns.UI.Refresh()
	ok(controls.challengeBox:IsShown() and controls.goalBox:IsShown(), "challenge and goal shown once set")
	for _, view in ipairs({ "hall", "members", "settings", "list" }) do
		tabs[view]:GetScript("OnClick")(tabs[view])
		eq(ns.UI.Current(), view, view .. " tab")
	end
end)

test("ranking chips switch the ranking in one click; bars and changes fill in", function()
	local w, kurt, sean, maria, g = TwoWeeks()
	local ns = sean.ns
	ns.db.ui.welcomed = true
	ns.UI.Show("list")
	local controls = Controls(sean)
	controls.chips.gold:GetScript("OnClick")(controls.chips.gold)
	eq(ns.db.view.metric, "gold", "gold chosen")
	controls.chips.xp:GetScript("OnClick")(controls.chips.xp)
	eq(ns.db.view.metric, "xp", "xp chosen")
	controls.chips.score:GetScript("OnClick")(controls.chips.score)
	eq(ns.db.view.metric, "score", "back to score")
	ns.db.view.metric = "gold"
	ns.UI.Refresh()
	-- the window's rows aren't reachable directly; check the numbers they're built from
	local rows = ns.BuildBoard(g, "gold", "week", true, 0)
	ok(rows[1].value > rows[4].value, "bars scale to the top value")
end)

test("player card: click a name for score breakdown, stats and recent weeks", function()
	local w, kurt, sean, maria, g = TwoWeeks()
	local ns = sean.ns
	ns.db.ui.welcomed = true
	ns.UI.Show("list")
	ns.Card.Toggle(kurt.key)
	ok(ns.Card.IsShown(), "card open")
	eq(ns.Card.key, kurt.key, "Kurt's card")
	local text = ns.Card.Texts()
	contains(text, "Score breakdown", "breakdown section")
	contains(text, "Gold by source", "gold sources")
	contains(text, "#", "rank tile")
	ns.Card.Toggle(maria.key)
	eq(ns.Card.key, maria.key, "switches to Maria")
	ns.Card.Toggle(maria.key)
	ok(not ns.Card.IsShown(), "same name again closes it")
	-- someone without enough play time
	ns.GetPlayer(g, "Bam-Firemaw", true).days[ns.Today()] = { playtime = 600, quests = 1 }
	ns.Card.Show("Bam-Firemaw")
	contains(ns.Card.Texts(), "Not ranked yet", "unranked explanation")
	ns.UI.Show("settings")
	ok(not ns.Card.IsShown(), "closes when leaving the leaderboard")
end)

test("invite: message under 255 characters, posted to guild chat in one click", function()
	local w, kurt, sean, maria, g = TwoWeeks()
	local ns = sean.ns
	sean:Slash("invite")
	local msg = ns.Invite.Message()
	ok(msg and #msg <= 255, "fits in one chat message")
	contains(msg, "Guild Ranks", "names the addon")
	contains(msg, "curseforge.com/wow/addons/guild-ranks", "CurseForge link")
	ns.Invite.Post()
	eq(#w.chat, 1, "posted once")
	eq(w.chat[1].msg, msg, "the same message")
end)

test("settings: members see a plain summary; officers edit with unsaved changes, save and discard", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	kurt:Login(); sean:Login(); maria:Login()
	w:Advance(30)
	-- Maria (member): summary
	maria.ns.db.ui.welcomed = true
	maria.ns.UI.Show("settings")
	local _, mw = Controls(maria)
	mw.rulesTab:GetScript("OnClick")(mw.rulesTab)
	ok(mw.summary:IsShown() and not mw.editor:IsShown(), "member sees the summary")
	local summary = mw.summaryText:GetText()
	contains(summary, "Wednesday 00:00 realm time", "reset")
	contains(summary, "30 min played", "minimum")
	contains(summary, "all sources", "gold")
	-- Sean (officer): editor
	sean.ns.db.ui.welcomed = true
	sean.ns.UI.Show("settings")
	local _, sw = Controls(sean)
	sw.rulesTab:GetScript("OnClick")(sw.rulesTab)
	ok(sw.editor:IsShown() and not sw.summary:IsShown(), "officer sees the editor")
	ok(not sw.unsaved:IsShown(), "nothing changed yet")
	sw.spoon:SetChecked(false)
	sw.spoon:GetScript("OnClick")(sw.spoon)
	ok(sw.unsaved:IsShown(), "unsaved changes shown")
	sw.discard:GetScript("OnClick")(sw.discard)
	ok(not sw.unsaved:IsShown(), "discarded")
	eq(sw.pending.showSpoon, true, "back to the saved value")
	contains(UI_Summary(sean), "except Auction House and mail", "AH and mail are off by default")
	sw.gold.trade:SetChecked(false)
	sw.gold.trade:GetScript("OnClick")(sw.gold.trade)
	sw.save:GetScript("OnClick")(sw.save)
	ok(not sw.unsaved:IsShown(), "saved")
	w:Advance(30)
	eq(maria:G().rules.gold.trade, false, "Maria got the new rule")
	maria.ns.UI.Refresh()
	contains(mw.summaryText:GetText(), "except Auction House, mail and trades", "summary updated")
	-- the You tab
	sw.youTab:GetScript("OnClick")(sw.youTab)
	ok(sw.youPane:IsShown() and not sw.rulesPane:IsShown(), "You tab")
end)

test("welcome shows once on first open; 'Show sample data' opens the demo", function()
	local w = NewWorld()
	local c = w:NewClient({ name = "Solo" })
	c:Login()
	c:Slash("")
	ok(c.ns.Welcome.IsShown(), "welcome on first open")
	c.ns.Welcome.Done()
	ok(not c.ns.Welcome.IsShown(), "closed")
	eq(c.ns.db.ui.welcomed, true, "remembered")
	c:Slash(""); c:Slash("")
	ok(not c.ns.Welcome.IsShown(), "not again")
	c:Slash("welcome")
	ok(c.ns.Welcome.IsShown(), "/granks welcome shows it again")
	c.ns.UI.Show("hall")
	ok(not c.ns.Welcome.IsShown(), "steps aside on another tab")
	c.ns.UI.Show("list")
	ok(c.ns.Welcome.IsShown(), "back on the leaderboard until dismissed")
	c.ns.Welcome.Done()
	c.ns.Tools.Demo(true)
	eq(c.ns.db.view.guild, "~demo", "sample data shown")
	ok(c.ns.UI.Frame():IsShown(), "window stays open (fix)")
	c.ns.UI.Show("list")
	c.ns.Card.Show(next(c.ns.db.guilds["~demo"].players))
	contains(c.ns.Card.Texts(), "Score breakdown", "card works on sample data")
end)

test("time-ago text and empty leaderboard with an invite button", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	sean:Login()
	local ns = sean.ns
	local now = sean.env.time()
	eq(ns.FormatAgo(nil), "never", "never")
	eq(ns.FormatAgo(now - 30), "just now", "just now")
	eq(ns.FormatAgo(now - 150), "2 min ago", "minutes")
	eq(ns.FormatAgo(now - 7300), "2 h ago", "hours")
	eq(ns.FormatAgo(now - 3 * 86400), "3 days ago", "days")
	ns.db.ui.welcomed = true
	ns.UI.Show("list")
	local controls = Controls(sean)
	ok(controls.emptyInvite:IsShown(), "invite button on an empty leaderboard")
	ok(not controls.awardBox:IsShown(), "no award box without results")
end)

test("online: green dots by names, 'Online only' keeps real rank numbers, online count in the footer", function()
	local w, kurt, sean, maria, g = TwoWeeks()
	local ns = sean.ns
	ns.db.ui.welcomed = true
	ns.db.view.metric = "gold"
	ns.UI.Show("list")
	eq(ns.UI.IsOnline(g, sean.key), true, "Sean online")
	eq(ns.UI.IsOnline(g, kurt.key), false, "Kurt offline")
	eq(ns.UI.OnlineCount(g), 1, "one online")
	local rows = ns.UI.VisibleRows()
	eq(#rows, 4, "everyone listed")
	contains(rows[1].name, "StatusIcon-Offline", "Joe (offline) has the offline ring")
	local _, _, _, footer = ns.UI.Internals()
	contains(footer:GetText(), "1 online", "online count")
	-- Online only
	local controls = ns.UI.Internals()
	controls.onlineOnly:SetChecked(true)
	controls.onlineOnly:GetScript("OnClick")(controls.onlineOnly)
	rows = ns.UI.VisibleRows()
	eq(#rows, 1, "only Sean")
	eq(rows[1].key, sean.key, "Sean")
	contains(rows[1].rank, "4.", "keeps his real rank (4th in gold)")
	contains(rows[1].name, "StatusIcon-Online", "green dot")
	-- Kurt logs in: he appears once the roster updates
	kurt:Login()
	ns.RequestRoster()
	w:Advance(5)
	rows = ns.UI.VisibleRows()
	eq(#rows, 2, "Kurt and Sean")
	contains(rows[1].rank, "2.", "Kurt is 2nd")
	contains(footer:GetText(), "2 online", "count updated")
	-- another character's guild or sample data: no dots, filter off
	ns.Tools.Demo(true)
	ns.UI.Refresh()
	ok(not controls.onlineOnly:IsEnabled(), "filter can't be used without a roster")
	ok(#ns.UI.VisibleRows() > 0, "sample data still listed")
	absent(ns.UI.VisibleRows()[1].name, "StatusIcon", "no dots on sample data")
end)

test("online only: a clear message when nobody on the list is online", function()
	local w, kurt, sean, maria, g = TwoWeeks()
	local ns = sean.ns
	ns.db.ui.welcomed = true
	ns.db.view.onlineOnly = true
	ns.db.view.bracket = 0
	g.rules.excluded[sean.key] = true -- Sean (the only one online) isn't on the board
	ns.UI.Show("list")
	eq(#ns.UI.VisibleRows(), 0, "nobody shown")
end)

test("weekly popup: podium, your place, one-click post to guild chat", function()
	local w, kurt, sean, maria, g = TwoWeeks()
	local ns = sean.ns
	ok(ns.Alerts.ShowWeeklyPopup(g), "popup shown")
	local text = ns.Alerts.WeeklyPopupText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	contains(text, "is over!", "title")
	contains(text, "1. Kurt MVP", "MVP on the podium")
	contains(text, "2. Sean", "second place")
	contains(text, "3. Maria", "third place")
	contains(text, "You finished #2 of 3", "my place")
	contains(text, "Your best ranking", "best ranking")
	local post = sean.env.GuildRanksWeekly.post
	local before = #w.chat
	post:GetScript("OnClick")(post)
	eq(#w.chat, before + 1, "posted once")
	local msg = w.chat[#w.chat].msg
	contains(msg, "I finished #2 of 3", "my result")
	contains(msg, "(Guild Ranks)", "names the addon")
	ok(#msg <= 255, "fits one chat message")
	ok(not post:IsEnabled(), "button disabled after posting")
	-- not ranked last week: posts the MVP instead
	ns.GetPlayer(g, sean.key).days[ns.ShiftDay(ns.WeekStart(g), -3)] = nil
	contains(ns.Alerts.WeeklyPostText(g), "MVP Kurt", "MVP line when you weren't ranked")
end)

test("members tab: officers get an invite nudge until 'Not now'; members never see it", function()
	local w, kurt, sean, maria, g = TwoWeeks()
	local ns = sean.ns
	ns.db.ui.welcomed = true
	w:AddRosterMember("Froga", "Ann-Firemaw", 4, 20, "MAGE")
	ns.ReadRoster()
	ns.UI.Show("members")
	local text = ns.UI.NudgeText()
	ok(text, "nudge shown to an officer")
	contains(text, "of 5 members use Guild Ranks", "counts")
	ns.UI.NudgeClick("later")
	eq(ns.UI.NudgeText(), nil, "hidden after Not now")
	eq(g.nudgeWeek, ns.WeekStart(g), "for this week")
	g.nudgeWeek = "2000-01-01" -- a new week
	ns.UI.Refresh()
	ok(ns.UI.NudgeText(), "back next week")
	ns.UI.NudgeClick("invite")
	ok(ns.Invite.Message(), "Invite opens the invite dialog")
	eq(ns.UI.NudgeText(), nil, "and hides the nudge for the week")
	-- a plain member
	maria:Login()
	maria.ns.db.ui.welcomed = true
	maria.ns.ReadRoster()
	maria.ns.UI.Show("members")
	eq(maria.ns.UI.NudgeText(), nil, "members don't get the nudge")
end)

test("welcome: 'You're #N' when guildmates use it, 'You're the first' when nobody does", function()
	local w, kurt, sean, maria, g = TwoWeeks()
	local ns = sean.ns
	sean:Slash("")
	local text = ns.Welcome.Texts():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	contains(text, "You're #4 in Froga!", "joined title")
	contains(text, "3 guildmates already use Guild Ranks", "count")
	contains(text, "Kurt", "names guildmates")
	contains(text, "after 30 min of play", "what happens next")
	ns.Welcome.Click("right")
	eq(ns.UI.Current(), "me", "Open your Me tab")
	eq(ns.db.ui.welcomed, true, "dismissed")

	local w2 = NewWorld()
	local _, s2 = StandardGuild(w2)
	s2:Login()
	s2:Slash("")
	contains(s2.ns.Welcome.Texts(), "Welcome to Guild Ranks", "generic while the guild's data may still arrive")
	w2:Advance(100)
	s2.ns.UI.Refresh()
	contains(s2.ns.Welcome.Texts(), "You're the first in Froga", "first in the guild")
	s2.ns.Welcome.Click("left")
	ok(s2.ns.Invite.Message(), "Invite opens the invite dialog")
	eq(s2.ns.db.ui.welcomed, true, "dismissed")
end)
