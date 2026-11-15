-- Sharing data between guild members over the (simulated) guild addon channel

local function PlayerDay(client, other)
	local p = client:G().players[other.key]
	return p and p.days[client.ns.Today()]
end

test("two members exchange their stats after logging in", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	kurt:Login(); sean:Login()
	kurt:Fire("LOOT_OPENED"); kurt:GainMoney(4000); kurt:Fire("LOOT_CLOSED")
	sean:Fire("LOOT_OPENED"); sean:GainMoney(1500); sean:Fire("LOOT_CLOSED")
	w:Advance(90)
	local seenBySean = PlayerDay(sean, kurt)
	local seenByKurt = PlayerDay(kurt, sean)
	ok(seenBySean, "Sean has Kurt's day")
	ok(seenByKurt, "Kurt has Sean's day")
	eq(seenBySean.g_loot, 4000, "Kurt's gold as seen by Sean")
	eq(seenByKurt.g_loot, 1500, "Sean's gold as seen by Kurt")
	eq(sean:G().players[kurt.key].class, "WARRIOR", "class shared")
end)

test("five-minute updates keep everyone current", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	kurt:Login(); sean:Login()
	w:Advance(60)
	kurt:Fire("LOOT_OPENED"); kurt:GainMoney(999); kurt:Fire("LOOT_CLOSED")
	w:Advance(320)
	eq(PlayerDay(sean, kurt).g_loot, 999, "update arrived")
end)

test("a member who logs in later receives offline members' data via relay", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	kurt:Login(); maria:Login()
	maria:Fire("LOOT_OPENED"); maria:GainMoney(3333); maria:Fire("LOOT_CLOSED")
	w:Advance(90)
	ok(PlayerDay(kurt, maria), "Kurt has Maria's data")
	maria:Logout()
	w:Advance(30)
	local claimsBefore = #w:MessagesOfKind("L")
	sean:Login()
	w:Advance(120)
	local relayed = PlayerDay(sean, maria)
	ok(relayed, "Sean got offline Maria's data")
	eq(relayed.g_loot, 3333, "relayed value")
	ok(#w:MessagesOfKind("X") >= 1, "relay messages were used")
	eq(#w:MessagesOfKind("L") - claimsBefore, 1, "exactly one member relayed for Sean")
end)

test("Blizzard's message limit is respected and no message is too long", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	kurt:Login()
	-- lots of history to send
	for d = 0, 7 do
		SeedDay(kurt, kurt.ns.ShiftDay(kurt.ns.Today(), -d), { playtime = 3600, g_loot = 123456789, xp = 99999, damage = 987654321 })
	end
	sean:Login()
	kurt.ns.Comm.SyncNow()
	w:Advance(120)
	eq(w.throttled or 0, 0, "no throttled sends")
	for _, s in ipairs(w.sent) do ok(#s.msg <= 255, "message length " .. #s.msg) end
	eq(kurt.ns.Comm.QueueLength(), 0, "queue drained")
	local p = sean:G().players[kurt.key]
	local days = 0
	for _ in pairs(p.days) do days = days + 1 end
	eq(days, 8, "all 8 days arrived")
end)

test("sharing pauses inside instances and during chat lockdown, then resumes", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	kurt:Login(); sean:Login()
	w:Advance(60)
	sean.inInstance = true
	local before = #w:MessagesOfKind("D", sean.key)
	sean.ns.Comm.SyncNow()
	w:Advance(60)
	eq(#w:MessagesOfKind("D", sean.key), before, "nothing sent inside the instance")
	sean.inInstance = false
	w.lockdown = true
	w:Advance(30)
	eq(#w:MessagesOfKind("D", sean.key), before, "nothing sent during lockdown")
	w.lockdown = false
	w:Advance(30)
	ok(#w:MessagesOfKind("D", sean.key) > before, "sent after leaving")
end)

test("turning off 'Share my stats' removes you from guildmates' boards, even via relay", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	kurt:Login(); sean:Login(); maria:Login()
	sean:Fire("LOOT_OPENED"); sean:GainMoney(1000); sean:Fire("LOOT_CLOSED")
	w:Advance(90)
	ok(kurt:G().players[sean.key], "Kurt sees Sean")
	sean.ns.Comm.SetShare(false)
	w:Advance(10)
	eq(kurt:G().players[sean.key], nil, "removed from Kurt")
	eq(maria:G().players[sean.key], nil, "removed from Maria")
	-- a relay from someone who still had old data must not bring him back
	maria:Logout(); w:Advance(5); maria:Login(); w:Advance(120)
	eq(maria:G().players[sean.key], nil, "still hidden after relay")
	sean:GainMoney(5) -- he keeps tracking locally
	sean.ns.Comm.SetShare(true)
	w:Advance(30)
	ok(kurt:G().players[sean.key], "back after turning sharing on")
end)

test("messages from other addons, other channels and self are ignored", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	sean:Login()
	sean:Fire("CHAT_MSG_ADDON", "OtherAddon", "D;1;X;1;1;2026-11-18;zz", "GUILD", kurt.key)
	sean:Fire("CHAT_MSG_ADDON", "GuildRanks", "D;1;WARRIOR;41;1.0;2026-11-18;zz", "WHISPER", kurt.key)
	sean:Fire("CHAT_MSG_ADDON", "GuildRanks", "D;1;MAGE;34;1.0;2026-11-18;zz", "GUILD", sean.key)
	sean:Fire("CHAT_MSG_ADDON", "GuildRanks", "D;9;WARRIOR;41;1.0;2026-11-18;zz", "GUILD", kurt.key) -- other protocol
	sean:Fire("CHAT_MSG_ADDON", "GuildRanks", "D;1;WARRIOR;41;1.0;1999-01-01;zz", "GUILD", kurt.key) -- too old
	local p = sean:G().players[kurt.key]
	local days = 0
	for _ in pairs(p and p.days or {}) do days = days + 1 end
	eq(days, 0, "nothing stored")
end)

test("two members logging in close together both get the guild's data (fix)", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	kurt:Login()
	w:Advance(90)
	kurt:Fire("LOOT_OPENED"); kurt:GainMoney(500); kurt:Fire("LOOT_CLOSED")
	w:Advance(5)
	maria:Login()
	w:Advance(30)  -- Kurt answers Maria's sync request
	sean:Login()   -- Sean's request comes within the same minute
	w:Advance(150)
	local day = kurt.ns.Today()
	ok(maria:G().players[kurt.key] and maria:G().players[kurt.key].days[day], "Maria has Kurt's data")
	ok(sean:G().players[kurt.key] and sean:G().players[kurt.key].days[day], "Sean has Kurt's data too")
end)
