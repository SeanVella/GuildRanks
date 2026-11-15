-- Guild Ranks: translations.
-- English text is the key, so a missing translation simply shows the English text.
-- To add a language, create Locales/<locale>.lua (for example deDE.lua), add it to
-- GuildRanks.toc after this file, and fill in entries like:
--   if GetLocale() ~= "deDE" then return end
--   local L = select(2, ...).L
--   L["This week"] = "Diese Woche"
local ADDON, ns = ...

ns.L = setmetatable({}, {
	__index = function(t, key)
		t[key] = key
		return key
	end,
})
