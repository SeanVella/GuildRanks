-- Tracking of your own character's stats

test("gold is split by source: loot, quest (either order), vendor, mail, Auction House, trade", function()
	local w = NewWorld()
	local _, sean = StandardGuild(w)
	sean:Login()
	sean:Fire("LOOT_OPENED"); sean:GainMoney(1234); sean:Fire("LOOT_CLOSED")
	w:Advance(3)
	-- quest money arriving BEFORE the quest event is re-labelled
	sean:GainMoney(5000); sean:Fire("QUEST_TURNED_IN", 1, 500, 5000)
	w:Advance(3)
	-- quest event BEFORE the money
	sean:Fire("QUEST_TURNED_IN", 2, 500, 700); sean:GainMoney(700)
	w:Advance(3)
	sean:Fire("MERCHANT_SHOW"); sean:GainMoney(300); sean:Fire("MERCHANT_CLOSED")
	sean:Fire("MAIL_SHOW")
	sean.invoiceType = nil; sean.env.TakeInboxMoney(1); sean:GainMoney(2000)
	sean.invoiceType = "seller"; sean.env.TakeInboxMoney(2); sean:GainMoney(9000)
	sean:Fire("MAIL_CLOSED")
	w:Advance(5)
	sean:Fire("TRADE_SHOW"); sean:Fire("TRADE_CLOSED"); sean:GainMoney(400)
	w:Advance(5)
	sean:GainMoney(50) -- nothing open: other
	local d = sean:Today()
	eq(d.g_loot, 1234, "loot")
	eq(d.g_quest, 5700, "quest")
	eq(d.g_vendor, 300, "vendor")
	eq(d.g_mail, 2000, "mail")
	eq(d.g_ah, 9000, "auction house")
	eq(d.g_trade, 400, "trade")
	eq(d.g_other, 50, "other")
	eq(d.quests, 2, "quests")
end)

test("spending money is not counted", function()
	local w = NewWorld()
	local _, sean = StandardGuild(w)
	sean:Login()
	sean:GainMoney(-5000)
	local d = sean:Today()
	eq(d.g_other, nil, "no negative gold")
end)

test("XP and levels gained, across a level-up, without double counting", function()
	local w = NewWorld()
	local _, sean = StandardGuild(w)
	sean.xp, sean.xpMax = 1000, 20000
	sean:Login()
	sean.xp = 19500; sean:Fire("PLAYER_XP_UPDATE")
	-- level-up where the XP update arrives before the level changes
	sean.xp = 300; sean:Fire("PLAYER_XP_UPDATE")
	sean.level = 35; sean:Fire("PLAYER_LEVEL_UP", 35); sean:Fire("PLAYER_XP_UPDATE")
	sean.xp = 1300; sean:Fire("PLAYER_XP_UPDATE")
	local d = sean:Today()
	eq(d.xp, 18500 + 500 + 300 + 1000, "xp")
	near(d.mlevels / 1000, 0.925 + 0.025 + 0.015 + 0.05, 0.0001, "levels gained")
	eq(sean:G().players[sean.key].level, 35, "stored level")
end)

test("kills, crafts, loot value (single and stacks), gathering, fishing, deaths", function()
	local w = NewWorld()
	local _, sean = StandardGuild(w)
	w.items[2589] = 25
	sean:Login()
	sean:Fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Miner dies, you gain 120 experience.")
	sean:Fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 300 experience.") -- quest XP: not a kill
	sean:Fire("CHAT_MSG_LOOT", "You create: |cffffffff|Hitem:2996::::::::|h[Bolt of Linen Cloth]|h|r.")
	sean:Fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r.")
	sean:Fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|rx4.")
	sean:Fire("CHAT_MSG_LOOT", "Kurt receives loot: |cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r.")
	sean:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 2366) -- Herb Gathering by ID
	sean:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 99999) -- unrelated spell
	sean.fishing = true; sean:Fire("LOOT_OPENED"); sean:Fire("LOOT_CLOSED"); sean.fishing = false
	sean:Fire("PLAYER_DEAD")
	local d = sean:Today()
	eq(d.kills, 1, "kills")
	eq(d.crafts, 1, "crafts")
	eq(d.lv_vendor, 25 * 5, "loot value")
	eq(d.lv_auction, 25 * 5, "auction value falls back to vendor")
	eq(d.gathers, 2, "gathering")
	eq(d.deaths, 1, "deaths")
