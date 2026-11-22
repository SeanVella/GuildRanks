-- Guild Ranks: which guild you're in, the guild roster, and who may change rules
local ADDON, ns = ...
local L = ns.L

ns.roster = {}          -- "Name-Realm" -> { level, class, rankIndex, rankName, online }
ns.rosterReady = false  -- some roster data has loaded
ns.rosterComplete = false -- Blizzard returned every member with readable data
ns.rosterCount = 0
local pendingAdds = {}  -- stats recorded before the guild is known (right after login)

---------------------------------------------------------------------------
-- Guild detection
---------------------------------------------------------------------------
local function NormalizeRealm(realm)
	if not realm or realm == "" then return ns.MyRealm() end
	return (realm:gsub("[%s%-]", ""))
end

local function GuildClubId()
	if not (C_Club and C_Club.GetGuildClubId) then return nil end
	local ok, id = pcall(C_Club.GetGuildClubId)
	if ok and id and ns.Readable(id) then return tostring(id) end
	return nil
end

-- Returns true once the current guild (or "no guild") is known
function ns.ResolveGuild()
	if not ns.me or not ns.db then return false end
	local key, name, realm, clubId, solo
	if IsInGuild() then
		local gname, _, _, grealm = GetGuildInfo("player")
		if not gname or gname == "" or not ns.Readable(gname) then return false end -- not loaded yet
		realm = NormalizeRealm(grealm)
		name = gname
		key = gname -- not the realm: on WoW: Forever it changes between sessions
		clubId = GuildClubId()
	else
		realm = ns.MyRealm()
		name = L["No guild"]
		key = "~solo"
		solo = true
	end

	local g = ns.db.guilds[key]
	if g and clubId and g.clubId and g.clubId ~= clubId then
		-- A different guild with the same name and realm: keep the old data separately
		ns.db.guilds[key .. " (" .. date("%Y-%m-%d") .. ")"] = g
		g.name = g.name .. " (" .. L["old"] .. ")"
		g = nil
	end
	if not g then
		g = ns.NewGuild(name, realm, clubId, solo)
		ns.db.guilds[key] = g
	end
	g.clubId = g.clubId or clubId

	local p = ns.GetPlayer(g, ns.me, true)
	p.class = select(2, UnitClass("player"))
	p.level = UnitLevel("player")
	p.version = ns.VERSION
	p.seen = time()

	local changed = ns.gkey ~= key
	ns.gkey = key
	ns.db.chars[ns.me].guild = key
	if changed then
		ns.roster, ns.rosterReady, ns.rosterComplete, ns.rosterCount = {}, false, false, 0
		for _, add in ipairs(pendingAdds) do ns.Add(add[1], add[2]) end
		pendingAdds = {}
		ns.RequestRoster()
		ns.FireGuildChanged()
		ns.MarkChanged()
	end
	return true
end

-- Called by the tracker while the guild is still unknown
function ns.QueueAdd(field, amount)
	if #pendingAdds < 500 then pendingAdds[#pendingAdds + 1] = { field, amount } end
end

ns.OnLogin(function()
	-- The guild name can take a few seconds to load after login
	local tries = 0
	local function try()
		if ns.ResolveGuild() then return end
		tries = tries + 1
		if tries < 30 then C_Timer.After(2, try) end
	end
	try()
end)

ns.On("PLAYER_GUILD_UPDATE", function(unit)
	if unit == nil or unit == "player" then C_Timer.After(1, ns.ResolveGuild) end
end)

---------------------------------------------------------------------------
-- Roster
---------------------------------------------------------------------------
function ns.RequestRoster()
	if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
end

