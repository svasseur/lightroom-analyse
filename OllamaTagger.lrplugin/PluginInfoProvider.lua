local LrDialogs = import "LrDialogs"
local LrPrefs = import "LrPrefs"
local LrTasks = import "LrTasks"
local LrView = import "LrView"

local OllamaClient = require "OllamaClient"

local function sectionsForTopOfDialog(f, _)
	local prefs = LrPrefs.prefsForPlugin()
	local bind = LrView.bind
	local labelWidth = LrView.share("label_width")

	local function row(label, control)
		return f:row {
			f:static_text { title = label, alignment = "right", width = labelWidth },
			control,
		}
	end

	return {
		{
			title = "Ollama",
			bind_to_object = prefs,

			row("URL du serveur :", f:edit_field { value = bind "ollamaUrl", width_in_chars = 30 }),
			row("Modèle :", f:edit_field { value = bind "model", width_in_chars = 30 }),
			row("Délai max / photo (s) :", f:edit_field {
				value = bind "timeout", width_in_digits = 5, min = 10, max = 3600, precision = 0,
			}),
			f:row {
				f:static_text { title = "", width = labelWidth },
				f:push_button {
					title = "Tester la connexion",
					action = function()
						LrTasks.startAsyncTask(function()
							local ok, msg = OllamaClient.checkConnection(prefs)
							LrDialogs.message("Ollama Tagger", msg, ok and "info" or "critical")
						end)
					end,
				},
			},
		},
		{
			title = "Analyse",
			bind_to_object = prefs,

			row("Langue des mots-clés :", f:popup_menu {
				value = bind "language",
				items = { { title = "Français", value = "fr" }, { title = "English", value = "en" } },
			}),
			row("Nombre max de mots-clés :", f:edit_field {
				value = bind "maxTags", width_in_digits = 3, min = 1, max = 50, precision = 0,
			}),
			row("Taille de l'aperçu (px) :", f:popup_menu {
				value = bind "previewSize",
				items = {
					{ title = "512 (rapide)", value = 512 },
					{ title = "768", value = 768 },
					{ title = "1024 (recommandé)", value = 1024 },
					{ title = "1536 (précis, lent)", value = 1536 },
				},
			}),
			row("Mot-clé parent :", f:edit_field {
				value = bind "parentKeyword", width_in_chars = 20,
				tooltip = "Les mots-clés IA sont rangés sous ce mot-clé. Laisser vide pour la racine.",
			}),
			row("Mot-clé marqueur :", f:edit_field {
				value = bind "markerKeyword", width_in_chars = 20,
				tooltip = "Ajouté aux photos analysées. Laisser vide pour désactiver.",
			}),
			f:row {
				f:static_text { title = "", width = labelWidth },
				f:checkbox { title = "Ignorer les photos portant déjà le mot-clé marqueur", value = bind "skipAnalyzed" },
			},
			f:row {
				f:static_text { title = "", width = labelWidth },
				f:checkbox { title = "Ne traiter que les photos ayant un aperçu dynamique", value = bind "smartPreviewOnly" },
			},
			row("Prompt personnalisé :", f:edit_field {
				value = bind "customPrompt", width_in_chars = 50, height_in_lines = 6,
				tooltip = "Laisser vide pour le prompt par défaut. %d = nombre max de mots-clés. " ..
					"Le modèle doit répondre en JSON {\"tags\": [...]}.",
			}),
		},
	}
end

return {
	sectionsForTopOfDialog = sectionsForTopOfDialog,
}