end)

test("loot value waits for item data that isn't loaded yet", function()
	local w = NewWorld()
	local _, sean = StandardGuild(w)
	w.items[4306] = false
	sean:Login()
	sean:Fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:4306::::::::|h[Silk Cloth]|h|r.")
	eq(sean:Today().lv_vendor, nil, "not yet")
	w.items[4306] = 150
	w:Advance(2)
	eq(sean:Today().lv_vendor, 150, "added once loaded")
end)

test("boss kills and dungeon runs (run needs at least one boss)", function()
	local w = NewWorld()
	local _, sean = StandardGuild(w)
	sean:Login()
	sean.inInstance, sean.instanceType, sean.instanceID = true, "party", 36
	sean:Fire("ZONE_CHANGED_NEW_AREA")
	sean:Fire("ENCOUNTER_END", 1, "Rhahk'Zor", 1, 5, 1)
	sean:Fire("ENCOUNTER_END", 2, "Sneed", 1, 5, 0) -- wipe
	sean.inInstance, sean.instanceType, sean.instanceID = false, "none", 0
	sean:Fire("ZONE_CHANGED_NEW_AREA")
	-- second visit without a boss kill
	sean.inInstance, sean.instanceType, sean.instanceID = true, "party", 36
	sean:Fire("ZONE_CHANGED_NEW_AREA")
	sean.inInstance, sean.instanceType, sean.instanceID = false, "none", 0
	sean:Fire("ZONE_CHANGED_NEW_AREA")
	local d = sean:Today()
	eq(d.bosses, 1, "bosses")
	eq(d.dungeons, 1, "runs")
end)

test("damage and healing from the damage meter: baseline, deltas, reset", function()
	local w = NewWorld()
	local _, sean = StandardGuild(w)
	sean.meter.damage = 5000 -- from before login: must not count
	sean:Login()
	w:Advance(5)
	sean.inCombat = true
	sean.meter.damage, sean.meter.healing = 8000, 1200
	w:Advance(2)
	sean.inCombat = false
	sean:Fire("PLAYER_REGEN_ENABLED")
	w:Advance(3)
	eq(sean:Today().damage, 3000, "damage delta")
	eq(sean:Today().healing, 1200, "healing")
	sean:Fire("DAMAGE_METER_RESET")
	sean.meter.damage = 700
	sean:Fire("PLAYER_REGEN_ENABLED")
	w:Advance(3)
	eq(sean:Today().damage, 3700, "after reset")
	eq(sean.ns.Tracker.state.meterStatus, "OK", "status")
end)

test("hidden (secret) values in combat are never used in maths, and counted after combat", function()
	local w = NewWorld()
	local _, sean = StandardGuild(w)
	sean:Login()
	sean.inCombat = true
	sean:Fire("LOOT_OPENED")
	sean.money = sean.money + 777
	sean:Fire("PLAYER_MONEY") -- GetMoney() is secret now
	sean:Fire("LOOT_CLOSED")
	sean.xp = sean.xp + 50
	sean:Fire("PLAYER_XP_UPDATE") -- secret XP: skipped, picked up next update
	sean.ns.Tracker.SyncMeters() -- in combat: skipped
	eq(sean:Today().g_loot, nil, "nothing counted in combat")
	sean.inCombat = false
	sean:Fire("PLAYER_REGEN_ENABLED")
	w:Advance(3)
	eq((sean:Today().g_other or 0) + (sean:Today().g_loot or 0), 777, "money counted after combat")
	sean.xp = sean.xp + 10
	sean:Fire("PLAYER_XP_UPDATE")
	eq(sean:Today().xp, 60, "xp counted after combat")
end)

test("play time counts active time only (not AFK)", function()
	local w = NewWorld()
	local _, sean = StandardGuild(w)
	sean:Login()
	local start = sean:Today().playtime or 0
	w:Advance(600)
	local active = (sean:Today().playtime or 0) - start
	near(active, 600, 10, "10 active minutes")
	sean.afk = true
	w:Advance(600)
	near((sean:Today().playtime or 0) - start, 600, 10, "AFK not counted")
end)

