-- Reset hour, play time privacy and sync timing (1.1.0)

local WED_MIDNIGHT = 1795003200 - 12 * 3600 -- Wed 18 Nov 2026 00:00 (realm time = UTC in the tests)

local function Publish(client, changes)
	local r = client:G().rules
	for k, v in pairs(changes) do r[k] = v end
	client.ns.InvalidateToday()
	client.ns.Comm.PublishRules()
end

local function PlayedSeconds(client, seconds)
	-- fake some play time today so boards have something to show
	local p = client.ns.GetPlayer(client:G(), client.key, true)
	local day = client.ns.Today()
	p.days[day] = p.days[day] or {}
	p.days[day].playtime = (p.days[day].playtime or 0) + seconds
	p.days[day].quests = (p.days[day].quests or 0) + 3
end

test("with a 05:00 reset, the day and the week start at 05:00 realm time", function()
	local w = NewWorld({ epoch = WED_MIDNIGHT + 4 * 3600 + 30 * 60 }) -- Wed 04:30
	local c = w:NewClient({ name = "Solo" })
	c:Login({ settle = 1 })
	local g, ns = c:G(), c.ns
	eq(ns.Today(), "2026-11-18", "midnight reset: already Wednesday")
	g.rules.resetHour = 5
	ns.InvalidateToday()
	eq(ns.Today(), "2026-11-17", "before 05:00 it is still Tuesday")
	eq(ns.WeekStart(g), "2026-11-11", "still last week's week")
	c:Fire("LOOT_OPENED"); c:GainMoney(10); c:Fire("LOOT_CLOSED")
	w:Advance(3600) -- 05:30
	eq(ns.Today(), "2026-11-18", "after 05:00 it is Wednesday")
	eq(ns.WeekStart(g), "2026-11-18", "a new week started")
	c:Fire("LOOT_OPENED"); c:GainMoney(20); c:Fire("LOOT_CLOSED")
	local p = g.players[c.key]
	eq(p.days["2026-11-17"].g_loot, 10, "gold before 05:00 counted for Tuesday")
	eq(p.days["2026-11-18"].g_loot, 20, "gold after 05:00 counted for Wednesday")
	contains(ns.PeriodDescription("week", g), "05:00", "week description shows the hour")
end)

test("the window shows when the week resets and how long until then", function()
	local w = NewWorld({ epoch = WED_MIDNIGHT + 4 * 3600 + 30 * 60 }) -- Wed 04:30
	local c = w:NewClient({ name = "Solo" })
	c:Login({ settle = 1 })
	local g, ns = c:G(), c.ns
	g.rules.resetHour = 5
	ns.InvalidateToday()
	local text = ns.ResetDescription(g)
	contains(text, "Wed 18 Nov, 05:00 realm time", "next reset")
	contains(text, "in 29m", "countdown (logged in at 04:30:01)")
	w:Advance(3600)
	text = ns.ResetDescription(g)
	contains(text, "Wed 25 Nov, 05:00", "after the reset: next week")
	contains(text, "in 6d 23h", "countdown to next week")
	g.rules.resetHour = 0
	ns.InvalidateToday()
	contains(ns.ResetDescription(g), "Wed 25 Nov, 00:00", "midnight reset")
	c.ns.UI.Show("list")
	c.ns.UI.Show("settings")
end)

test("reset hour and play time rule reach every member", function()
	local w = NewWorld({ epoch = WED_MIDNIGHT + 3 * 3600 }) -- Wed 03:00
	local kurt, sean, maria = StandardGuild(w)
	kurt:Login(); sean:Login(); maria:Login()
	w:Advance(30)
	eq(maria.ns.Today(), "2026-11-18", "midnight reset at first")
	Publish(sean, { resetHour = 5, showPlaytime = false })
	w:Advance(30)
	local r = maria:G().rules
	eq(r.resetHour, 5, "reset hour")
	eq(r.showPlaytime, false, "play time hidden for everyone")
	eq(maria.ns.Today(), "2026-11-17", "Maria's day follows the new reset hour right away")
	eq(kurt:G().rules.resetHour, 5, "GM got it too")
end)

