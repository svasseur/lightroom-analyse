local LrPrefs = import "LrPrefs"

local Defaults = require "Defaults"

-- Initialise les préférences manquantes avec les valeurs par défaut.
local prefs = LrPrefs.prefsForPlugin()
for key, value in pairs(Defaults) do
	if prefs[key] == nil then
		prefs[key] = value
	end
end
