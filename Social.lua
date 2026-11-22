-- Guild Ranks: who has which profession (shared by each member's addon) and member activity
-- (last seen from the guild roster, play time this week from Guild Ranks).
local ADDON, ns = ...
local L = ns.L
local S = {}
ns.Social = S

---------------------------------------------------------------------------
-- Professions
---------------------------------------------------------------------------
local function Clean(s) return (tostring(s or ""):gsub("[;,:|]", "")) end

-- Our professions: { { id, name, skill, max }, ... }
function S.MyProfessions()
	if not GetProfessions or not GetProfessionInfo then return nil end
	local list = {}
	local idx = { GetProfessions() }
	for i = 1, 6 do
		local index = idx[i]
		if index then
			local name, _, skill, max, _, _, skillLine = GetProfessionInfo(index)
			if type(name) == "string" and name ~= "" and ns.Readable(skill) then
				list[#list + 1] = { id = tonumber(skillLine) or 0, name = name, skill = tonumber(skill) or 0, max = tonumber(max) or 0 }
			end
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

local function Encode(list)
	local out = {}
	for _, pr in ipairs(list) do out[#out + 1] = string.format("%d:%d:%d:%s", pr.id, pr.skill, pr.max, Clean(pr.name)) end
	return table.concat(out, ",")
end

local function Decode(s)
	local list = {}
	for item in tostring(s or ""):gmatch("[^,]+") do
		local id, skill, max, name = item:match("^(%d+):(%d+):(%d+):(.+)$")
		if id and #list < 8 then
			list[#list + 1] = { id = tonumber(id), skill = tonumber(skill), max = tonumber(max), name = name:sub(1, 40) }
		end
	end
	return list
end
S.Decode = Decode

local lastSent
-- "P;proto;id:skill:max:name,..."
local function QueueMine(force)
	if not ns.db or not ns.db.share then return end
	local list = S.MyProfessions()
	if not list then return end
	local g = ns.G()
	if g then ns.GetPlayer(g, ns.me, true).profs = list end
	local encoded = Encode(list)
	if not force and encoded == lastSent then return end
	lastSent = encoded
	ns.Comm.Enqueue("P", string.format("P;%d;%s", ns.PROTO, encoded))
end
S.QueueProfessions = QueueMine
table.insert(ns.Comm.extraSenders, function() QueueMine(true) end)

ns.Comm.handlers.P = function(g, sender, parts)
	local p = ns.GetPlayer(g, sender, true)
	p.profs = Decode(parts[3])
	ns.MarkChanged()
end

-- Skill went up or a profession was learned or dropped
ns.On("SKILL_LINES_CHANGED", function()
	if not ns.me then return end
	C_Timer.After(5, function() QueueMine(false) end)
end)

-- Directory: { { name = "Alchemy", members = { { key, name, class, skill, max }, ... } }, ... }
function S.Directory(g)
	local byName = {}
	for key, p in pairs(ns.EligiblePlayers(g)) do
		for _, pr in ipairs(p.profs or {}) do
			local list = byName[pr.name]
			if not list then list = {}; byName[pr.name] = list end
			list[#list + 1] = { key = key, name = ns.ShortName(key), class = p.class, skill = pr.skill or 0, max = pr.max or 0 }
		end
	end
	local out = {}
	for name, members in pairs(byName) do
		table.sort(members, function(a, b)
			if a.skill ~= b.skill then return a.skill > b.skill end
			return a.name < b.name
		end)
		out[#out + 1] = { name = name, members = members }
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

---------------------------------------------------------------------------
-- Activity
---------------------------------------------------------------------------
-- "online", "today", "yesterday", "3 days ago"
function S.LastSeenText(info)
	if not info then return "-" end
	if info.online then return "|cff40ff40" .. L["online"] .. "|r" end
	local days = info.lastDays
	if not days then return "-" end
	if days < 1 then return L["today"] end
	if days < 2 then return L["yesterday"] end
	return string.format(L["%d days ago"], math.floor(days))
end

function S.InactiveDays(g) return (g and g.rules and g.rules.inactiveDays) or 14 end

function S.IsInactive(g, info)
	return info ~= nil and not info.online and info.lastDays ~= nil and info.lastDays >= S.InactiveDays(g)
end

-- Rows for the Activity view: everyone in the roster, online first, then most recently seen
function S.ActivityRows(g)
	local rows = {}
	for key, info in pairs(ns.roster) do
		local p = g.players[key]
		local week = p and ns.Aggregate(p, "week", g) or nil
		rows[#rows + 1] = {
			key = key, name = ns.ShortName(key), class = info.class, level = info.level, info = info,
			week = week and week.playtime or nil, version = p and p.version or nil, hidden = g.hidden[key],
		}
	end
	table.sort(rows, function(a, b)
		local ao, bo = a.info.online and 1 or 0, b.info.online and 1 or 0
		if ao ~= bo then return ao > bo end
		local ad, bd = a.info.lastDays or 9999, b.info.lastDays or 9999
		if ad ~= bd then return ad < bd end
		return a.name < b.name
	end)
	return rows
end
