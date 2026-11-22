-- Guild Ranks: 1v1 challenges. Challenge an online guildmate to a 30 or 60 minute race in gold,
-- XP or kills. Each side counts its own progress and sends it every 20 seconds.
--   V;proto;req;id;target;metric;secs   challenge
--   V;proto;ans;id;yes|no               answer (from the target)
--   V;proto;val;id;value                progress (both sides; also the final value)
--   V;proto;quit;id                     gave up
local ADDON, ns = ...
local L = ns.L
local V = {}
ns.Versus = V

V.METRICS = { gold = L["Gold"], xp = L["XP"], kills = L["Kills"] }
V.DURATIONS = { 1800, 3600 }
local SEND_EVERY, GRACE, ANSWER_TIME = 20, 15, 60

local race      -- the running (or just finished) challenge
local incoming  -- a challenge waiting for our answer
local outgoing  -- our challenge waiting for an answer

local function Send(key, msg) ns.Comm.Enqueue(key, msg) end

local function NewId() return string.format("%x%02x", GetServerTime(), math.random(0, 255)) end

function V.Format(metric, v, plain)
	v = v or 0
	if metric == "gold" then return ns.FormatMoney(v, plain) end
	return ns.FormatNumber(math.floor(v))
end

local function MetricLabel(metric) return V.METRICS[metric] or metric end
local function DurationText(secs) return secs >= 3600 and L["1-hour"] or string.format(L["%d-minute"], math.floor(secs / 60)) end

-- Count our own progress
table.insert(ns.addHooks, function(field, amount)
	if not race or race.done or not race.started then return end
	local m = race.metric
	local counts = false
	if m == "gold" then
		local src = field:match("^g_(.+)$")
		local g = ns.G()
		counts = src ~= nil and g ~= nil and g.rules.gold[src] == true
	elseif m == "xp" then
		counts = field == "xp"
	elseif m == "kills" then
		counts = field == "kills"
	end
	if counts and amount > 0 then
		race.mine = race.mine + amount
		if ns.UI and ns.UI.RefreshVersus then ns.UI.RefreshVersus() end
	end
end)

local function Start(r)
	r.started, r.startedAt = true, GetTime()
	r.mine, r.theirs = 0, 0
	r.lastHeard = GetTime()
	race = r
	if ns.UI and ns.UI.ShowVersus then ns.UI.ShowVersus() end
	ns.Print(string.format(L["%s race against %s started: %s."], DurationText(r.secs), r.opponent, MetricLabel(r.metric)))
end

local function Finish(reason)
	if not race or race.done then return end
	race.done = true
	race.reason = reason
	local won = race.mine > race.theirs
	local draw = race.mine == race.theirs
	if reason == "quit" then won, draw = true, false end
	if reason == "gaveup" then won, draw = false, false end
	race.won, race.draw = won, draw
	if ns.Alerts and ns.Alerts.QueueCard then
		local title = draw and L["It's a draw!"] or (won and L["You won the race!"] or string.format(L["%s won the race"], race.opponent))
		local sub = string.format("%s %s  ·  %s %s", L["You"], V.Format(race.metric, race.mine), race.opponent, V.Format(race.metric, race.theirs))
		if reason == "quit" then sub = string.format(L["%s gave up"], race.opponent) end
		ns.Alerts.QueueCard({ won = won, kicker = string.format(L["1v1 %s race"], MetricLabel(race.metric):lower()), title = title, sub = sub })
	end
	if ns.UI and ns.UI.ShowVersus then ns.UI.ShowVersus() end
end

-- Every second while racing: send progress, end on time
C_Timer.NewTicker(1, function()
	if incoming and GetTime() - incoming.at > ANSWER_TIME then
		incoming = nil
		if ns.UI and ns.UI.HideVersusInvite then ns.UI.HideVersusInvite() end
	end
	if outgoing and GetTime() - outgoing.at > ANSWER_TIME + 10 then
		ns.Print(string.format(L["%s didn't answer your challenge."], outgoing.opponent))
		outgoing = nil
	end
	if not race or race.done or not race.started then return end
	local elapsed = GetTime() - race.startedAt
	if not race.lastSent or GetTime() - race.lastSent >= SEND_EVERY then
		race.lastSent = GetTime()
		Send("Vval" .. race.id, string.format("V;%d;val;%s;%d", ns.PROTO, race.id, math.floor(race.mine)))
	end
	if elapsed >= race.secs and not race.timeUp then
		race.timeUp = GetTime()
		Send("Vval" .. race.id, string.format("V;%d;val;%s;%d", ns.PROTO, race.id, math.floor(race.mine)))
	end
	if race.timeUp and GetTime() - race.timeUp >= GRACE then Finish("time") end
	if ns.UI and ns.UI.RefreshVersus then ns.UI.RefreshVersus() end
end)

