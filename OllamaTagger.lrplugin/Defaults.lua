-- Valeurs par défaut des préférences du plug-in.
return {
	ollamaUrl = "http://localhost:11434",
	model = "qwen2.5vl:7b",
	language = "fr",           -- "fr" ou "en"
	maxTags = 10,
	previewSize = 1024,        -- côté long (px) de l'image envoyée au modèle
	timeout = 180,             -- secondes par photo
	parentKeyword = "IA",      -- vide = mots-clés à la racine
	markerKeyword = "ia-analysé", -- vide = pas de marqueur
	skipAnalyzed = true,       -- ignore les photos portant déjà le marqueur
	smartPreviewOnly = false,  -- ne traite que les photos ayant un aperçu dynamique
	customPrompt = "",         -- vide = prompt par défaut
}
