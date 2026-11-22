-- Guild Ranks test kit: a simulated World of Warcraft.
-- Several players ("clients") each run their own copy of the addon in their own
-- environment and talk over a shared, simulated guild addon channel with
-- Blizzard's per-prefix throttle (10 messages burst, 1 per second). The world has
-- a fake clock and timers, a guild roster, combat "secret values", instances and
-- chat lockdown, so tests can drive whole scenarios deterministically.
-- Runs on Lua 5.1 (what WoW uses) and Lua 5.3+.

local unpack = unpack or table.unpack
local W = {}
W.__index = W

local ADDON_FILES -- read from the TOC

local function DeepCopy(v, seen)
	if type(v) ~= "table" then return v end
	seen = seen or {}
	if seen[v] then return seen[v] end
	local t = {}
	seen[v] = t
	for k, x in pairs(v) do t[DeepCopy(k, seen)] = DeepCopy(x, seen) end
	return t
end
W.DeepCopy = DeepCopy

-- A value addons may display but not read (what issecretvalue() detects).
-- Any arithmetic or comparison on it raises an error, like in the real client.
local SecretMT = {}
local function Boom() error("arithmetic or comparison on a secret value", 2) end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__unm", "__lt", "__le", "__concat", "__pow" }) do SecretMT[op] = Boom end
SecretMT.__tostring = function() return "<secret>" end
local function Secret() return setmetatable({}, SecretMT) end
W.Secret = Secret
local function IsSecret(v) return type(v) == "table" and getmetatable(v) == SecretMT end

---------------------------------------------------------------------------
-- World
---------------------------------------------------------------------------
function W.New(opts)
	opts = opts or {}
	local world = setmetatable({}, W)
	world.addonDir = opts.addonDir or "."
	-- Realm clock: 2026-11-18 (a Wednesday) 12:00 UTC by default
	world.epoch = opts.epoch or 1795003200
	world.now = 1000              -- GetTime()
	world.timers = {}
	world.clients = {}
	world.guilds = {}             -- name -> { clubId, members = { key -> member } }
	world.chat = {}               -- guild chat lines { sender, msg }
	world.sent = {}               -- every addon message { from, msg, result }
	world.errors = {}
	world.calendarReady = true
	world.realmOffset = 0         -- realm time = server time + offset
	world.items = {}              -- itemID -> sell price
	world.verbose = opts.verbose
	return world
end

function W:AddGuild(name, clubId)
	self.guilds[name] = { name = name, clubId = clubId or tostring(math.random(100000, 999999)), members = {} }
	return self.guilds[name]
end

-- Offline guild member without the addon (only shows in the roster)
function W:AddRosterMember(guild, key, rankIndex, level, class)
	self.guilds[guild].members[key] = { key = key, rankIndex = rankIndex, rankName = "Rank " .. rankIndex,
		level = level or 10, class = class or "WARRIOR", online = false }
end

W.seq = 0
local function NextSeq(self)
	self.seq = self.seq + 1
	return self.seq
end

-- owner (optional): a client; its timers stop when it logs out
function W:After(delay, fn, owner)
	self.timers[#self.timers + 1] = { at = self.now + delay, fn = fn, seq = NextSeq(self),
		owner = owner, session = owner and owner.session }
end

