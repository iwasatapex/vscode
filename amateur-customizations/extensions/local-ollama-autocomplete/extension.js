"use strict";
// Local Ollama Autocomplete model picker.
// Scope: ONLY github.copilot.localAutocomplete.* . Does NOT touch Chat, Agent,
// remote Copilot completions, authentication, or the local Ollama adapter.
const vscode = require("vscode");
const fs = require("fs");
const os = require("os");
const path = require("path");

// EXACTLY three models. Exact Ollama ids only -- no aliases, no substitutions.
const MODELS = [
  { id: "qwen2.5-coder:1.5b", description: "Qwen2.5 Coder 1.5B" },
  { id: "qwen2.5-coder:3b-base", description: "Qwen2.5 Coder 3B Base" },
  { id: "qwen2.5-coder:7b-base", description: "Qwen2.5 Coder 7B Base" },
];

const SECTION = "github.copilot.localAutocomplete";

function normalizeEndpoint(ep) {
  return String(ep || "http://127.0.0.1:11435").replace(/\/+$/, "");
}

// Returns Set of installed model names, or null if the endpoint is unreachable
// (so callers can distinguish "unknown" from "not installed"). Never throws.
async function getInstalledTags(endpoint) {
  try {
    const r = await fetch(normalizeEndpoint(endpoint) + "/api/tags", { method: "GET" });
    if (!r || !r.ok) return null;
    const j = await r.json();
    const names = (j && Array.isArray(j.models)) ? j.models.map((m) => m.name) : [];
    return new Set(names);
  } catch (_e) {
    return null;
  }
}

// true / false / null(unknown)
function isInstalled(tags, id) {
  if (!tags) return null;
  return tags.has(id) || tags.has(id + ":latest");
}

// ---- ON/OFF toggle via direct, JSONC-safe edit of User settings.json --------
// github.copilot.localAutocomplete.enabled is NOT registered in Code - OSS's
// configuration schema, so vscode.configuration update() throws
// "is not a registered configuration". We therefore read/write that single key
// by surgically editing the User settings.json (comments/formatting preserved).
const ENABLED_KEY = "github.copilot.localAutocomplete.enabled";

// Resolve the real Code - OSS User settings.json path (no hardcoded assumptions).
function getSettingsPath() {
  // Portable installation (VSCODE_PORTABLE points at the data dir root).
  if (process.env.VSCODE_PORTABLE) {
    return path.join(process.env.VSCODE_PORTABLE, "user-data", "User", "settings.json");
  }
  const appName = (vscode.env && vscode.env.appName) ? vscode.env.appName : "Code - OSS";
  const plat = process.platform;
  if (plat === "win32") {
    const appData = process.env.APPDATA || path.join(os.homedir(), "AppData", "Roaming");
    return path.join(appData, appName, "User", "settings.json");
  }
  if (plat === "darwin") {
    return path.join(os.homedir(), "Library", "Application Support", appName, "User", "settings.json");
  }
  const xdg = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config");
  return path.join(xdg, appName, "User", "settings.json");
}

// Scan JSONC text for the value span of a top-level property whose key equals
// `key`. Skips // and /* */ comments and never matches inside string literals,
// so a commented-out key is correctly treated as absent. Returns
// { valueStart, valueEnd } indices into `text`, or null if the key is absent.
function findKeyValueSpan(text, key) {
  const n = text.length;
  let i = 0;
  let depth = 0;

  // Advance past a string literal starting at the opening quote (i points at ").
  // Returns the index just after the closing quote.
  const skipString = (start) => {
    let j = start + 1;
    while (j < n && text[j] !== '"') {
      if (text[j] === "\\") j++;
      j++;
    }
    return j + 1;
  };
  // Advance past whitespace and comments; return the next significant index.
  const skipTrivia = (start) => {
    let j = start;
    while (j < n) {
      if (text[j] === "/" && text[j + 1] === "/") { while (j < n && text[j] !== "\n") j++; continue; }
      if (text[j] === "/" && text[j + 1] === "*") { j += 2; while (j < n && !(text[j] === "*" && text[j + 1] === "/")) j++; j += 2; continue; }
      if (/\s/.test(text[j])) { j++; continue; }
      break;
    }
    return j;
  };

  while (i < n) {
    const c = text[i];
    const c2 = i + 1 < n ? text[i + 1] : "";
    // Comments.
    if (c === "/" && c2 === "/") { while (i < n && text[i] !== "\n") i++; continue; }
    if (c === "/" && c2 === "*") { i += 2; while (i < n && !(text[i] === "*" && text[i + 1] === "/")) i++; i += 2; continue; }

    // At depth 1 a quoted token is an object key.
    if (c === '"' && depth === 1) {
      const strStart = i;
      let j = strStart + 1;
      let raw = "";
      while (j < n && text[j] !== '"') {
        if (text[j] === "\\") { raw += text[j + 1] || ""; j += 2; continue; }
        raw += text[j];
        j++;
      }
      i = j + 1; // past closing quote
      if (raw === key) {
        i = skipTrivia(i);
        if (text[i] !== ":") return null; // malformed; treat as absent
        i = skipTrivia(i + 1);
        const valueStart = i;
        if (text[i] === '"') {
          i = skipString(i);
        } else {
          while (i < n && !/[,\}\]\r\n]/.test(text[i]) &&
                 !(text[i] === "/" && (text[i + 1] === "/" || text[i + 1] === "*"))) {
            i++;
          }
        }
        return { valueStart, valueEnd: i };
      }
      continue;
    }

    // Elsewhere a quoted token is a string literal (value or nested key): skip it.
    if (c === '"') { i = skipString(i); continue; }

    if (c === "{" || c === "[") depth++;
    if (c === "}" || c === "]") depth--;
    i++;
  }
  return null;
}

