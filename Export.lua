-- Guild Ranks: export for optional automatic Discord posting (see docs/discord-automation.md).
-- On logout / reload the guild data is written into SavedVariables as a JSON
-- string (GuildRanksDB.exportJSON), which the uploader and bot read.
local ADDON, ns = ...

local function EscapeString(s)
	return (s:gsub('[%c"\\]', function(c)
		if c == '"' then return '\\"' end
		if c == "\\" then return "\\\\" end
		return string.format("\\u%04x", c:byte())
	end))
end

local function Encode(v)
	local t = type(v)
	if t == "nil" then return "null" end
	if t == "boolean" then return v and "true" or "false" end
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return "0" end
		if v == math.floor(v) then return string.format("%.0f", v) end
		return string.format("%.4f", v)
	end
	if t == "string" then return '"' .. EscapeString(v) .. '"' end
	if t == "table" then
		local out = {}
		if v[1] ~= nil then
			for i = 1, #v do out[i] = Encode(v[i]) end
			return "[" .. table.concat(out, ",") .. "]"
		end
		for k, val in pairs(v) do
			out[#out + 1] = '"' .. EscapeString(tostring(k)) .. '":' .. Encode(val)
		end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end
ns.JSONEncode = Encode

function ns.BuildExport()
	if not ns.db then return end
	local out = {
		addon = "GuildRanks",
		version = ns.VERSION,
		generatedAt = GetServerTime(),
		exportedBy = ns.me,
		today = ns.Today(),
		guilds = {},
	}
	-- One entry per guild (not "no guild"): daily buckets for the last 15 days
	-- (covers this week and last week), plus all-time totals
	local oldest = ns.ShiftDay(ns.Today(), -15)
	for gkey, g in pairs(ns.db.guilds) do
		if not g.solo and not g.demo then
			local r = g.rules
			local excluded = {}
			for name in pairs(r.excluded) do excluded[#excluded + 1] = name end
			local entry = {
				key = gkey, name = g.name, realm = g.realm,
				rules = {
					version = r.version, resetDay = r.resetDay, resetHour = r.resetHour or 0, minMinutes = r.minMinutes, gold = r.gold,
					managerRank = r.managerRank, showSpoon = r.showSpoon, itemValue = r.itemValue,
					excluded = excluded, by = r.by, challengeMetric = r.challengeMetric, challengePrize = r.challengePrize,
					goalMetric = r.goalMetric, goalTarget = r.goalTarget,
				},
				players = {},
			}
			for key, p in pairs(g.players) do
				if not g.hidden[key] then
					local days = {}
					for day, b in pairs(p.days or {}) do
						if day >= oldest then days[day] = b end
					end
					entry.players[#entry.players + 1] = {
						key = key, name = ns.ShortName(key), class = p.class, level = p.level,
						seen = p.seen, version = p.version, days = days, all = p.all or {},
					}
				end
			end
			out.guilds[#out.guilds + 1] = entry
		end
	end
	ns.db.exportJSON = Encode(out)
	ns.db.exportAt = out.generatedAt
end

ns.On("PLAYER_LOGOUT", function()
	local ok, err = pcall(ns.BuildExport)
	if not ok and ns.db then ns.db.exportError = tostring(err) end
end)
