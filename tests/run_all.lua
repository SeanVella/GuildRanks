-- Guild Ranks test runner. From the repository root:
--   lua5.1 tests/run_all.lua          (or lua5.3 / texlua)
--   lua5.1 tests/run_all.lua sync     (only test files whose name contains "sync")
-- Exit code 0 = all passed.
package.path = "./tests/?.lua;" .. package.path
math.randomseed(1)
local W = require("wow")

local cases = {}
local current

function test(name, fn) cases[#cases + 1] = { name = name, fn = fn, file = current } end

local function fmt(v)
	if type(v) == "string" then return string.format("%q", v) end
	return tostring(v)
end

function eq(actual, expected, what)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", what or "value", fmt(expected), fmt(actual)), 2)
	end
end

function near(actual, expected, tolerance, what)
	if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 0.001) then
		error(string.format("%s: expected ~%s, got %s", what or "value", fmt(expected), fmt(actual)), 2)
	end
end

function ok(cond, what)
	if not cond then error((what or "condition") .. " was false", 2) end
end

function contains(text, part, what)
	if type(text) ~= "string" or not text:find(part, 1, true) then
		error(string.format("%s: %s not found in %s", what or "text", fmt(part), fmt(text)), 2)
	end
end

function absent(text, part, what)
	if type(text) == "string" and text:find(part, 1, true) then
		error(string.format("%s: %s should not appear in %s", what or "text", fmt(part), fmt(text)), 2)
	end
end

-- A world with guild <Froga>: Kurt (GM), Sean (officer), Maria (member)
local caseWorlds = {}
function NewWorld(opts)
	opts = opts or {}
	opts.addonDir = opts.addonDir or "."
	local world = W.New(opts)
	caseWorlds[#caseWorlds + 1] = world
	return world
end

function StandardGuild(world)
	world:AddGuild("Froga", "15554351")
	local kurt = world:NewClient({ name = "Kurt", guild = "Froga", rank = 0, level = 41, class = "WARRIOR" })
	local sean = world:NewClient({ name = "Sean", guild = "Froga", rank = 1, level = 34, class = "MAGE" })
	local maria = world:NewClient({ name = "Maria", guild = "Froga", rank = 3, level = 22, class = "PRIEST" })
	return kurt, sean, maria
end

-- Give a client a day of stats directly (fast way to build history)
function SeedDay(client, day, bucket)
	local ns = client.ns
	local p = ns.GetPlayer(ns.G(), ns.me, true)
	p.days[day] = bucket
	for k, v in pairs(bucket) do p.all[k] = (p.all[k] or 0) + v end
end

local files = { "test_tracking", "test_sync", "test_rules", "test_guild", "test_dates", "test_scoring", "test_features", "test_privacy" }
local filter = arg and arg[1]
for _, f in ipairs(files) do
	if not filter or f:find(filter, 1, true) then
		current = f
		dofile("tests/" .. f .. ".lua")
	end
end

local passed, failed = 0, 0
for _, case in ipairs(cases) do
	caseWorlds = {}
	local okRun, err = pcall(case.fn)
	-- any Lua error inside the addon fails the test too
	for _, world in ipairs(caseWorlds) do
		if okRun and #world.errors > 0 then
			okRun, err = false, "addon error: " .. world.errors[1] .. (#world.errors > 1 and (" (+" .. (#world.errors - 1) .. " more)") or "")
		end
	end
	if okRun then
		passed = passed + 1
		io.write("  ok    " .. case.file .. " > " .. case.name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL  " .. case.file .. " > " .. case.name .. "\n        " .. tostring(err) .. "\n")
	end
end
io.write(string.format("\n%d passed, %d failed (%s)\n", passed, failed, _VERSION))
os.exit(failed == 0 and 0 or 1)