// Extract a boolean value for `key` from raw JSONC text. Commented-out keys and
// non-boolean values are treated as false. Never throws.
function readBoolFromSettings(text, key) {
  const span = findKeyValueSpan(text, key);
  if (!span) return false;
  const raw = text.slice(span.valueStart, span.valueEnd).trim();
  return raw === "true";
}

// Read github.copilot.localAutocomplete.enabled fresh from the settings file.
function isAutocompleteEnabled() {
  try {
    const text = fs.readFileSync(getSettingsPath(), "utf8");
    return readBoolFromSettings(text, ENABLED_KEY);
  } catch (_e) {
    return false;
  }
}

// Surgically set github.copilot.localAutocomplete.enabled in settings.json.
// - If the key exists, replace ONLY its value token (comments/formatting kept).
// - If absent, insert it as the first property of the root object.
// - Backs up the file first. Never touches any other setting. Never workspace.
function setAutocompleteEnabled(value) {
  const file = getSettingsPath();
  let text = "";
  try {
    text = fs.readFileSync(file, "utf8");
  } catch (_e) {
    text = "";
  }

  // Backup before modifying (only if the file already has content).
  if (text.trim()) {
    try {
      fs.writeFileSync(file + ".localollama.bak", text, "utf8");
    } catch (_e) {
      /* best-effort backup */
    }
  }

  const boolStr = value ? "true" : "false";
  const span = findKeyValueSpan(text, ENABLED_KEY);

  let updated;
  if (span) {
    updated = text.slice(0, span.valueStart) + boolStr + text.slice(span.valueEnd);
  } else {
    // Insert as the first property of the root object, preserving EOL style.
    const idx = text.indexOf("{");
    if (idx === -1) {
      updated = "{\n  \"" + ENABLED_KEY + "\": " + boolStr + "\n}\n";
    } else {
      const eol = text.includes("\r\n") ? "\r\n" : "\n";
      updated =
        text.slice(0, idx + 1) +
        eol + "  \"" + ENABLED_KEY + "\": " + boolStr + "," +
        text.slice(idx + 1);
    }
  }

  fs.writeFileSync(file, updated, "utf8");
}

async function selectModel() {
  const cfg = vscode.workspace.getConfiguration(SECTION);
  const endpoint = cfg.get("endpoint", "http://127.0.0.1:11435");
  const current = cfg.get("model", MODELS[0].id);
  // Read ON/OFF fresh every time the picker opens (from settings.json, since
  // `enabled` is not a registered configuration in Code - OSS).
  const enabled = isAutocompleteEnabled();
  const tags = await getInstalledTags(endpoint);

  // Toggle item, always first. $(check) ~ ✓, $(circle-outline) ~ ○.
  const toggleItem = {
    label: (enabled ? "$(check) " : "$(circle-outline) ") +
      "Local Autocomplete: " + (enabled ? "ON" : "OFF"),
    description: "Toggle local autocomplete",
    detail: enabled
      ? "Local Ollama completions enabled"
      : "Local Ollama completions disabled",
    isToggle: true,
  };

  const modelItems = MODELS.map((m) => {
    const inst = isInstalled(tags, m.id);
    const mark = m.id === current ? "$(check) " : "";
    const avail = inst === null ? "" : inst ? "Installed" : "Not installed";
    return {
      label: mark + m.description,
      description: m.id,
      detail: avail,
      modelId: m.id,
    };
  });

  const picked = await vscode.window.showQuickPick([toggleItem, ...modelItems], {
    title: "Local Ollama Autocomplete",
    placeHolder: "Select a local Ollama autocomplete model",
    matchOnDescription: true,
  });
  if (!picked) return undefined;

  // Toggle ONLY flips github.copilot.localAutocomplete.enabled (via a surgical
  // settings.json edit -- never cfg.update, which fails for this unregistered
  // key), then reopens the picker so the new state is visible. The selected
  // model is left untouched.
  if (picked.isToggle) {
    const currently = isAutocompleteEnabled();
    setAutocompleteEnabled(!currently);
    return selectModel();
  }

  // Update ONLY the local autocomplete model setting. Never `enabled`, never remote.
  await cfg.update("model", picked.modelId, vscode.ConfigurationTarget.Global);
  vscode.window.setStatusBarMessage("Local Ollama Autocomplete model: " + picked.modelId, 4000);
  return picked.modelId;
}

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand("localOllamaAutocomplete.selectModel", selectModel)
  );
}

function deactivate() {}

module.exports = {
  activate,
  deactivate,
  selectModel,
  MODELS,
  getInstalledTags,
  isInstalled,
  normalizeEndpoint,
  isAutocompleteEnabled,
  setAutocompleteEnabled,
  getSettingsPath,
  readBoolFromSettings,
};
