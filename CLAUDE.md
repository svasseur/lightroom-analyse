# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Lightroom Classic plug-in (Lua, Lightroom SDK) that sends photo previews to a local Ollama vision model (default `qwen2.5vl:7b`) and adds the returned tags as keywords. It only ever adds keywords and must never remove existing ones. All plug-in code lives in `OllamaTagger.lrplugin/`; user-facing strings, comments and the README are in French.

## Commands

There is no build step, no test suite and no package manager: Lightroom loads the `.lrplugin` folder directly.

- Syntax check all files: `cd OllamaTagger.lrplugin && for f in *.lua; do luac -p "$f"; done` (Homebrew `lua` 5.4 is installed; Lightroom embeds Lua 5.1, so avoid 5.2+ features such as `goto`, integer division `//`, bitwise operators, `utf8` library).
- Check that Ollama is running and the model is installed: `curl -s localhost:11434/api/tags`.
- In Lightroom: File › Plug-in Manager › Add the folder, then "Reload Plug-in" after each edit. Logs go to `~/Documents/LrClassicLogs/OllamaTagger.log` (`LrLogger("OllamaTagger")`).

The SDK-independent modules (`JSON.lua`, `OllamaClient.lua`) can be tested outside Lightroom with plain `lua` by defining a global `import(name)` that returns stub tables for `LrHttp` (`post`/`get` via `curl` through `io.popen`) and `LrStringUtils` (`lower`, `encodeBase64`), then putting the plug-in folder on `package.path` and calling `OllamaClient.analyze(jpegBytes, prefs)`. `AnalyzeMenuItem.lua` and `PluginInfoProvider.lua` depend on the catalog/UI and can only be exercised inside Lightroom.

## Architecture

Flow when the user runs "Analyser la sélection avec Ollama…" (`AnalyzeMenuItem.lua`, registered in `Info.lua` under both Library and File/Export menus):

1. Runs inside `LrFunctionContext.postAsyncTaskWithContext` (required for HTTP calls, sleeps and catalog writes). Calls `OllamaClient.checkConnection` first and aborts with a dialog if Ollama or the model is missing.
2. Creates the parent keyword (`IA`) and the marker keyword (`ia-analysé`) in their **own** `withWriteAccessDo` transaction before the loop. This is a precaution so the keyword is committed before being used as a parent.
3. For each photo, gets a JPEG with `photo:requestJpegThumbnail`. This is how smart previews are supported: Lightroom renders from the smart preview when the original is offline. Smart previews themselves are DNG files Ollama can't read, so don't try to read them directly. The callback is async: the returned handle must stay referenced until the callback fires, and the code polls with `LrTasks.sleep`.
4. `OllamaClient.analyze` base64-encodes the JPEG and sends it to `POST /api/chat` with a JSON-schema `format` (`{"tags": [string]}`, which needs Ollama ≥ 0.5). `parseTags` falls back to extracting a `{…}` block, then to comma/newline splitting, for models that ignore the schema. `normalizeTags` lowercases, dedupes, strips `,;|` (special in Lightroom keyword syntax) and caps the count.
5. Writes keywords in one `withWriteAccessDo` per photo, so progress survives a cancel or a crash. `createKeyword(..., returnExisting = true)` reuses existing keywords.

Preferences: `Defaults.lua` is the single source of default values. `Init.lua` (`LrInitPlugin`) copies missing defaults into `LrPrefs.prefsForPlugin()`, and `PluginInfoProvider.lua` binds the Plug-in Manager UI directly to that prefs object. To add a setting, add it to `Defaults.lua`, add a UI row in `PluginInfoProvider.lua`, then read it via `prefs.<key>`.

`JSON.lua` is a self-contained Lua 5.1 JSON encoder/decoder, because the Lightroom SDK has none. Empty Lua tables encode as `{}`. Use `JSON.emptyArray()` when `[]` is needed.