test("stats before the guild is known are kept and added once it loads", function()
	local w = NewWorld()
	local _, sean = StandardGuild(w)
	sean.guildInfoDelay = w.now + 6 -- guild name not available for 6 seconds
	sean:Login({ settle = 1 })
	eq(sean.ns.gkey, nil, "guild not known yet")
	sean:Fire("LOOT_OPENED"); sean:GainMoney(500); sean:Fire("LOOT_CLOSED")
	w:Advance(10)
	eq(sean.ns.gkey, "Froga", "guild resolved")
	eq(sean:Today().g_loot, 500, "queued gold added")
end)

test("healing counts your own spells only: no potions, healthstones, bandages or Leech (fix)", function()
	local w = NewWorld()
	local _, sean = StandardGuild(w)
	sean:Login()
	w:Advance(5)
	sean.meter.healSpells = {
		{ 2061, 1000 },  -- Flash Heal (your spell)
		{ 33110, 400 },  -- Prayer of Mending heal: own spell ID, same name as the spell you know
		{ 6262, 500 },   -- Healthstone
		{ 441, 300 },    -- Healing Potion
		{ 10839, 200 },  -- bandage
		{ 143924, 100 }, -- Leech (gear)
	}
	sean:Fire("PLAYER_REGEN_ENABLED")
	w:Advance(3)
	eq(sean:Today().healing, 1400, "only Flash Heal and Prayer of Mending")
	ok(sean.ns.Tracker.IsOwnSpell(2061), "Flash Heal is yours")
	ok(not sean.ns.Tracker.IsOwnSpell(6262), "Healthstone isn't")
end)

test("no damage spike when the meter briefly doesn't list you (fix)", function()
	local w = NewWorld()
	local _, sean = StandardGuild(w)
	sean.meter.damage = 50000
	sean:Login()
	w:Advance(5)
	sean.meter.damage = 52000
	sean:Fire("PLAYER_REGEN_ENABLED"); w:Advance(3)
	eq(sean:Today().damage, 2000, "normal fight")
	sean.meter.hideLocal = true -- e.g. right after a loading screen
	sean:Fire("PLAYER_REGEN_ENABLED"); w:Advance(3)
	sean.meter.hideLocal = false
	sean.meter.damage = 53000
	sean:Fire("PLAYER_REGEN_ENABLED"); w:Advance(3)
	eq(sean:Today().damage, 3000, "only the new 1000, not the whole 53000 again")
end)

test("an impossible jump in damage is ignored (safety net)", function()
	local w = NewWorld()
	local _, sean = StandardGuild(w)
	sean.meter.aps = 100 -- your overall average: 100 damage per second
	sean:Login()
	w:Advance(5)
	sean.meter.damage = 30000 -- a believable fight
	sean:Fire("PLAYER_REGEN_ENABLED"); w:Advance(3)
	eq(sean:Today().damage, 30000, "counted")
	sean.meter.damage = 30000 + 50000000 -- 50 million in a few seconds at 100/s average
	sean:Fire("PLAYER_REGEN_ENABLED"); w:Advance(3)
	eq(sean:Today().damage, 30000, "ignored")
	ok((sean.ns.Tracker.state.meterCapped or 0) >= 1, "noted")
end)

test("deaths count even when the game's death event doesn't arrive, and never twice (fix)", function()
	local w = NewWorld()
	local _, sean = StandardGuild(w)
	sean:Login()
	sean:Die(true) -- no PLAYER_DEAD event
	w:Advance(6)
	eq(sean:Today().deaths, 1, "noticed by the health check")
	w:Advance(60) -- still dead / ghost
	eq(sean:Today().deaths, 1, "counted once")
	sean:Revive(); w:Advance(6)
	sean:Die() -- with the event
	w:Advance(6)
	eq(sean:Today().deaths, 2, "event and health check together count once")
	-- logging in while already dead isn't a new death
	sean:Logout()
	sean:Login()
	w:Advance(10)
	eq(sean:Today().deaths, 2, "no new death on login")
end)
