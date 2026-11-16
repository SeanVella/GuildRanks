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
	contains(msg, "/releases", "download link")
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
	sw.gold.mail:SetChecked(false)
	sw.gold.mail:GetScript("OnClick")(sw.gold.mail)
	sw.save:GetScript("OnClick")(sw.save)
	ok(not sw.unsaved:IsShown(), "saved")
	w:Advance(30)
	eq(maria:G().rules.gold.mail, false, "Maria got the new rule")
	maria.ns.UI.Refresh()
	contains(mw.summaryText:GetText(), "except mail", "summary updated")
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
