local LrApplication = import "LrApplication"
local LrDialogs = import "LrDialogs"
local LrFunctionContext = import "LrFunctionContext"
local LrLogger = import "LrLogger"
local LrPrefs = import "LrPrefs"
local LrProgressScope = import "LrProgressScope"
local LrTasks = import "LrTasks"

local OllamaClient = require "OllamaClient"

local logger = LrLogger("OllamaTagger")
logger:enable("logfile") -- ~/Documents/LrClassicLogs/OllamaTagger.log

-- Récupère un JPEG de l'aperçu de la photo. Lightroom utilise le meilleur
-- aperçu disponible : si l'original est hors ligne, c'est l'aperçu dynamique
-- (smart preview) qui est rendu.
local function getPreviewJpeg(photo, size, timeoutSec)
	local result, err
	local done = false
	local handle = photo:requestJpegThumbnail(size, size, function(jpeg, reason)
		if done then return end
		done = true
		result, err = jpeg, reason
	end)

	local waited = 0
	while not done and waited < timeoutSec do
		LrTasks.sleep(0.1)
		waited = waited + 0.1
	end
	handle = nil -- la référence devait rester vivante jusqu'au callback

	if not done then
		return nil, "délai dépassé pour la génération de l'aperçu"
	end
	if not result then
		return nil, "aperçu indisponible (" .. tostring(err) .. ")"
	end
	return result
end

local function hasSmartPreview(photo)
	local ok, info = pcall(photo.getRawMetadata, photo, "smartPreviewInfo")
	return ok and info ~= nil and info.smartPreviewPath ~= nil
end

local function hasKeyword(photo, keyword)
	if not keyword then return false end
	for _, kw in ipairs(photo:getRawMetadata("keywords") or {}) do
		if kw.localIdentifier == keyword.localIdentifier then
			return true
		end
	end
	return false
end

-- Crée (ou récupère) le mot-clé parent et le mot-clé marqueur.
local function prepareKeywords(catalog, prefs)
	local parent, marker
	catalog:withWriteAccessDo("Ollama Tagger : préparation des mots-clés", function()
		if prefs.parentKeyword and prefs.parentKeyword:match("%S") then
			parent = catalog:createKeyword(prefs.parentKeyword, {}, false, nil, true)
		end
		if prefs.markerKeyword and prefs.markerKeyword:match("%S") then
			marker = catalog:createKeyword(prefs.markerKeyword, {}, false, nil, true)
		end
	end, { timeout = 30 })
	return parent, marker
end

local function applyTags(catalog, photo, tags, parent, marker)
	catalog:withWriteAccessDo("Ollama Tagger : ajout des mots-clés", function()
		for _, tag in ipairs(tags) do
			local kw = catalog:createKeyword(tag, {}, true, parent, true)
			if kw then
				photo:addKeyword(kw)
			end
		end
		if marker then
			photo:addKeyword(marker)
		end
	end, { timeout = 30 })
end

LrFunctionContext.postAsyncTaskWithContext("OllamaTagger", function(context)
	LrDialogs.attachErrorDialogToFunctionContext(context)

	local prefs = LrPrefs.prefsForPlugin()
	local catalog = LrApplication.activeCatalog()
	local photos = catalog:getTargetPhotos()

	if #photos == 0 then
		LrDialogs.message("Ollama Tagger", "Aucune photo sélectionnée.", "info")
		return
	end

	local ok, msg = OllamaClient.checkConnection(prefs)
	if not ok then
		LrDialogs.message("Ollama Tagger", msg, "critical")
		return
	end

	local parent, marker = prepareKeywords(catalog, prefs)

	local progress = LrProgressScope {
		title = "Analyse IA (" .. prefs.model .. ")",
		functionContext = context,
	}
	progress:setCancelable(true)

	local stats = { tagged = 0, skipped = 0, failed = 0, errors = {} }
	local previewSize = tonumber(prefs.previewSize) or 1024
	local timeout = tonumber(prefs.timeout) or 180

	for i, photo in ipairs(photos) do
		if progress:isCanceled() then break end

		local name = photo:getFormattedMetadata("fileName")
		progress:setCaption(string.format("%s (%d/%d)", name, i, #photos))
		progress:setPortionComplete(i - 1, #photos)

		if prefs.skipAnalyzed and hasKeyword(photo, marker) then
			stats.skipped = stats.skipped + 1
		elseif prefs.smartPreviewOnly and not hasSmartPreview(photo) then
			stats.skipped = stats.skipped + 1
		else
			local jpeg, err = getPreviewJpeg(photo, previewSize, 60)
			local tags
			if jpeg then
				tags, err = OllamaClient.analyze(jpeg, prefs)
			end

			if tags and #tags > 0 then
				applyTags(catalog, photo, tags, parent, marker)
				stats.tagged = stats.tagged + 1
				logger:info(name .. " : " .. table.concat(tags, ", "))
			else
				err = err or "aucun mot-clé renvoyé"
				stats.failed = stats.failed + 1
				stats.errors[#stats.errors + 1] = name .. " : " .. err
				logger:warn(name .. " : " .. err)
			end
		end
	end

	local canceled = progress:isCanceled()
	progress:done()

	local summary = string.format(
		"%d photo(s) taguée(s)\n%d ignorée(s)\n%d en erreur",
		stats.tagged, stats.skipped, stats.failed)
	if canceled then
		summary = "Analyse interrompue.\n\n" .. summary
	end
	if #stats.errors > 0 then
		local shown = {}
		for j = 1, math.min(#stats.errors, 10) do
			shown[j] = stats.errors[j]
		end
		summary = summary .. "\n\nErreurs :\n" .. table.concat(shown, "\n")
	end
	LrDialogs.message("Ollama Tagger", summary, stats.failed > 0 and "warning" or "info")
end)