local rosterPending = false
local function ReadRoster()
	rosterPending = false
	if not IsInGuild() then return end
	local total = GetNumGuildMembers() or 0
	local roster, count, myName, clashes = {}, 0, nil, {}
	for i = 1, total do
		local name, rankName, rankIndex, level, _, _, _, _, online, _, classFile, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		if name and ns.Readable(name) then
			name = ns.CanonName(name)
			-- your own entry tells us the name guildmates see for you ("Healya Jamie")
			if ns.myGUID and guid and ns.Readable(guid) and guid == ns.myGUID then myName = name end
			if roster[name] then clashes[name] = true end -- two members with the same name
			roster[name] = {
				rankName = ns.Readable(rankName) and rankName or nil,
				rankIndex = ns.Readable(rankIndex) and rankIndex or nil,
				level = ns.Readable(level) and level or nil,
				class = ns.Readable(classFile) and classFile or nil,
				online = ns.Readable(online) and online or false,
				lastDays = (function()
					if online or not GetGuildRosterLastOnline then return online and 0 or nil end
					local ok, y, m, d, h = pcall(GetGuildRosterLastOnline, i)
					if not ok or not (ns.Readable(y) and ns.Readable(d)) then return nil end
					return (y or 0) * 365 + (m or 0) * 30 + (d or 0) + (h or 0) / 24
				end)(),
			}
			count = count + 1
		end
	end
	if count > 0 then
		ns.roster, ns.rosterCount, ns.rosterReady = roster, count, true
		ns.nameClashes = clashes
		if myName and myName ~= ns.me then ns.RenameMe(myName) end
		-- Blizzard sometimes returns a partial or partly hidden roster; don't let
		-- that hide members from the leaderboard
		ns.rosterComplete = (count == total)
		if ns.Comm and ns.Comm.ProcessPending then ns.Comm.ProcessPending() end
		ns.MarkChanged()
	end
end
ns.ReadRoster = ReadRoster

ns.On("GUILD_ROSTER_UPDATE", function()
	if rosterPending then return end
	rosterPending = true
	C_Timer.After(2, function() ns.ReadRoster() end)
	if not ns.gkey or (ns.G() and ns.G().solo and IsInGuild()) then ns.ResolveGuild() end
end)

ns.OnLogin(function()
	C_Timer.NewTicker(120, ns.RequestRoster)
end)

-- Members of your current guild who don't have the addon (or haven't shared yet)
function ns.MembersWithoutAddon()
	local g = ns.G()
	local list = {}
	if not g or g.solo then return list end
	for name, info in pairs(ns.roster) do
		if not g.players[name] then list[#list + 1] = { key = name, name = ns.ShortName(name), level = info.level or 0, class = info.class } end
	end
	table.sort(list, function(a, b)
		if a.level == b.level then return a.name < b.name end
		return a.level > b.level
	end)
	return list
end

---------------------------------------------------------------------------
-- Permissions
---------------------------------------------------------------------------
function ns.MyRankIndex()
	if not IsInGuild() then return nil end
	local _, _, rankIndex = GetGuildInfo("player")
	if not ns.Readable(rankIndex) then return nil end
	return rankIndex
end

function ns.IsGuildMaster()
	return ns.MyRankIndex() == 0
end

-- May I change the rules of guild g? (only your current guild; solo = always)
function ns.CanEditRules(g)
	g = g or ns.G()
	if not g then return false end
	if g.solo then return true end
	if g ~= ns.G() then return false end
	local r = ns.MyRankIndex()
	return r ~= nil and r <= (g.rules.managerRank or 1)
end

function ns.RankOfMember(key)
	local info = ns.roster[key]
	return info and info.rankIndex
end

-- Guild rank names for the "who can change rules" setting
function ns.RankChoices()
	local list, seen = {}, {}
	for _, info in pairs(ns.roster) do
		if info.rankIndex and not seen[info.rankIndex] then
			seen[info.rankIndex] = true
			list[#list + 1] = { value = info.rankIndex, text = info.rankName or (L["Rank"] .. " " .. info.rankIndex) }
		end
	end
	if not seen[0] then list[#list + 1] = { value = 0, text = L["Guild Master"] } end
	if not seen[1] then list[#list + 1] = { value = 1, text = L["Rank"] .. " 1" } end
	table.sort(list, function(a, b) return a.value < b.value end)
	for _, item in ipairs(list) do
		if item.value > 0 then item.text = item.text .. " " .. L["and above"] end
		if item.value == 0 then item.text = L["Guild Master only"] end
	end
	return list
end
