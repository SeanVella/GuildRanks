-- Guild rules: who may change them, and how they spread

local function Publish(client, changes)
	local r = client:G().rules
	for k, v in pairs(changes) do r[k] = v end
	client.ns.Comm.PublishRules()
end

test("an officer's rules reach every member, with all fields", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	kurt:Login(); sean:Login(); maria:Login()
	w:Advance(30)
	sean:G().rules.gold.mail = false
	Publish(sean, { resetDay = 3, minMinutes = 45, showSpoon = false, itemValue = "auction",
		challengeMetric = "quests", challengePrize = "100g; from bank", goalMetric = "gold", goalTarget = 50000000, announceMVP = true })
	w:Advance(30)
	local r = maria:G().rules
	eq(r.resetDay, 3, "reset day")
	eq(r.minMinutes, 45, "min minutes")
	eq(r.gold.mail, false, "mail excluded")
	eq(r.gold.loot, true, "loot included")
	eq(r.showSpoon, false, "spoon off")
	eq(r.itemValue, "auction", "item value")
	eq(r.challengeMetric, "quests", "challenge")
	eq(r.challengePrize, "100g  from bank", "prize (cleaned)")
	eq(r.goalMetric, "gold", "goal metric")
	eq(r.goalTarget, 50000000, "goal target")
	eq(r.announceMVP, true, "announce MVP")
	eq(r.by, "Sean", "set by")
	eq(kurt:G().rules.resetDay, 3, "GM got it too")
end)

test("a regular member can't change the rules", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	kurt:Login(); maria:Login()
	w:Advance(30)
	ok(not maria.ns.CanEditRules(), "Maria may not edit")
	Publish(maria, { minMinutes = 1 })
	w:Advance(30)
	eq(kurt:G().rules.minMinutes, 30, "ignored by others")
end)

test("the Guild Master can let more ranks change rules; only the GM can change that", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	kurt:Login(); sean:Login(); maria:Login()
	w:Advance(30)
	-- officer tries to widen permissions: others keep managerRank 1
	Publish(sean, { managerRank = 5 })
	w:Advance(30)
	eq(maria:G().rules.managerRank, 1, "officer can't change who manages")
	-- GM allows rank 3
	Publish(kurt, { managerRank = 3 })
	w:Advance(30)
	eq(maria:G().rules.managerRank, 3, "GM's change accepted")
	ok(maria.ns.CanEditRules(), "Maria may edit now")
	Publish(maria, { minMinutes = 20 })
	w:Advance(30)
	eq(sean:G().rules.minMinutes, 20, "Maria's rules accepted")
end)

test("rules that arrive before the roster loads are applied once it does (fix)", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	kurt:Login()
	w:Advance(5)
	kurt:G().rules.minMinutes = 15
	kurt:G().rules.version = 1795000000
	kurt:G().rules.excludedFor = 1795000000
	kurt:G().rules.excluded["Cheater-Firemaw"] = true
	-- Sean logs in but his roster hasn't loaded yet when the rules arrive
	sean:Login({ settle = 0 })
	sean.ns.roster, sean.ns.rosterReady, sean.ns.rosterComplete = {}, false, false
	-- Sean's roster read is delayed: hold it back by clearing it whenever it loads
	local realRead = sean.ns.ReadRoster
	sean.ns.ReadRoster = function() end
	kurt.ns.Comm.QueueRules()
	w:Advance(15) -- C and E arrive while Sean's roster is still unknown
	eq(sean:G().rules.minMinutes, 30, "not applied without knowing Kurt's rank")
	-- now the roster loads
	realRead()
	eq(sean:G().rules.minMinutes, 15, "held rules applied after roster")
	ok(sean:G().rules.excluded["Cheater-Firemaw"], "held exclusions applied")
end)

test("excluded players disappear from boards and scores everywhere", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	kurt:Login(); sean:Login(); maria:Login()
	for _, c in ipairs({ kurt, sean, maria }) do
		c:Fire("LOOT_OPENED"); c:GainMoney(1000 * c.level); c:Fire("LOOT_CLOSED")
	end
	w:Advance(2400)
	ok(#sean.ns.BuildBoard(sean:G(), "gold", "week", false, 0) == 3, "three on the board")
	kurt:G().rules.excluded[maria.key] = true
	kurt.ns.Comm.PublishRules()
	w:Advance(30)
	local rows = sean.ns.BuildBoard(sean:G(), "gold", "week", false, 0)
	eq(#rows, 2, "Maria excluded on Sean's board")
	for _, r in ipairs(sean.ns.ComputeScores(sean:G(), "week", 0)) do ok(r.key ~= maria.key, "not in scores") end
	-- and included again
	kurt:G().rules.excluded[maria.key] = nil
	kurt.ns.Comm.PublishRules()
	w:Advance(30)
	eq(#sean.ns.BuildBoard(sean:G(), "gold", "week", false, 0), 3, "back after including")
end)

test("older rule versions never overwrite newer ones", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	kurt:Login(); sean:Login()
	w:Advance(30)
	Publish(kurt, { minMinutes = 50 })
	w:Advance(30)
	local v = sean:G().rules.version
	-- replay an old rules message
	sean:Fire("CHAT_MSG_ADDON", "GuildRanks", "C;1;1;4;5;1111111;1;1;v;Old;;;;0;0", "GUILD", kurt.key)
	eq(sean:G().rules.minMinutes, 50, "kept the newer rules")
	eq(sean:G().rules.version, v, "version unchanged")
end)
