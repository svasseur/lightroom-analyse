--[[
  Ollama Tagger - Plug-in Lightroom Classic
  Analyse les aperçus (aperçus dynamiques / smart previews inclus) avec un
  modèle de vision local servi par Ollama et ajoute des mots-clés.
]]

return {
	LrSdkVersion = 10.0,
	LrSdkMinimumVersion = 6.0,

	LrToolkitIdentifier = "com.github.svasseur.ollamatagger",
	LrPluginName = "Ollama Tagger",
	LrPluginInfoUrl = "https://github.com/svasseur/lightroom-analyse",

	LrPluginInfoProvider = "PluginInfoProvider.lua",
	LrInitPlugin = "Init.lua",

	LrLibraryMenuItems = {
		{
			title = "Analyser la sélection avec Ollama…",
			file = "AnalyzeMenuItem.lua",
			enabledWhen = "photosSelected",
		},
	},

	LrExportMenuItems = {
		{
			title = "Analyser la sélection avec Ollama…",
			file = "AnalyzeMenuItem.lua",
			enabledWhen = "photosSelected",
		},
	},

	VERSION = { major = 1, minor = 1, revision = 1 },
}
