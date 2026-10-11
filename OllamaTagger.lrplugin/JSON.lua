--[[
  Encodeur / décodeur JSON minimal en Lua pur (le SDK Lightroom n'en fournit pas).
]]

local JSON = {}

local escapes = {
	['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
	['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local function encodeString(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		return escapes[c] or string.format("\\u%04x", c:byte())
	end) .. '"'
end

local function isArray(t)
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" or k <= 0 or k % 1 ~= 0 then
			return false
		end
		n = math.max(n, k)
	end
	return n == #t
end

local encodeValue

local function encodeTable(t)
	local parts = {}
	if next(t) ~= nil and isArray(t) then
		for i = 1, #t do
			parts[i] = encodeValue(t[i])
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	if next(t) == nil and getmetatable(t) == JSON.arrayMt then
		return "[]"
	end
	for k, v in pairs(t) do
		parts[#parts + 1] = encodeString(tostring(k)) .. ":" .. encodeValue(v)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

encodeValue = function(v)
	local tv = type(v)
	if tv == "string" then
		return encodeString(v)
	elseif tv == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			error("JSON: nombre invalide")
		end
		if v % 1 == 0 and v > -1e15 and v < 1e15 then
			return string.format("%d", v)
		end
		return string.format("%.14g", v)
	elseif tv == "boolean" then
		return tostring(v)
	elseif tv == "nil" or v == JSON.null then
		return "null"
	elseif tv == "table" then
		return encodeTable(v)
	end
	error("JSON: type non supporté " .. tv)
end

JSON.null = setmetatable({}, { __tostring = function() return "null" end })
JSON.arrayMt = {}

-- Retourne une table vide qui sera encodée comme un tableau JSON "[]".
function JSON.emptyArray()
	return setmetatable({}, JSON.arrayMt)
end

function JSON.encode(v)
	return encodeValue(v)
end

---------------------------------------------------------------------------
-- Décodage
---------------------------------------------------------------------------

local function decodeError(str, pos, msg)
	error(string.format("JSON: %s à la position %d (%q)", msg, pos, str:sub(pos, pos + 20)))
end

local function skipWs(str, pos)
	return str:find("[^ \t\r\n]", pos) or #str + 1
end

local function utf8Char(cp)
	if cp < 0x80 then
		return string.char(cp)
	elseif cp < 0x800 then
		return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
	elseif cp < 0x10000 then
		return string.char(0xE0 + math.floor(cp / 0x1000),
			0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
	end
	return string.char(0xF0 + math.floor(cp / 0x40000),
		0x80 + math.floor(cp / 0x1000) % 0x40,
		0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local decodeValue

local function decodeString(str, pos)
	local buf = {}
	local i = pos + 1
	while true do
		local c = str:sub(i, i)
		if c == "" then
			decodeError(str, pos, "chaîne non terminée")
		elseif c == '"' then
			return table.concat(buf), i + 1
		elseif c == "\\" then
			local e = str:sub(i + 1, i + 1)
			local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
			if map[e] then
				buf[#buf + 1] = map[e]
				i = i + 2
			elseif e == "u" then
				local cp = tonumber(str:sub(i + 2, i + 5), 16)
				if not cp then decodeError(str, i, "séquence \\u invalide") end
				i = i + 6
				-- paire de substitution UTF-16
				if cp >= 0xD800 and cp <= 0xDBFF and str:sub(i, i + 1) == "\\u" then
					local lo = tonumber(str:sub(i + 2, i + 5), 16)
					if lo and lo >= 0xDC00 and lo <= 0xDFFF then
						cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
						i = i + 6
					end
				end
				buf[#buf + 1] = utf8Char(cp)
			else
				decodeError(str, i, "échappement invalide")
			end
		else
			local j = str:find('["\\]', i) or #str + 1
			buf[#buf + 1] = str:sub(i, j - 1)
			i = j
		end
	end
end

local function decodeArray(str, pos)
	local result = {}
	pos = skipWs(str, pos + 1)
	if str:sub(pos, pos) == "]" then
		return result, pos + 1
	end
	while true do
		local v
		v, pos = decodeValue(str, pos)
		result[#result + 1] = v
		pos = skipWs(str, pos)
		local c = str:sub(pos, pos)
		if c == "]" then
			return result, pos + 1
		elseif c ~= "," then
			decodeError(str, pos, "',' ou ']' attendu")
		end
		pos = skipWs(str, pos + 1)
	end
end

local function decodeObject(str, pos)
	local result = {}
	pos = skipWs(str, pos + 1)
	if str:sub(pos, pos) == "}" then
		return result, pos + 1
	end
	while true do
		if str:sub(pos, pos) ~= '"' then
			decodeError(str, pos, "clé attendue")
		end
		local key
		key, pos = decodeString(str, pos)
		pos = skipWs(str, pos)
		if str:sub(pos, pos) ~= ":" then
			decodeError(str, pos, "':' attendu")
		end
		pos = skipWs(str, pos + 1)
		local v
		v, pos = decodeValue(str, pos)
		result[key] = v
		pos = skipWs(str, pos)
		local c = str:sub(pos, pos)
		if c == "}" then
			return result, pos + 1
		elseif c ~= "," then
			decodeError(str, pos, "',' ou '}' attendu")
		end
		pos = skipWs(str, pos + 1)
	end
end

decodeValue = function(str, pos)
	pos = skipWs(str, pos)
	local c = str:sub(pos, pos)
	if c == "{" then
		return decodeObject(str, pos)
	elseif c == "[" then
		return decodeArray(str, pos)
	elseif c == '"' then
		return decodeString(str, pos)
	elseif str:sub(pos, pos + 3) == "true" then
		return true, pos + 4
	elseif str:sub(pos, pos + 4) == "false" then
		return false, pos + 5
	elseif str:sub(pos, pos + 3) == "null" then
		return nil, pos + 4
	end
	local num = str:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
	if num and #num > 0 then
		return tonumber(num), pos + #num
	end
	decodeError(str, pos, "valeur inattendue")
end

function JSON.decode(str)
	if type(str) ~= "string" then
		error("JSON: chaîne attendue")
	end
	local v, pos = decodeValue(str, 1)
	pos = skipWs(str, pos)
	if pos <= #str then
		decodeError(str, pos, "caractères en trop")
	end
	return v
end

return JSON
