local LrHttp = import "LrHttp"
local LrStringUtils = import "LrStringUtils"

local JSON = require "JSON"

local OllamaClient = {}

local PROMPTS = {
	fr = [[Tu es un assistant de catalogage pour photographes.
Analyse cette photo et donne au maximum %d mots-clés EN FRANÇAIS qui décrivent :
le sujet principal, les objets et éléments visibles, le type de lieu ou de scène,
la présence de personnes ou d'animaux (sans identifier qui), l'ambiance,
les couleurs dominantes, la saison ou le moment de la journée si c'est évident.
Règles : mots-clés courts (1 à 3 mots), en minuscules, au singulier, sans doublon,
uniquement ce qui est réellement visible.
Réponds uniquement avec du JSON de la forme {"tags": ["mot-clé", "..."]}.]],

	en = [[You are a cataloguing assistant for photographers.
Analyze this photo and return at most %d keywords IN ENGLISH describing:
the main subject, visible objects and elements, the type of place or scene,
people or animals present (without identifying anyone), the mood,
dominant colors, season or time of day if obvious.
Rules: short keywords (1 to 3 words), lowercase, singular, no duplicates,
only what is actually visible.
Reply only with JSON of the form {"tags": ["keyword", "..."]}.]],
}

local function trimSlash(url)
	return (url:gsub("/+$", ""))
end

function OllamaClient.buildPrompt(prefs)
	local maxTags = tonumber(prefs.maxTags) or 10
	if prefs.customPrompt and prefs.customPrompt:match("%S") then
		-- %d dans un prompt personnalisé est remplacé par le nombre max de tags.
		return (prefs.customPrompt:gsub("%%d", tostring(maxTags)))
	end
	return string.format(PROMPTS[prefs.language] or PROMPTS.fr, maxTags)
end

-- Nettoie et déduplique la liste de tags renvoyée par le modèle.
function OllamaClient.normalizeTags(tags, maxTags)
	local result, seen = {}, {}
	for _, tag in ipairs(tags or {}) do
		if type(tag) == "string" then
			tag = tag:gsub("[\r\n\t]", " ")
			tag = tag:gsub("[,;|]", " ")      -- caractères spéciaux pour les mots-clés LR
			tag = tag:gsub("^[%s%-%*%.#\"']+", ""):gsub("[%s%.\"']+$", "")
			tag = tag:gsub("%s+", " ")
			tag = LrStringUtils.lower(tag)
			if #tag > 0 and #tag <= 50 and not seen[tag] then
				seen[tag] = true
				result[#result + 1] = tag
				if #result >= maxTags then
					break
				end
			end
		end
	end
	return result
end

-- Extrait la liste de tags du texte renvoyé par le modèle, même s'il n'a
-- pas parfaitement respecté le format JSON.
function OllamaClient.parseTags(content)
	if type(content) ~= "string" then
		return {}
	end
	local ok, data = pcall(JSON.decode, content)
	if not ok then
		-- Tente d'isoler un objet JSON au milieu d'un texte libre.
		local jsonPart = content:match("%b{}")
		if jsonPart then
			ok, data = pcall(JSON.decode, jsonPart)
		end
	end
	if ok and type(data) == "table" then
		local list = data.tags or data.keywords or data
		if type(list) == "table" then
			return list
		end
	end
	-- Repli : liste séparée par virgules ou retours à la ligne.
	local tags = {}
	for item in content:gmatch("[^,\n]+") do
		tags[#tags + 1] = item
	end
	return tags
end

-- Envoie une image JPEG (données binaires) au modèle et retourne la liste de tags.
-- Retourne nil, message en cas d'erreur.
function OllamaClient.analyze(jpegData, prefs)
	local maxTags = tonumber(prefs.maxTags) or 10

	local body = JSON.encode({
		model = prefs.model,
		stream = false,
		keep_alive = "10m",
		messages = {
			{
				role = "user",
				content = OllamaClient.buildPrompt(prefs),
				images = { LrStringUtils.encodeBase64(jpegData) },
			},
		},
		format = {
			type = "object",
			properties = {
				tags = { type = "array", items = { type = "string" } },
			},
			required = { "tags" },
		},
		options = {
			temperature = 0.2,
		},
	})

	local response, headers = LrHttp.post(
		trimSlash(prefs.ollamaUrl) .. "/api/chat",
		body,
		{ { field = "Content-Type", value = "application/json" } },
		"POST",
		tonumber(prefs.timeout) or 180
	)

	if not response then
		local err = headers and headers.error
		local msg = err and (err.name or err.errorCode) or "pas de réponse"
		return nil, "Impossible de joindre Ollama (" .. tostring(msg) .. ")"
	end

	local status = headers and headers.status
	local ok, data = pcall(JSON.decode, response)
	if not ok or type(data) ~= "table" then
		return nil, string.format("Réponse invalide d'Ollama (HTTP %s) : %s",
			tostring(status), response:sub(1, 200))
	end
	if data.error then
		return nil, "Erreur Ollama : " .. tostring(data.error)
	end

	local content = data.message and data.message.content
	return OllamaClient.normalizeTags(OllamaClient.parseTags(content), maxTags)
end

-- Vérifie que le serveur répond et que le modèle est installé.
function OllamaClient.checkConnection(prefs)
	local response, headers = LrHttp.get(trimSlash(prefs.ollamaUrl) .. "/api/tags", nil, 10)
	if not response then
		return false, "Ollama ne répond pas à l'adresse " .. prefs.ollamaUrl ..
			".\nLancez « ollama serve » ou l'application Ollama."
	end
	local ok, data = pcall(JSON.decode, response)
	if not ok or type(data) ~= "table" or type(data.models) ~= "table" then
		return false, "Réponse inattendue : " .. response:sub(1, 200)
	end
	local names = {}
	for _, m in ipairs(data.models) do
		names[#names + 1] = m.name
		if m.name == prefs.model or m.name == prefs.model .. ":latest" then
			return true, "Connexion OK. Modèle « " .. prefs.model .. " » disponible."
		end
	end
	return false, "Ollama répond mais le modèle « " .. prefs.model .. " » n'est pas installé.\n" ..
		"Exécutez : ollama pull " .. prefs.model .. "\n\nModèles installés :\n" .. table.concat(names, "\n")
end

return OllamaClient
