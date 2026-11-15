-- Day keys, weeks and the weekly reset

local DAY = 86400

test("days-from-civil matches known dates", function()
	local w = NewWorld()
	local c = w:NewClient({ name = "Solo" })
	c:Login()
	local D = c.ns.DaysFromCivil
	eq(D(1970, 1, 1), 0, "epoch")
	eq(D(2000, 3, 1), 11017, "2000-03-01")
	eq(D(2026, 11, 18) * DAY, 1795003200 - 12 * 3600, "2026-11-18")
end)

test("week starts on the guild's reset day; last week is the 7 days before", function()
	-- Wednesday 18 Nov 2026, reset Wednesday
	local w = NewWorld()
	local c = w:NewClient({ name = "Solo" })
	c:Login()
	local g = c:G()
	eq(c.ns.Today(), "2026-11-18", "today")
	eq(c.ns.WeekStart(g), "2026-11-18", "reset day itself starts the week")
	g.rules.resetDay = 2 -- Monday
	eq(c.ns.WeekStart(g), "2026-11-16", "Monday reset")
	g.rules.resetDay = 5 -- Thursday
	eq(c.ns.WeekStart(g), "2026-11-12", "Thursday reset")
	g.rules.resetDay = 4
	local f = c.ns.PeriodFilter("lastweek", g)
	ok(f("2026-11-11") and f("2026-11-17"), "last week includes Wed..Tue")
	ok(not f("2026-11-18") and not f("2026-11-10"), "and nothing else")
	local m = c.ns.PeriodFilter("month", g)
	ok(m("2026-11-01") and not m("2026-10-31"), "month filter")
	local r = c.ns.PeriodFilter({ from = "2026-11-01", to = "2026-11-08" }, g)
	ok(r("2026-11-07") and not r("2026-11-08"), "explicit range end is exclusive")
end)

test("the day rolls over at realm midnight", function()
	local w = NewWorld({ epoch = 1795003200 + 11 * 3600 + 50 * 60 }) -- 23:50 realm time
	local c = w:NewClient({ name = "Solo" })
	c:Login({ settle = 1 })
	eq(c.ns.Today(), "2026-11-18", "before midnight")
	c:Fire("LOOT_OPENED"); c:GainMoney(10); c:Fire("LOOT_CLOSED")
	w:Advance(20 * 60)
	eq(c.ns.Today(), "2026-11-19", "after midnight")
	c:Fire("LOOT_OPENED"); c:GainMoney(20); c:Fire("LOOT_CLOSED")
	local p = c:G().players[c.key]
	eq(p.days["2026-11-18"].g_loot, 10, "yesterday's gold")
	eq(p.days["2026-11-19"].g_loot, 20, "today's gold")
end)

test("before the game calendar loads, the realm day comes from server time, not the PC clock (fix)", function()
	-- Realm is UTC+1. Server time 23:30 UTC = 00:30 next day on the realm.
	local w = NewWorld({ epoch = 1795003200 + 11 * 3600 + 30 * 60 })
	w.realmOffset = 3600
	local c = w:NewClient({ name = "Solo" })
	c:Login({ settle = 1 })
	eq(c.ns.Today(), "2026-11-19", "learned realm day from the calendar")
	eq(c.ns.db.realmOffset, 3600, "offset remembered")
	c:Logout()
	w.calendarReady = false -- next login: calendar not ready yet
	c:Login({ settle = 1 })
	eq(c.ns.Today(), "2026-11-19", "still the realm day, from server time + offset")
end)

test("old days are pruned after 62 days", function()
	local w = NewWorld()
	local c = w:NewClient({ name = "Solo" })
	c:Login()
	SeedDay(c, "2026-08-01", { playtime = 100 })
	SeedDay(c, "2026-11-01", { playtime = 100 })
	c.ns.PruneOldDays()
	local p = c:G().players[c.key]
	eq(p.days["2026-08-01"], nil, "old day removed")
	ok(p.days["2026-11-01"], "recent day kept")
end)