test("rules from an older version (without the new fields) use midnight and show play time", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	kurt:Login(); maria:Login()
	w:Advance(30)
	maria:G().rules.resetHour, maria:G().rules.showPlaytime = 5, false
	-- the 1.0 rules message: 15 fields
	kurt.env.C_ChatInfo.SendAddonMessage("GuildRanks", "C;1;" .. "zzzzzz" .. ";4;30;1111111;1;1;v;Kurt;;;;0;0", "GUILD")
	w:Advance(5)
	eq(maria:G().rules.resetHour, 0, "midnight")
	eq(maria:G().rules.showPlaytime, true, "play time shown")
end)

test("a member can hide their play time; others see 'hidden' but still rank them", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	kurt:Login(); maria:Login()
	w:Advance(30)
	PlayedSeconds(maria, 3600)
	PlayedSeconds(kurt, 3600)
	maria.ns.Comm.SetShowPlay(false)
	w:Advance(60)
	local g = kurt:G()
	eq(g.players[maria.key].hidePlay, true, "Kurt knows Maria hides her play time")
	ok(not kurt.ns.PlaytimeShownFor(g, maria.key), "hidden for Kurt")
	ok(maria.ns.PlaytimeShownFor(maria:G(), maria.key), "Maria still sees her own")
	local rows = kurt.ns.BuildBoard(g, "playtime", "week", false, 0)
	for _, r in ipairs(rows) do ok(r.key ~= maria.key, "Maria not on the Play time board") end
	eq(#rows, 1, "Kurt alone on the Play time board")
	local scores = kurt.ns.BuildBoard(g, "quests", "week", true, 0)
	eq(#scores, 2, "Maria still ranked on per-hour boards")
	local text = table.concat(kurt.ns.BuildDiscordText(g, "week"), "\n")
	local playLine = text:match("%*%*Play time:%*%*[^\n]*") or ""
	absent(playLine, "Maria", "not in the Discord play time line")
	kurt.ns.UI.Show("list")
	-- turning it back on clears it
	maria.ns.Comm.SetShowPlay(true)
	w:Advance(60)
	eq(g.players[maria.key].hidePlay, nil, "shown again")
end)

test("the hidden play time choice travels with relayed data", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	kurt:Login(); maria:Login()
	w:Advance(30)
	PlayedSeconds(maria, 3600)
	maria.ns.Comm.SetShowPlay(false)
	w:Advance(60)
	maria:Logout()
	w:Advance(30)
	sean:Login()
	w:Advance(240)
	local p = sean:G().players[maria.key]
	ok(p, "Sean got Maria's data from Kurt")
	eq(p and p.hidePlay, true, "and knows she hides her play time")
end)

test("a guild rule hides play time for everyone", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	kurt:Login(); sean:Login()
	w:Advance(30)
	PlayedSeconds(kurt, 3600); PlayedSeconds(sean, 3600)
	kurt.ns.Comm.QueueRecent(1); sean.ns.Comm.QueueRecent(1)
	w:Advance(30)
	Publish(kurt, { showPlaytime = false })
	w:Advance(30)
	local g, ns = sean:G(), sean.ns
	eq(#ns.BuildBoard(g, "playtime", "week", false, 0), 0, "no Play time board")
	ok(not ns.PlaytimeShownFor(g, sean.key), "even your own is hidden in the window")
	for _, o in ipairs(ns.RankingChoices(g)) do ok(o.value ~= "playtime", "Play time not offered") end
	absent(table.concat(ns.BuildDiscordText(g, "week"), "\n"), "Play time", "not in Discord")
	ns.db.view.metric = "playtime"
	ns.UI.Show("list")
	eq(ns.db.view.metric, "score", "window switches to Guild score")
end)

test("/granks diag shows how long guild sync takes", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	kurt:Login(); maria:Login()
	w:Advance(30)
	PlayedSeconds(kurt, 3600); PlayedSeconds(maria, 1800)
	w:Advance(90) -- after Kurt's and Maria's own login syncs
	sean:Login()
	w:Advance(120)
	local f = sean.ns.Comm.FullSyncInfo()
	ok(f, "full sync recorded")
	ok(f.msgs > 0 and f.members >= 2, "messages from Kurt and Maria")
	ok(f.secs > 0 and f.secs < 60, "took a few seconds")
	ok(not f.busy, "finished")
	sean.printed = {}
	sean:Slash("diag")
	local out = table.concat(sean.printed, "\n")
	contains(out, "guild sync", "section")
	contains(out, "Last full sync:", "full sync line")
	contains(out, "Last send:", "own send batch")
	contains(out, "Latest data from guildmates: ", "latest data")
	contains(out, "Kurt", "Kurt listed")
	contains(out, "Resets ", "reset time")
end)