-- Can we challenge this guildmate? (online, has the addon, not us)
function V.CanChallenge(key)
	local g = ns.G()
	if not g or g.solo or not key or ns.IsMyCharacter(key) then return false end
	if race and not race.done then return false end
	local p = g.players[key]
	return p ~= nil and p.version ~= nil and ns.UI and ns.UI.IsOnline(g, key) == true
end

-- Online guildmates with the addon
function V.Opponents()
	local g, out = ns.G(), {}
	if not g then return out end
	for key in pairs(g.players) do if V.CanChallenge(key) then out[#out + 1] = key end end
	table.sort(out)
	return out
end

function V.Challenge(key, metric, secs)
	if not V.CanChallenge(key) or not V.METRICS[metric] then return false end
	secs = (secs == 1800) and 1800 or 3600
	local id = NewId()
	outgoing = { id = id, opponent = key, metric = metric, secs = secs, at = GetTime() }
	Send("Vreq", string.format("V;%d;req;%s;%s;%s;%d", ns.PROTO, id, key, metric, secs))
	ns.Print(string.format(L["Challenge sent to %s. Waiting for an answer..."], key))
	return true
end

function V.Answer(yes)
	local inc = incoming
	if not inc then return false end
	incoming = nil
	if ns.UI and ns.UI.HideVersusInvite then ns.UI.HideVersusInvite() end
	Send("Vans" .. inc.id, string.format("V;%d;ans;%s;%s", ns.PROTO, inc.id, yes and "yes" or "no"))
	if yes then Start({ id = inc.id, opponent = inc.opponent, metric = inc.metric, secs = inc.secs }) end
	return true
end

function V.GiveUp()
	if not race or race.done then return end
	Send("Vquit" .. race.id, string.format("V;%d;quit;%s", ns.PROTO, race.id))
	Finish("gaveup")
end

function V.Close() if race and race.done then race = nil end end

function V.PostResult()
	if not race or not race.done or not race.won then return false end
	if not (ns.Alerts.CanChat and ns.Alerts.CanChat()) then return false end
	local msg
	if race.reason == "quit" then
		msg = string.format(L["I won a %s %s race against %s (they gave up)"], DurationText(race.secs), MetricLabel(race.metric):lower(), race.opponent)
	else
		msg = string.format(L["I won a %s %s race against %s: %s vs %s"], DurationText(race.secs), MetricLabel(race.metric):lower(),
			race.opponent, V.Format(race.metric, race.mine, true), V.Format(race.metric, race.theirs, true))
	end
	ns.Alerts.GuildChat(msg .. " (Guild Ranks)")
	race.posted = true
	return true
end

function V.Current() return race end
function V.Incoming() return incoming end

ns.Comm.handlers.V = function(g, sender, parts)
	local sub, id = parts[3], parts[4]
	if not sub or not id then return end
	if sub == "req" then
		local target, metric, secs = ns.CanonName(parts[5]), parts[6], tonumber(parts[7])
		if target ~= ns.me or not V.METRICS[metric] or not secs then return end
		if race and not race.done then
			Send("Vans" .. id, string.format("V;%d;ans;%s;no", ns.PROTO, id)) -- busy
			return
		end
		incoming = { id = id, opponent = sender, metric = metric, secs = (secs == 1800) and 1800 or 3600, at = GetTime() }
		if ns.UI and ns.UI.ShowVersusInvite then ns.UI.ShowVersusInvite(incoming) end
		ns.Print(string.format(L["%s challenges you to a %s %s race! Accept or decline in the popup."], sender, DurationText(incoming.secs), MetricLabel(metric):lower()))
	elseif sub == "ans" then
		if not outgoing or outgoing.id ~= id or outgoing.opponent ~= sender then return end
		local out = outgoing
		outgoing = nil
		if parts[5] == "yes" then
			Start({ id = out.id, opponent = out.opponent, metric = out.metric, secs = out.secs })
		else
			ns.Print(string.format(L["%s declined your challenge."], sender))
		end
	elseif sub == "val" then
		if not race or race.id ~= id or race.opponent ~= sender then return end
		local v = tonumber(parts[5])
		if v and v >= 0 then race.theirs = v; race.lastHeard = GetTime() end
		if ns.UI and ns.UI.RefreshVersus then ns.UI.RefreshVersus() end
	elseif sub == "quit" then
		if race and race.id == id and race.opponent == sender then Finish("quit") end
	end
end