function W:Ticker(every, fn, owner)
	local t = { at = self.now + every, fn = fn, every = every, seq = NextSeq(self), owner = owner, session = owner and owner.session }
	t.Cancel = function() t.cancelled = true end
	self.timers[#self.timers + 1] = t
	return t
end

-- Move the clock forward, running timers in order
function W:Advance(seconds, step)
	local target = self.now + seconds
	while true do
		local best, bi
		for i, t in ipairs(self.timers) do
			if not best or t.at < best.at or (t.at == best.at and t.seq < best.seq) then best, bi = t, i end
		end
		if not best or best.at > target then break end
		table.remove(self.timers, bi)
		self.now = best.at
		self.epochNow = nil
		local stale = best.owner and (not best.owner.online or best.owner.session ~= best.session)
		if not best.cancelled and not stale then
			local ok, err = pcall(best.fn)
			if not ok then self:Error("timer", err) end
			if best.every and not best.cancelled then
				best.at = self.now + best.every
				best.seq = NextSeq(self)
				self.timers[#self.timers + 1] = best
			end
		end
	end
	self.now = target
end

function W:ServerTime()
	return self.epoch + math.floor(self.now - 1000)
end

function W:Error(where, err)
	self.errors[#self.errors + 1] = where .. ": " .. tostring(err)
	if self.verbose then print("ERROR", where, err) end
end

---------------------------------------------------------------------------
-- Guild channel (with Blizzard's per-prefix throttle)
---------------------------------------------------------------------------
function W:SendAddon(client, prefix, msg, chatType)
	if chatType ~= "GUILD" then return 4 end
	if #msg > 255 then
		self.sent[#self.sent + 1] = { from = client.key, msg = msg, result = 2 }
		return 2
	end
	if client.inInstance or self.lockdown then return 11 end
	-- throttle: allowance regains 1 per second up to 10
	local th = client.throttle
	th.allowance = math.min(10, th.allowance + (self.now - th.last))
	th.last = self.now
	if th.allowance < 1 then
		self.throttled = (self.throttled or 0) + 1
		self.sent[#self.sent + 1] = { from = client.key, msg = msg, result = 3 }
		return 3
	end
	th.allowance = th.allowance - 1
	self.sent[#self.sent + 1] = { from = client.key, msg = msg, result = 0 }
	local guild = client.guild
	self:After(0.05, function()
		for _, other in ipairs(self.clients) do
			-- the sender gets its own message back too, like the real game
			if other.online and other.guild == guild and other.prefixes[prefix] and (other == client or not other.inInstance) then
				other:Fire("CHAT_MSG_ADDON", prefix, msg, "GUILD", self:SenderName(client))
			end
		end
	end)
	return 0
end

-- The sender name receivers see: "Full Name-Realm". With world.shards (WoW: Forever) the realm
-- part changes from message to message.
function W:SenderName(client)
	local realm = client.realm
	if self.shards then
		self.shardTurn = (self.shardTurn or 0) + 1
		realm = self.shards[self.shardTurn % #self.shards + 1]
	end
	return client.fullName .. "-" .. realm
end

function W:MessagesOfKind(kind, from)
	local list = {}
	for _, s in ipairs(self.sent) do
		if s.result == 0 and s.msg:sub(1, #kind + 1) == kind .. ";" and (not from or s.from == from) then list[#list + 1] = s end
	end
	return list
end

---------------------------------------------------------------------------
-- Clients
---------------------------------------------------------------------------
local Client = {}
Client.__index = Client
W.Client = Client

function W:NewClient(o)
	local c = setmetatable({}, Client)
	c.world = self
	c.name = o.name                                    -- what UnitName("player") returns
	c.realm = o.realm or "Firemaw"
	c.fullName = o.surname and (o.name .. " " .. o.surname) or o.name -- what other players see
	c.key = c.fullName                                 -- how the addon stores this player
	c.guid = "Player-" .. c.name
	c.guild = o.guild
	c.rankIndex = o.rank or 3
	c.level = o.level or 30
	c.class = o.class or "WARRIOR"
	c.xp, c.xpMax = o.xp or 0, o.xpMax or 20000
	c.money = o.money or 10000
	c.online = false
	c.afk, c.inCombat, c.inInstance = false, false, false
	c.instanceID = 0
	c.prefixes = {}
	c.throttle = { allowance = 10, last = self.now }
	c.frames = {}
	c.printed = {}
	c.saved = o.saved
	c.addons = o.addons or {}
	c.invoiceType = nil
	c.meter = { damage = 0, healing = 0, healSpells = nil, hideLocal = false }
	c.knownSpells = { [2061] = "Flash Heal", [33076] = "Prayer of Mending" } -- spellbook (id -> name)
	c.dead = false
	self.clients[#self.clients + 1] = c
	if c.guild then
		local g = self.guilds[c.guild] or self:AddGuild(c.guild)
		g.members[c.key] = { key = c.fullName .. "-" .. c.realm, guid = c.guid, rankIndex = c.rankIndex, rankName = "Rank " .. c.rankIndex,
			level = c.level, class = c.class, online = false, client = c }
	end
	return c
end

-- Frames: any method works; the few the addon reads back return sensible values
local FrameMT = {}
FrameMT.__index = function(t, k)
	if type(k) == "string" and k:sub(1, 1) == "_" then return nil end
	return function(self, ...)
		local a = ...
		if k == "SetScript" then
			local ev, fn = ...
			rawset(self, "_s_" .. ev, fn)
		elseif k == "GetScript" then return rawget(self, "_s_" .. a)
		elseif k == "RegisterEvent" or k == "RegisterUnitEvent" then
			local e = rawget(self, "_events") or {}
			rawset(self, "_events", e)
			e[a] = true
		elseif k == "IsShown" or k == "IsVisible" then return rawget(self, "_shown") or false
		elseif k == "Show" then
			rawset(self, "_shown", true)
			local f = rawget(self, "_s_OnShow")
			if f then f(self) end
		elseif k == "Hide" then rawset(self, "_shown", false)
		elseif k == "SetShown" then if a then self:Show() else self:Hide() end
		elseif k == "GetChecked" then return rawget(self, "_checked")
		elseif k == "SetChecked" then rawset(self, "_checked", a)
		elseif k == "HasFocus" then return false
		elseif k == "GetText" then return rawget(self, "_text") or ""
		elseif k == "SetText" then rawset(self, "_text", a)
		elseif k == "GetParent" then return rawget(self, "_parent")
		elseif k == "GetPoint" then return "CENTER", nil, "CENTER", 0, 0
		elseif k == "SetSize" then rawset(self, "_w", a); rawset(self, "_h", select(2, ...))
		elseif k == "SetWidth" then rawset(self, "_w", a)
		elseif k == "SetHeight" then rawset(self, "_h", a)
		elseif k == "GetWidth" then return rawget(self, "_w") or 100
		elseif k == "GetHeight" then return rawget(self, "_h") or 100
		elseif k == "GetStringWidth" or k == "GetStringHeight" then return 100
		elseif k == "CreateFontString" or k == "CreateTexture" then
			return setmetatable({ _parent = self }, FrameMT)
		elseif k == "SetupMenu" then rawset(self, "_menu", a)
		elseif k == "IsEnabled" then return rawget(self, "_disabled") ~= true
		elseif k == "Enable" then rawset(self, "_disabled", false)
		elseif k == "Disable" then rawset(self, "_disabled", true)
		end
	end
end
W.FrameMT = FrameMT

local function LoadInto(path, env)
	if setfenv then
		local f, err = loadfile(path)
		if not f then error(err) end
		setfenv(f, env)
		return f
	end
	local f, err = loadfile(path, "t", env)
	if not f then error(err) end
	return f
end

local function TocFiles(dir)
	local files = {}
	for line in io.lines(dir .. "/GuildRanks.toc") do
		line = line:gsub("\r", "")
		-- Bundled libraries only exist in the release zip; tests use mock libraries.
		if not line:match("^#") and line:match("%S") and not line:match("^Libs\\") then files[#files + 1] = (line:gsub("\\", "/")) end
	end
	return files
end

function Client:BuildEnv()
	local c, world = self, self.world
	local env = setmetatable({}, { __index = _G })
	env._G = env
	env.unpack = unpack
	env.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
		local line = table.concat(parts, " ")
		c.printed[#c.printed + 1] = line
		if world.verbose then io.write("[" .. c.name .. "] " .. line .. "\n") end
	end
	env.geterrorhandler = function() return function(err) world:Error(c.name, err) end end
	env.time = function(t) if t then return os.time(t) end return world:ServerTime() end
	env.date = function(fmt, t) return os.date(fmt, t or world:ServerTime()) end
	env.GetTime = function() return world.now end
	env.GetServerTime = function() return world:ServerTime() end
	env.C_Timer = {
		After = function(d, fn) world:After(d, fn, c) end,
		NewTicker = function(d, fn) return world:Ticker(d, fn, c) end,
	}
	env.C_DateAndTime = { GetCurrentCalendarTime = function()
		if not world.calendarReady then return { year = 0, month = 0, monthDay = 0, weekday = 0, hour = 0, minute = 0 } end
		local t = os.date("!*t", world:ServerTime() + world.realmOffset)
		return { year = t.year, month = t.month, monthDay = t.day, weekday = t.wday, hour = t.hour, minute = t.min }
	end }
	env.C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return c.version or "1.1.0" end end }
	env.issecretvalue = IsSecret
	env.CreateFrame = function(kind, name, parent)
		local f = setmetatable({ _kind = kind, _parent = parent }, FrameMT)
		c.frames[#c.frames + 1] = f
		if name then env[name] = f end
		return f
	end
	env.UIParent = setmetatable({}, FrameMT)
	env.GameTooltip = setmetatable({}, FrameMT)
	env.UISpecialFrames = {}
	env.tinsert = table.insert
	env.ChatFontNormal = {}
	env.SlashCmdList = {}
	env.CLOSE = "Close"
	env.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { colorStr = "ffffffff" } end })
	env.COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
	env.LOOT_ITEM_CREATED_SELF = "You create: %s."
	env.LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
	env.LOOT_ITEM_SELF = "You receive loot: %s."
	env.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
	env.Enum = { DamageMeterSessionType = { Overall = 0, Current = 1, Expired = 2 },
		DamageMeterType = { DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3 } }
	-- Healing per spell: c.meter.healSpells = { { id, amount }, ... }, or all of c.meter.healing as Flash Heal
	local function HealSpells()
		if c.meter.healSpells then return c.meter.healSpells end
		return { { 2061, c.meter.healing } }
	end
	env.C_DamageMeter = {
		GetCombatSessionFromType = function(_, meterType)
			local amount
			if meterType == 2 then
				amount = 0
				for _, sp in ipairs(HealSpells()) do amount = amount + sp[2] end
			else
				amount = (meterType == 0) and c.meter.damage or 0
			end
			if c.inCombat then amount = Secret() end
			local sources = { { isLocalPlayer = false, totalAmount = 5 } }
			if not c.meter.hideLocal then sources[2] = { isLocalPlayer = true, totalAmount = amount, amountPerSecond = c.meter.aps } end
			return { combatSources = sources }
		end,
		GetCombatSessionSourceFromType = function(_, meterType, guid)
			if c.inCombat then return Secret() end
			if c.meter.hideLocal or guid ~= "Player-" .. c.name then return nil end
			if meterType ~= 2 then return { totalAmount = c.meter.damage, combatSpells = {} } end
			local spells, total = {}, 0
			for _, sp in ipairs(HealSpells()) do
				spells[#spells + 1] = { spellID = sp[1], totalAmount = sp[2] }
				total = total + sp[2]
			end
			return { totalAmount = total, combatSpells = spells }
		end,
	}
	env.UnitGUID = function(unit) return unit == "player" and c.guid or nil end
	env.IsPlayerSpell = function(id) return c.knownSpells[id] ~= nil end
	env.UnitIsDeadOrGhost = function(unit) return unit == "player" and c.dead or false end
	env.C_ChatInfo = {
		RegisterAddonMessagePrefix = function(p) c.prefixes[p] = true return true end,
		IsAddonMessagePrefixRegistered = function(p) return c.prefixes[p] == true end,
		SendAddonMessage = function(p, msg, chatType) return world:SendAddon(c, p, msg, chatType) end,
		InChatMessagingLockdown = function() return world.lockdown or false end,
		SendChatMessage = function(msg, chatType)
			if chatType == "GUILD" and c.guild then world.chat[#world.chat + 1] = { sender = c.key, msg = msg } end
		end,
	}
	env.C_GuildInfo = { GuildRoster = function()
		if c.guild then world:After(0.2, function() if c.online then c:Fire("GUILD_ROSTER_UPDATE") end end) end
	end }
	env.C_Club = { GetGuildClubId = function() return c.guild and world.guilds[c.guild].clubId or nil end }
	env.IsInGuild = function() return c.guild ~= nil end
	env.GetGuildInfo = function(unit)
		if unit ~= "player" or not c.guild then return nil end
		if c.guildInfoDelay and world.now < c.guildInfoDelay then return nil end
		return c.guild, "Rank " .. c.rankIndex, c.rankIndex, nil
	end
	local function RosterList()
		local list = {}
		if not c.guild then return list end
		for _, m in pairs(world.guilds[c.guild].members) do list[#list + 1] = m end
		table.sort(list, function(a, b) return a.key < b.key end)
		return list
	end
	env.GetNumGuildMembers = function() return #RosterList() end
	env.GetGuildRosterLastOnline = function(i)
		local m = RosterList()[i]
		if not m or (m.client and m.client.online) then return nil end
		local days = m.lastDays or 0
		return 0, 0, math.floor(days), math.floor((days % 1) * 24)
	end
	env.GetGuildRosterInfo = function(i)
		local m = RosterList()[i]
		if not m then return nil end
		local online = m.client and m.client.online or false
		if world.partialRoster and i % 2 == 0 then return nil end -- Blizzard returning incomplete data
		local level = m.client and m.client.level or m.level
		return m.key, m.rankName, m.rankIndex, level, m.class, "", "", "", online, 0, m.class,
			0, false, false, false, 0, (not world.noRosterGUID) and (m.guid or ("Player-" .. m.key)) or nil
	end
	env.GetNormalizedRealmName = function() return c.realm end
	env.GetRealmName = function() return c.realm end
	env.UnitName = function() return c.name end
	env.IsTrialAccount = function() return c.trial == true end
	env.RequestTimePlayed = function()
		world:After(0.5, function() c:Fire("TIME_PLAYED_MSG", c.played or 360000, 3600) end, c)
	end
	-- professions: c.profs = { { name, skill, max, skillLine }, ... }
	env.GetProfessions = function()
		local p = c.profs or {}
		return p[1] and 1 or nil, p[2] and 2 or nil, nil, p[3] and 3 or nil, p[4] and 4 or nil
	end
	env.GetProfessionInfo = function(i)
		local pr = (c.profs or {})[i]
		if not pr then return nil end
		return pr[1], 0, pr[2], pr[3], 0, 0, pr[4]
	end
	env.UnitClass = function() return c.class, c.class end
	env.UnitLevel = function() return c.level end
	env.UnitXP = function() return c.inCombat and Secret() or c.xp end
	env.UnitXPMax = function() return c.xpMax end
	env.GetMoney = function() return c.inCombat and Secret() or c.money end
	env.UnitIsAFK = function() return c.afk end
	env.UnitAffectingCombat = function() return c.inCombat end
	env.InCombatLockdown = function() return c.inCombat end
	env.IsInInstance = function() return c.inInstance, c.inInstance and (c.instanceType or "party") or "none" end
	env.GetInstanceInfo = function() return "Instance", c.instanceType or "none", 1, "", 5, 0, false, c.instanceID end
	env.GetMaxLevelForPlayerExpansion = function() return 60 end
	env.GetBuildInfo = function() return "1.60.1", "70000", "Nov 1 2026", 16001 end
	env.GetLocale = function() return "enUS" end
	env.IsFishingLoot = function() return c.fishing or false end
	local SPELL_NAMES = { [2366] = "Herb Gathering", [2575] = "Mining", [8613] = "Skinning", [2061] = "Flash Heal",
		[33076] = "Prayer of Mending", [33110] = "Prayer of Mending", [6262] = "Healthstone", [441] = "Healing Potion",
		[10839] = "Heavy Runecloth Bandage", [143924] = "Leech" }
	env.C_Spell = {
		GetSpellName = function(id) return SPELL_NAMES[id] or c.knownSpells[id] end,
		-- by name: only spells you know (like the real API)
		GetSpellInfo = function(idOrName)
			if type(idOrName) == "string" then
				for _, name in pairs(c.knownSpells) do if name == idOrName then return { name = name } end end
				return nil
			end
			local name = SPELL_NAMES[idOrName] or c.knownSpells[idOrName]
			return name and { name = name, spellID = idOrName } or nil
		end,
	}
	env.C_Item = {
		GetItemInfo = function(link)
			local id = tonumber(tostring(link):match("item:(%d+)"))
			if world.items[id] == false then return nil end -- not cached yet
			return "Item" .. tostring(id), link, 1, 1, 1, "", "", 20, "", 0, world.items[id] or 100
		end,
		RequestLoadItemDataByID = function() end,
	}
	env.GetInboxInvoiceInfo = function() return c.invoiceType end
	env.TakeInboxMoney = function() end
	env.AutoLootMailItem = function() end
	env.hooksecurefunc = function(name, hook)
		local orig = env[name]
		env[name] = function(...)
			local r = { orig(...) }
			hook(...)
			return unpack(r)
		end
	end
	for k, v in pairs(c.addons) do env[k] = v end -- optional third-party addons (TSM_API, Auctionator, LibStub)
	return env
end

-- Log in: load the addon (with this character's saved data) and fire login events
function Client:Login(opts)
	opts = opts or {}
	local world = self.world
	self.online = true
	self.session = (self.session or 0) + 1
	self.frames = {}
	self.prefixes = {}
	self.env = self:BuildEnv()
	self.env.GuildRanksDB = self.saved and DeepCopy(self.saved) or nil
	if self.guild then world.guilds[self.guild].members[self.key].online = true end
	self.ns = {}
	ADDON_FILES = ADDON_FILES or TocFiles(world.addonDir)
	for _, file in ipairs(ADDON_FILES) do
		local f = LoadInto(world.addonDir .. "/" .. file, self.env)
		local ok, err = pcall(f, "GuildRanks", self.ns)
		if not ok then world:Error(self.name .. " load " .. file, err) end
	end
	self:Fire("ADDON_LOADED", "GuildRanks")
	self:Fire("PLAYER_LOGIN")
	self:Fire("PLAYER_ENTERING_WORLD", not opts.reload, opts.reload and true or false)
	self:Fire("GUILD_ROSTER_UPDATE")
	if opts.settle ~= false then world:Advance(opts.settle or 5) end
	return self
end

function Client:Logout()
	self:Fire("PLAYER_LOGOUT")
	self.saved = DeepCopy(self.env.GuildRanksDB)
	self.online = false
	if self.guild then self.world.guilds[self.guild].members[self.key].online = false end
	-- this session's timers stop (they belong to the old session)
	return self
end

function Client:Fire(event, ...)
	if not self.online then return end
	for _, f in ipairs(self.frames) do
		local e = rawget(f, "_events")
		local h = rawget(f, "_s_OnEvent")
		if e and e[event] and h then
			local ok, err = pcall(h, f, event, ...)
			if not ok then self.world:Error(self.name .. " " .. event, err) end
		end
	end
end

-- Die; with noEvent the game's PLAYER_DEAD event never arrives (seen on some clients)
function Client:Die(noEvent)
	self.dead = true
	if not noEvent then self:Fire("PLAYER_DEAD") end
end

function Client:Revive()
	self.dead = false
	self:Fire("PLAYER_ALIVE")
end

function Client:Slash(cmd)
	local ok, err = pcall(self.env.SlashCmdList.GUILDRANKS, cmd)
	if not ok then self.world:Error(self.name .. " /granks " .. cmd, err) end
end

-- Convenience actions --------------------------------------------------------
function Client:GainMoney(amount)
	self.money = self.money + amount
	self:Fire("PLAYER_MONEY")
end

function Client:GainXP(amount)
	self.xp = self.xp + amount
	while self.xp >= self.xpMax do
		self.xp = self.xp - self.xpMax
		self.level = self.level + 1
	end
	self:Fire("PLAYER_XP_UPDATE", "player")
end

function Client:Today()
	return self.ns.GetPlayer(self.ns.G(), self.ns.me).days[self.ns.Today()] or {}
end

function Client:G() return self.ns.G() end

-- Spend time playing (play time ticks every 5 s)
function Client:Play(seconds) self.world:Advance(seconds) end

-- Mark the start of a test step in logs
function W:Errors() return self.errors end

return W
