local LrDialogs = import "LrDialogs"
local LrPrefs = import "LrPrefs"
local LrTasks = import "LrTasks"

local OllamaClient = require "OllamaClient"

LrTasks.startAsyncTask(function()
	local ok, msg = OllamaClient.checkConnection(LrPrefs.prefsForPlugin())
	LrDialogs.message("Ollama Tagger", msg, ok and "info" or "critical")
end)
