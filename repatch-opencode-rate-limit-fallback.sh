#!/usr/bin/env bash
set -euo pipefail

APP="${1:-/Applications/OpenCode.app}"
DRY_RUN="${DRY_RUN:-0}"

if [[ "${1:-}" == "--dry-run" ]]; then
  APP="/Applications/OpenCode.app"
  DRY_RUN=1
elif [[ "${2:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

if [[ ! -d "$APP/Contents/Resources" ]]; then
  echo "OpenCode app not found: $APP" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "node is required" >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required for @electron/asar" >&2
  exit 1
fi

RESOURCES="$APP/Contents/Resources"
ASAR="$RESOURCES/app.asar"
PLIST="$APP/Contents/Info.plist"
STAMP="$(date +%Y%m%d%H%M%S)"
WORK="$(mktemp -d /tmp/opencode-repatch.XXXXXX)"
ENTITLEMENTS="$WORK/entitlements.plist"
PATCHER="$WORK/patch-opencode.js"
PATCHED_ASAR="$WORK/app.asar"

cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

cat >"$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.allow-dyld-environment-variables</key>
  <true/>
  <key>com.apple.security.cs.allow-jit</key>
  <true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
  <true/>
  <key>com.apple.security.cs.disable-library-validation</key>
  <true/>
  <key>com.apple.security.get-task-allow</key>
  <true/>
  <key>com.apple.security.cs.debugger</key>
  <true/>
</dict>
</plist>
PLIST

cat >"$PATCHER" <<'NODE'
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const root = process.argv[2];
if (!root) throw new Error("missing extracted app root");

const touched = new Set();

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

function read(file) {
  return fs.readFileSync(file, "utf8");
}

function write(file, text) {
  fs.writeFileSync(file, text);
  touched.add(file);
}

function rel(file) {
  return path.relative(root, file);
}

function mustFind(files, predicate, label) {
  const found = files.filter(predicate);
  if (found.length !== 1) {
    throw new Error(`expected exactly one ${label}, found ${found.length}: ${found.map(rel).join(", ")}`);
  }
  return found[0];
}

function replaceOnce(text, search, replacement, label) {
  const count = text.split(search).length - 1;
  if (count !== 1) {
    throw new Error(`expected exactly one match for ${label}, found ${count}`);
  }
  return text.replace(search, replacement);
}

function insertAfter(text, search, addition, marker, label) {
  if (text.includes(marker)) return text;
  return replaceOnce(text, search, search + addition, label);
}

function insertBefore(text, search, addition, marker, label) {
  if (text.includes(marker)) return text;
  return replaceOnce(text, search, addition + search, label);
}

const CLAUDE_CODE_HELPERS = "var CLAUDE_CODE_PROVIDER_ID = \"claude-code\", CLAUDE_CODE_PACKAGE = \"@opencode/claude-code\";\nfunction isClaudeCodeProviderID(providerID2) {\n  return String(providerID2) === CLAUDE_CODE_PROVIDER_ID;\n}\nfunction claudeCodeModelsDevProvider() {\n  const model = (id12, name38, family, costInput, costOutput) => ({\n    id: id12,\n    name: name38,\n    family,\n    status: \"active\",\n    release_date: \"2026-06-15\",\n    cost: {\n      input: costInput,\n      output: costOutput,\n      cache_read: 0,\n      cache_write: 0\n    },\n    limit: {\n      context: 2e5,\n      output: 64e3\n    },\n    modalities: {\n      input: [\"text\"],\n      output: [\"text\"]\n    },\n    temperature: false,\n    reasoning: false,\n    attachment: false,\n    tool_call: false\n  });\n  return {\n    id: CLAUDE_CODE_PROVIDER_ID,\n    name: \"Claude Code\",\n    env: [],\n    npm: CLAUDE_CODE_PACKAGE,\n    api: \"\",\n    models: {\n      opus: model(\"opus\", \"Claude Code Opus\", \"claude\", 15, 75),\n      sonnet: model(\"sonnet\", \"Claude Code Sonnet\", \"claude\", 3, 15),\n      haiku: model(\"haiku\", \"Claude Code Haiku\", \"claude\", 1, 5)\n    }\n  };\n}\nfunction claudeCodeProviderInfo() {\n  return fromModelsDevProvider(claudeCodeModelsDevProvider());\n}\nfunction claudeCodeSpawnEnv() {\n  const env4 = { ...process.env };\n  const pathParts = [\n    path78__default.join(OS__default.homedir(), \".local/bin\"),\n    \"/opt/homebrew/bin\",\n    \"/usr/local/bin\",\n    env4.PATH\n  ].filter(Boolean);\n  env4.PATH = [...new Set(pathParts.join(path78__default.delimiter).split(path78__default.delimiter).filter(Boolean))].join(path78__default.delimiter);\n  delete env4.ELECTRON_RUN_AS_NODE;\n  return env4;\n}\nfunction findClaudeCodeBinary() {\n  const envPath = process.env.CLAUDE_CODE_PATH;\n  const candidates = [\n    envPath,\n    path78__default.join(OS__default.homedir(), \".local/bin/claude\"),\n    \"/opt/homebrew/bin/claude\",\n    \"/usr/local/bin/claude\",\n    ...String(process.env.PATH ?? \"\").split(path78__default.delimiter).filter(Boolean).map((item2) => path78__default.join(item2, \"claude\"))\n  ].filter((item2) => typeof item2 === \"string\" && item2.trim() !== \"\");\n  for (const item2 of candidates) {\n    try {\n      if (fs10__default.existsSync(item2))\n        return item2;\n    } catch {\n    }\n  }\n  try {\n    const result5 = NodeChildProcess__default.spawnSync(\"claude\", [\"--version\"], {\n      env: claudeCodeSpawnEnv(),\n      stdio: \"ignore\"\n    });\n    if (result5.status === 0)\n      return \"claude\";\n  } catch {\n  }\n  return;\n}\nfunction claudeCodeStringify(value4) {\n  if (value4 === void 0 || value4 === null)\n    return \"\";\n  if (typeof value4 === \"string\")\n    return value4;\n  if (typeof value4 === \"number\" || typeof value4 === \"boolean\" || typeof value4 === \"bigint\")\n    return String(value4);\n  try {\n    return JSON.stringify(value4, null, 2);\n  } catch {\n    return String(value4);\n  }\n}\nfunction claudeCodePartText(part2) {\n  if (part2 === void 0 || part2 === null)\n    return \"\";\n  if (typeof part2 === \"string\")\n    return part2;\n  const type = part2.type;\n  if (type === \"text\")\n    return claudeCodeStringify(part2.text);\n  if (type === \"reasoning\")\n    return `[reasoning]\\n${claudeCodeStringify(part2.text)}`;\n  if (type === \"file\" || type === \"media\")\n    return `[attached ${part2.mediaType ?? part2.mimeType ?? \"file\"}${part2.filename ? `: ${part2.filename}` : \"\"}]`;\n  if (type === \"image\")\n    return \"[attached image]\";\n  if (type === \"tool-call\")\n    return `[tool call: ${part2.toolName ?? part2.name ?? part2.id ?? \"unknown\"}]\\n${claudeCodeStringify(part2.input ?? part2.args)}`;\n  if (type === \"tool-result\")\n    return `[tool result: ${part2.toolName ?? part2.name ?? part2.toolCallId ?? \"unknown\"}]\\n${claudeCodeStringify(part2.output ?? part2.result ?? part2.content)}`;\n  if (type === \"tool-error\")\n    return `[tool error: ${part2.toolName ?? part2.name ?? part2.toolCallId ?? \"unknown\"}]\\n${claudeCodeStringify(part2.error ?? part2.message)}`;\n  return claudeCodeStringify(part2.text ?? part2.content ?? part2);\n}\nfunction claudeCodeContentText(content2) {\n  if (typeof content2 === \"string\")\n    return content2;\n  if (Array.isArray(content2))\n    return content2.map(claudeCodePartText).filter((item2) => item2.trim() !== \"\").join(\"\\n\\n\");\n  return claudeCodePartText(content2);\n}\nfunction claudeCodeMessageText(message32) {\n  const role = message32.role ?? \"user\";\n  const text82 = claudeCodeContentText(message32.content);\n  return `### ${role}\\n${text82}`;\n}\nfunction claudeCodePromptText(messages3) {\n  return messages3.map(claudeCodeMessageText).filter((item2) => item2.trim() !== \"\").join(\"\\n\\n\");\n}\nfunction claudeCodeSystemText(system) {\n  const base5 = Array.isArray(system) ? system.map(claudeCodePartText).filter((item2) => item2.trim() !== \"\").join(\"\\n\\n\") : claudeCodeStringify(system);\n  return [\n    base5,\n    \"You are running as the Claude Code provider inside OpenCode. OpenCode owns tool execution, file edits, permissions, and conversation state. Do not use Claude Code tools; continue from the context provided in the prompt.\"\n  ].filter((item2) => item2.trim() !== \"\").join(\"\\n\\n\");\n}\nfunction claudeCodePromptFromAI(options10) {\n  const prompt = options10.prompt ?? [];\n  const system = prompt.filter((message32) => message32.role === \"system\").map((message32) => claudeCodeContentText(message32.content)).join(\"\\n\\n\");\n  const messages3 = prompt.filter((message32) => message32.role !== \"system\");\n  return {\n    system: claudeCodeSystemText([options10.system, system].filter(Boolean).join(\"\\n\\n\")),\n    prompt: claudeCodePromptText(messages3)\n  };\n}\nfunction claudeCodePromptFromLLM(request32) {\n  return {\n    system: claudeCodeSystemText(request32.system ?? []),\n    prompt: claudeCodePromptText(request32.messages ?? [])\n  };\n}\nfunction claudeCodeUsageFromRaw(raw32) {\n  if (!raw32 || typeof raw32 !== \"object\")\n    return;\n  const usage3 = raw32.usage ?? raw32.message?.usage ?? raw32;\n  const input = usage3.input_tokens ?? usage3.inputTokens;\n  const output2 = usage3.output_tokens ?? usage3.outputTokens;\n  const cacheRead = usage3.cache_read_input_tokens ?? usage3.cacheReadInputTokens;\n  const cacheWrite = usage3.cache_creation_input_tokens ?? usage3.cacheWriteInputTokens;\n  const entries5 = Object.entries({\n    inputTokens: input,\n    outputTokens: output2,\n    totalTokens: usage3.total_tokens ?? usage3.totalTokens ?? (typeof input === \"number\" && typeof output2 === \"number\" ? input + output2 : void 0),\n    cacheReadInputTokens: cacheRead,\n    cacheWriteInputTokens: cacheWrite\n  }).filter((entry) => typeof entry[1] === \"number\" && Number.isFinite(entry[1]));\n  return entries5.length === 0 ? void 0 : Object.fromEntries(entries5);\n}\nfunction claudeCodeAIUsage(usage3) {\n  return {\n    inputTokens: {\n      total: usage3?.inputTokens,\n      noCache: usage3?.inputTokens,\n      cacheRead: usage3?.cacheReadInputTokens,\n      cacheWrite: usage3?.cacheWriteInputTokens\n    },\n    outputTokens: {\n      total: usage3?.outputTokens,\n      text: usage3?.outputTokens\n    },\n    raw: usage3\n  };\n}\nfunction claudeCodeErrorMessage(error512) {\n  if (!error512)\n    return \"Claude Code failed\";\n  if (error512 instanceof Error)\n    return error512.message;\n  return String(error512);\n}\nfunction claudeCodeExtractText(event2, state22) {\n  if (!event2 || typeof event2 !== \"object\")\n    return \"\";\n  if (event2.type === \"assistant\" && event2.message?.content) {\n    const full = claudeCodeContentText(event2.message.content);\n    if (!full)\n      return \"\";\n    let delta = full;\n    if (state22.assistantText && full.startsWith(state22.assistantText))\n      delta = full.slice(state22.assistantText.length);\n    else if (full === state22.assistantText)\n      delta = \"\";\n    state22.assistantText = full;\n    state22.assistantEmitted = true;\n    return delta;\n  }\n  if (event2.type === \"content_block_delta\" && event2.delta?.text)\n    return event2.delta.text;\n  if (typeof event2.delta === \"string\")\n    return event2.delta;\n  if (typeof event2.text === \"string\" && event2.type !== \"system\")\n    return event2.text;\n  if (event2.type === \"result\" && typeof event2.result === \"string\" && !state22.assistantEmitted)\n    return event2.result;\n  return \"\";\n}\nasync function* claudeCodeTextStream(input) {\n  const command = input.command ?? findClaudeCodeBinary();\n  if (!command)\n    throw new Error(\"Claude Code CLI not found. Install Claude Code or set CLAUDE_CODE_PATH.\");\n  const tmp = await fs14__default.mkdtemp(path78__default.join(OS__default.tmpdir(), \"opencode-claude-code-\"));\n  const systemPath = path78__default.join(tmp, \"system.md\");\n  await fs14__default.writeFile(systemPath, input.system, \"utf8\");\n  const args4 = [\n    \"--print\",\n    \"--input-format\",\n    \"text\",\n    \"--output-format\",\n    \"stream-json\",\n    \"--verbose\",\n    \"--model\",\n    input.model,\n    \"--system-prompt-file\",\n    systemPath,\n    \"--no-session-persistence\",\n    \"--disable-slash-commands\",\n    \"--tools\",\n    \"\"\n  ];\n  const child = NodeChildProcess__default.spawn(command, args4, {\n    env: claudeCodeSpawnEnv(),\n    stdio: [\"pipe\", \"pipe\", \"pipe\"]\n  });\n  const queue = [];\n  let stdout = \"\";\n  let stderr = \"\";\n  let done3 = false;\n  let error46;\n  let notify;\n  const state22 = { assistantText: \"\", assistantEmitted: false };\n  const wake = () => {\n    if (notify) {\n      const fn3 = notify;\n      notify = void 0;\n      fn3();\n    }\n  };\n  const push = (item2) => {\n    queue.push(item2);\n    wake();\n  };\n  const handleLine = (line6) => {\n    const trimmed = line6.trim();\n    if (!trimmed)\n      return;\n    try {\n      const event2 = JSON.parse(trimmed);\n      const usage3 = claudeCodeUsageFromRaw(event2);\n      if (usage3)\n        push({ type: \"usage\", usage: usage3 });\n      const text82 = claudeCodeExtractText(event2, state22);\n      if (text82)\n        push({ type: \"text\", text: text82 });\n    } catch {\n      push({ type: \"text\", text: `${line6}\\n` });\n    }\n  };\n  child.stdout.on(\"data\", (chunk) => {\n    stdout += chunk.toString(\"utf8\");\n    let index3;\n    while ((index3 = stdout.indexOf(\"\\n\")) !== -1) {\n      const line6 = stdout.slice(0, index3);\n      stdout = stdout.slice(index3 + 1);\n      handleLine(line6);\n    }\n  });\n  child.stderr.on(\"data\", (chunk) => {\n    stderr += chunk.toString(\"utf8\");\n  });\n  child.on(\"error\", (e3) => {\n    error46 = e3;\n    done3 = true;\n    wake();\n  });\n  child.on(\"close\", (code, signal) => {\n    if (stdout.trim()) {\n      handleLine(stdout);\n      stdout = \"\";\n    }\n    if (code !== 0) {\n      const suffix = signal ? ` signal ${signal}` : ` code ${code}`;\n      error46 = new Error((stderr.trim() || `Claude Code exited with${suffix}`).trim());\n    }\n    done3 = true;\n    wake();\n  });\n  if (input.abortSignal) {\n    input.abortSignal.addEventListener(\"abort\", () => {\n      try {\n        child.kill(\"SIGTERM\");\n      } catch {\n      }\n    }, { once: true });\n  }\n  child.stdin.end(input.prompt);\n  try {\n    while (!done3 || queue.length > 0) {\n      if (queue.length > 0) {\n        yield queue.shift();\n        continue;\n      }\n      await new Promise((resolve4) => notify = resolve4);\n    }\n    if (error46)\n      throw error46;\n  } finally {\n    try {\n      child.kill(\"SIGTERM\");\n    } catch {\n    }\n    await fs14__default.rm(tmp, { recursive: true, force: true });\n  }\n}\nfunction createClaudeCodeLanguageModel(modelID, options10 = {}) {\n  return {\n    specificationVersion: \"v3\",\n    provider: CLAUDE_CODE_PROVIDER_ID,\n    modelId: modelID,\n    supportedUrls: {},\n    async doGenerate(options11) {\n      const { system, prompt } = claudeCodePromptFromAI(options11);\n      let text82 = \"\";\n      let usage3;\n      for await (const item2 of claudeCodeTextStream({\n        command: options10.command,\n        model: modelID,\n        system,\n        prompt,\n        abortSignal: options11.abortSignal\n      })) {\n        if (item2.type === \"usage\")\n          usage3 = item2.usage;\n        if (item2.type === \"text\")\n          text82 += item2.text;\n      }\n      return {\n        content: [{ type: \"text\", text: text82 }],\n        finishReason: { unified: \"stop\", raw: \"stop\" },\n        usage: claudeCodeAIUsage(usage3),\n        warnings: [],\n        response: { headers: {} },\n        request: { body: { model: modelID } }\n      };\n    },\n    async doStream(options11) {\n      const { system, prompt } = claudeCodePromptFromAI(options11);\n      const command = options10.command;\n      const stream11 = new ReadableStream({\n        async start(controller) {\n          let textStarted = false;\n          let usage3;\n          controller.enqueue({ type: \"stream-start\", warnings: [] });\n          try {\n            for await (const item2 of claudeCodeTextStream({\n              command,\n              model: modelID,\n              system,\n              prompt,\n              abortSignal: options11.abortSignal\n            })) {\n              if (item2.type === \"usage\") {\n                usage3 = item2.usage;\n                continue;\n              }\n              if (!textStarted) {\n                controller.enqueue({ type: \"text-start\", id: \"text-0\" });\n                textStarted = true;\n              }\n              controller.enqueue({ type: \"text-delta\", id: \"text-0\", delta: item2.text });\n            }\n            if (textStarted)\n              controller.enqueue({ type: \"text-end\", id: \"text-0\" });\n            controller.enqueue({\n              type: \"finish\",\n              finishReason: { unified: \"stop\", raw: \"stop\" },\n              usage: claudeCodeAIUsage(usage3)\n            });\n            controller.close();\n          } catch (e3) {\n            controller.enqueue({ type: \"error\", error: e3 });\n            controller.enqueue({\n              type: \"finish\",\n              finishReason: { unified: \"error\", raw: \"error\" },\n              usage: claudeCodeAIUsage()\n            });\n            controller.close();\n          }\n        }\n      });\n      return {\n        stream: stream11,\n        request: { body: { model: modelID } },\n        response: { headers: {} }\n      };\n    }\n  };\n}\nfunction claudeCodePreparedRequest(request32) {\n  return new PreparedRequest({\n    id: request32.id ?? \"request\",\n    route: CLAUDE_CODE_PROVIDER_ID,\n    protocol: CLAUDE_CODE_PROVIDER_ID,\n    model: request32.model,\n    body: { model: request32.model.id },\n    metadata: { transport: \"claude-code-cli\" }\n  });\n}\nfunction claudeCodeLLMClientStream(request32) {\n  return fromAsyncIterable2((async function* () {\n    const { system, prompt } = claudeCodePromptFromLLM(request32);\n    let textStarted = false;\n    let usage3;\n    yield LLMEvent.stepStart({ index: 0 });\n    try {\n      for await (const item2 of claudeCodeTextStream({\n        model: request32.model.id,\n        system,\n        prompt,\n        abortSignal: request32.abort\n      })) {\n        if (item2.type === \"usage\") {\n          usage3 = item2.usage;\n          continue;\n        }\n        if (!textStarted) {\n          yield LLMEvent.textStart({ id: \"text-0\" });\n          textStarted = true;\n        }\n        yield LLMEvent.textDelta({ id: \"text-0\", text: item2.text });\n      }\n      if (textStarted)\n        yield LLMEvent.textEnd({ id: \"text-0\" });\n      yield LLMEvent.stepFinish({ index: 0, reason: \"stop\", usage: usage3 });\n      yield LLMEvent.finish({ reason: \"stop\", usage: usage3 });\n    } catch (e3) {\n      if (textStarted)\n        yield LLMEvent.textEnd({ id: \"text-0\" });\n      yield LLMEvent.providerError({ message: claudeCodeErrorMessage(e3), retryable: true });\n      yield LLMEvent.stepFinish({ index: 0, reason: \"error\" });\n      yield LLMEvent.finish({ reason: \"error\" });\n    }\n  })(), (e3) => e3 instanceof Error ? e3 : new Error(String(e3)));\n}\n";


function patchMainIndex(file) {
  let text = read(file);
  text = insertAfter(
    text,
    'const SETTINGS_STORE = "opencode.settings";\n',
    'const RENDERER_STORE = "default.dat";\n',
    'const RENDERER_STORE = "default.dat";',
    "renderer store constant"
  );
  text = insertAfter(
    text,
    '  if (process.platform === "linux") delete env.LD_PRELOAD;\n',
    '  env.OPENCODE_DESKTOP_SETTINGS_PATH = join(app.getPath("userData"), RENDERER_STORE);\n',
    "OPENCODE_DESKTOP_SETTINGS_PATH",
    "sidecar settings env"
  );
  write(file, text);
}

function patchRendererSettings(file) {
  let text = read(file);
  text = insertAfter(
    text,
    "    showSessionProgressBar: true,\n    showCustomAgents: false",
    ",\n    rateLimitModelFallback: true",
    "rateLimitModelFallback: true",
    "default rate limit fallback setting"
  );
  text = insertAfter(
    text,
    '        setShowReasoningSummaries(value) {\n          setStore("general", "showReasoningSummaries", value);\n        },\n',
    '        rateLimitModelFallback: withFallback(() => store2.general?.rateLimitModelFallback, defaultSettings.general.rateLimitModelFallback),\n        setRateLimitModelFallback(value) {\n          setStore("general", "rateLimitModelFallback", value);\n        },\n',
    "setRateLimitModelFallback",
    "settings getter/setter"
  );
  write(file, text);
}

function patchModelSchemas(text) {
  text = insertAfter(
    text,
    '    model: exports_Schema.optional(exports_Schema.String).annotate({\n      description: "Model to use in the format of provider/model, eg anthropic/claude-2"\n    }),\n',
    '    model_fallback: exports_Schema.optional(exports_Schema.mutable(exports_Schema.Array(exports_Schema.String))).annotate({\n      description: "Fallback models to try, in order, when the active model is rate limited"\n    }),\n',
    "model_fallback: exports_Schema.optional(exports_Schema.mutable",
    "v1 model_fallback schema"
  );
  text = insertAfter(
    text,
    "    model: info32.model,\n",
    "    model_fallback: info32.model_fallback,\n",
    "model_fallback: info32.model_fallback",
    "v1 migration model_fallback"
  );
  text = insertAfter(
    text,
    '    model: exports_Schema.String.pipe(exports_Schema.optional).annotate({\n      description: "Default model to use when no session or agent model is selected"\n    }),\n',
    '    model_fallback: exports_Schema.String.pipe(exports_Schema.Array, exports_Schema.optional).annotate({\n      description: "Fallback models to try, in order, when the active model is rate limited"\n    }),\n',
    "model_fallback: exports_Schema.String.pipe(exports_Schema.Array",
    "v2 model_fallback schema"
  );
  return text;
}

function patchRanking(text) {
  if (text.includes("rankedRunnerModels =")) return text;
  text = replaceOnce(
    text,
    '}, resolve11 = (session2, model8) => fromCatalogModel(withVariant(model8, session2.model?.variant)), supported = (model8) => model8.api.type === "aisdk" && (model8.api.package === "@ai-sdk/openai" || model8.api.package === "@ai-sdk/anthropic" || model8.api.package === "@ai-sdk/openai-compatible" && model8.api.url !== void 0), locationLayer23;',
    '}, resolve11 = (session2, model8) => fromCatalogModel(withVariant(model8, session2.model?.variant)), supported = (model8) => model8.api.type === "aisdk" && (model8.api.package === "@ai-sdk/openai" || model8.api.package === "@ai-sdk/anthropic" || model8.api.package === "@ai-sdk/openai-compatible" && model8.api.url !== void 0), modelLabel = (model8) => `${model8.providerID} ${model8.id} ${model8.name} ${model8.family ?? ""}`.toLowerCase(), modelCost = (model8) => Math.max(0, ...model8.cost.map((item2) => (item2.input ?? 0) + (item2.output ?? 0))), modelStrengthScore = (model8) => {\n  const label3 = modelLabel(model8);\n  const input = model8.capabilities.input ?? [];\n  const output2 = model8.capabilities.output ?? [];\n  let score = 0;\n  score += input.includes("text") ? 60 : -500;\n  score += output2.includes("text") ? 100 : -500;\n  score += model8.capabilities.tools ? 120 : -60;\n  score += Math.min(110, modelCost(model8) * 4);\n  score += Math.min(90, Math.log10(Math.max(1, model8.limit.context)) * 13);\n  score += Math.min(70, Math.log10(Math.max(1, model8.limit.output)) * 11);\n  score += input.filter((item2) => item2 !== "text").length * 8;\n  score += output2.filter((item2) => item2 !== "text").length * 8;\n  score += model8.status === "active" ? 25 : model8.status === "beta" ? 5 : -50;\n  const ageMonths = Math.max(0, (Date.now() - model8.time.released.epochMilliseconds) / (1e3 * 60 * 60 * 24 * 30));\n  score += Math.max(0, 40 - ageMonths * 2);\n  if (/\\b(pro|opus|ultra|max)\\b/.test(label3))\n    score += 70;\n  if (/\\b(codex|sonnet|thinking|reasoning)\\b/.test(label3))\n    score += 35;\n  if (/\\b(gpt-5|gpt-4\\.1|claude|gemini-[23]|o[34]|grok-4|deepseek-r1|qwen3|kimi-k2)\\b/.test(label3))\n    score += 30;\n  if (/\\b(mini|nano|haiku|flash|lite|small|fast)\\b/.test(label3))\n    score -= 70;\n  if (label3.includes("chat") && !model8.capabilities.tools)\n    score -= 50;\n  return score;\n}, rankedRunnerModels = (models3) => {\n  const candidates = models3.filter((model8) => supported(model8) && model8.enabled && model8.status !== "deprecated" && model8.capabilities.input.includes("text") && model8.capabilities.output.includes("text"));\n  const toolCandidates = candidates.filter((model8) => model8.capabilities.tools);\n  const selected = toolCandidates.length > 0 ? toolCandidates : candidates;\n  return selected.toSorted((a4, b2) => modelStrengthScore(b2) - modelStrengthScore(a4) || String(a4.providerID).localeCompare(String(b2.providerID)) || String(a4.id).localeCompare(String(b2.id)));\n}, locationLayer23;',
    "model ranking helpers"
  );
  text = insertAfter(
    text,
    "    init_model2(),\n    init_catalog(),\n",
    "    init_config3(),\n",
    "init_config3(),\n    init_credential()",
    "config init for ranked models"
  );
  text = insertAfter(
    text,
    "    const catalog = yield* exports_catalog.Service;\n",
    "    const config62 = yield* exports_config3.Service;\n",
    "const config62 = yield* exports_config3.Service;",
    "config service for ranked models"
  );
  text = replaceOnce(
    text,
    '      resolve: exports_Effect.fn("SessionRunnerModel.resolve")(function* (session2) {\n        yield* boot.wait();\n        const selected = session2.model ? yield* catalog.model.get(session2.model.providerID, session2.model.id) : exports_Option.getOrUndefined((yield* catalog.model.default()).pipe(exports_Option.filter(supported))) ?? (yield* catalog.model.available()).find(supported);\n        if (!selected)\n          return yield* new ModelNotSelectedError({ sessionID: session2.id });\n        const connection = yield* integrations.connection.forIntegration(exports_integration.ID.make(selected.providerID));\n        return yield* fromCatalogModel(withVariant(selected, session2.model?.variant), connection, connection?.type === "credential" ? yield* credentials.get(connection.id) : void 0);\n      })',
    '      resolve: exports_Effect.fn("SessionRunnerModel.resolve")(function* (session2) {\n        yield* boot.wait();\n        const available3 = yield* catalog.model.available();\n        let selected;\n        if (session2.model) {\n          selected = yield* catalog.model.get(session2.model.providerID, session2.model.id);\n        } else {\n          const configuredDefault = exports_config3.latest(yield* config62.entries(), "model");\n          if (configuredDefault !== void 0) {\n            try {\n              const parsed = exports_model.parse(configuredDefault);\n              selected = exports_Option.getOrUndefined((yield* catalog.model.get(parsed.providerID, parsed.modelID).pipe(exports_Effect.option)).pipe(exports_Option.filter(supported)));\n            } catch {\n            }\n          }\n          selected ??= rankedRunnerModels(available3)[0];\n        }\n        if (!selected)\n          return yield* new ModelNotSelectedError({ sessionID: session2.id });\n        const connection = yield* integrations.connection.forIntegration(exports_integration.ID.make(selected.providerID));\n        return yield* fromCatalogModel(withVariant(selected, session2.model?.variant), connection, connection?.type === "credential" ? yield* credentials.get(connection.id) : void 0);\n      }),\n      ranked: exports_Effect.fn("SessionRunnerModel.ranked")(function* () {\n        yield* boot.wait();\n        return rankedRunnerModels(yield* catalog.model.available()).map((model8) => ({\n          id: model8.id,\n          providerID: model8.providerID,\n          apiID: model8.api.id\n        }));\n      })',
    "ranked model resolver"
  );
  return text;
}

function patchClaudeCodeIntegration(text) {
  text = insertBefore(
    text,
    "function custom6(dep) {\n",
    CLAUDE_CODE_HELPERS,
    "var CLAUDE_CODE_PROVIDER_ID",
    "Claude Code helper runtime"
  );
  if (text.includes('"stream-json",\n    "--model",')) {
    text = text.replace('"stream-json",\n    "--model",', '"stream-json",\n    "--verbose",\n    "--model",');
  }
  text = insertAfter(
    text,
    "function custom6(dep) {\n  return {\n",
    '    "claude-code": () => exports_Effect.succeed({\n      autoload: findClaudeCodeBinary() !== void 0,\n      options: {\n        command: findClaudeCodeBinary() ?? "claude"\n      },\n      async getModel(_sdk, modelID, options10) {\n        return createClaudeCodeLanguageModel(modelID, { command: options10?.command });\n      }\n    }),\n',
    '"claude-code": () => exports_Effect.succeed',
    "Claude Code custom provider"
  );
  if (!text.includes("data2[CLAUDE_CODE_PROVIDER_ID] = claudeCodeModelsDevProvider();")) {
    text = replaceOnce(
      text,
      "        const data2 = yield* modelsDev.get();\n",
      "        const data2 = { ...(yield* modelsDev.get()) };\n        if (findClaudeCodeBinary())\n          data2[CLAUDE_CODE_PROVIDER_ID] = claudeCodeModelsDevProvider();\n",
      "Claude Code models.dev catalog injection"
    );
  }
  if (!text.includes("catalog[CLAUDE_CODE_PROVIDER_ID] = claudeCodeProviderInfo();")) {
    text = replaceOnce(
      text,
      "      const catalog = i4(modelsDev, fromModelsDevProvider);\n      const database = i4(catalog, toPublicInfo);\n",
      "      const catalog = i4(modelsDev, fromModelsDevProvider);\n      if (findClaudeCodeBinary())\n        catalog[CLAUDE_CODE_PROVIDER_ID] = claudeCodeProviderInfo();\n      const database = i4(catalog, toPublicInfo);\n",
      "Claude Code provider database injection"
    );
  }
  text = insertAfter(
    text,
    '  if (resolved.api.type === "aisdk" && resolved.api.package === "@ai-sdk/anthropic") {\n    return exports_Effect.succeed(withDefaults(resolved, route2).with({ auth: key3 === void 0 ? exports_auth.none : exports_auth.header("x-api-key", key3) }).model({ id: resolved.api.id }));\n  }\n',
    '  if (resolved.api.type === "aisdk" && resolved.api.package === CLAUDE_CODE_PACKAGE) {\n    return exports_Effect.succeed(route2.with({\n      provider: CLAUDE_CODE_PROVIDER_ID,\n      endpoint: { baseURL: "http://localhost" },\n      limits: { context: resolved.limit.context, output: resolved.limit.output }\n    }).model({ id: resolved.api.id }));\n  }\n',
    'resolved.api.package === CLAUDE_CODE_PACKAGE',
    "Claude Code SessionRunnerModel support"
  );
  if (!text.includes('model8.api.package === CLAUDE_CODE_PACKAGE')) {
    text = replaceOnce(
      text,
      'model8.api.package === "@ai-sdk/anthropic" || model8.api.package === "@ai-sdk/openai-compatible"',
      'model8.api.package === "@ai-sdk/anthropic" || model8.api.package === CLAUDE_CODE_PACKAGE || model8.api.package === "@ai-sdk/openai-compatible"',
      "Claude Code supported model predicate"
    );
  }
  text = insertAfter(
    text,
    '  prepareWith = exports_Effect.fn("LLMClient.prepare")(function* (request32) {\n',
    '    if (request32.model.provider === CLAUDE_CODE_PROVIDER_ID)\n      return claudeCodePreparedRequest(request32);\n',
    'claudeCodePreparedRequest(request32)',
    "Claude Code prepared request"
  );
  if (!text.includes("streamWithClaudeCode")) {
    text = replaceOnce(
      text,
      "    return Service5.of({ prepare: prepareWith, stream: stream82, generate: generateWith(stream82) });\n",
      "    const streamWithClaudeCode = (request32) => request32.model.provider === CLAUDE_CODE_PROVIDER_ID ? claudeCodeLLMClientStream(request32) : stream82(request32);\n    return Service5.of({ prepare: prepareWith, stream: streamWithClaudeCode, generate: generateWith(streamWithClaudeCode) });\n",
      "Claude Code LLMClient stream"
    );
  }
  text = insertAfter(
    text,
    '      const provider11 = s6.providers[model8.providerID];\n',
    '      if (isClaudeCodeProviderID(model8.providerID)) {\n        const command = provider11?.options?.command;\n        const language2 = createClaudeCodeLanguageModel(model8.api.id, { command: typeof command === "string" ? command : void 0 });\n        s6.models.set(key3, language2);\n        return language2;\n      }\n',
    'isClaudeCodeProviderID(model8.providerID)',
    "Claude Code Provider.getLanguage"
  );
  if (!text.includes("var CLAUDE_CODE_EFFORTS")) {
    text = replaceOnce(
      text,
      "CLAUDE_CODE_PACKAGE = \"@opencode/claude-code\";\nfunction isClaudeCodeProviderID(providerID2) {",
      "CLAUDE_CODE_PACKAGE = \"@opencode/claude-code\";\nvar CLAUDE_CODE_EFFORTS = [\"low\", \"medium\", \"high\", \"xhigh\", \"max\"];\nfunction claudeCodeNormalizeEffort(value4) {\n  if (typeof value4 !== \"string\")\n    return;\n  const normalized = value4.trim().toLowerCase();\n  return CLAUDE_CODE_EFFORTS.includes(normalized) ? normalized : void 0;\n}\nfunction claudeCodeEffortFromProviderOptions(providerOptions) {\n  return claudeCodeNormalizeEffort(providerOptions?.[CLAUDE_CODE_PROVIDER_ID]?.effort);\n}\nfunction claudeCodeRequestEffort(request32) {\n  return claudeCodeEffortFromProviderOptions(request32?.providerOptions) ?? claudeCodeEffortFromProviderOptions(request32?.model?.route?.defaults?.providerOptions);\n}\nfunction isClaudeCodeProviderID(providerID2) {",
      "Claude Code effort helpers"
    );
  }
  if (!text.includes("values: CLAUDE_CODE_EFFORTS")) {
    text = replaceOnce(
      text,
      "temperature: false,\n    reasoning: false,\n    attachment: false,\n    tool_call: false\n  });",
      "temperature: false,\n    reasoning: true,\n    reasoning_options: [{ type: \"effort\", values: CLAUDE_CODE_EFFORTS }],\n    attachment: false,\n    tool_call: false\n  });",
      "Claude Code model reasoning"
    );
  }
  if (!text.includes("\"Claude Code Opus\", \"claude-opus\"")) {
    text = replaceOnce(
      text,
      "      opus: model(\"opus\", \"Claude Code Opus\", \"claude\", 15, 75),\n      sonnet: model(\"sonnet\", \"Claude Code Sonnet\", \"claude\", 3, 15),\n      haiku: model(\"haiku\", \"Claude Code Haiku\", \"claude\", 1, 5)",
      "      opus: model(\"opus\", \"Claude Code Opus\", \"claude-opus\", 15, 75),\n      sonnet: model(\"sonnet\", \"Claude Code Sonnet\", \"claude-sonnet\", 3, 15),\n      haiku: model(\"haiku\", \"Claude Code Haiku\", \"claude-haiku\", 1, 5)",
      "Claude Code distinct model families"
    );
  }
  if (!text.includes("args4.push(\"--effort\"")) {
    text = replaceOnce(
      text,
      "\"--tools\",\n    \"\"\n  ];\n  const child = NodeChildProcess__default.spawn(command, args4, {",
      "\"--tools\",\n    \"\"\n  ];\n  const claudeCodeEffort = claudeCodeNormalizeEffort(input.effort);\n  if (claudeCodeEffort)\n    args4.push(\"--effort\", claudeCodeEffort);\n  const child = NodeChildProcess__default.spawn(command, args4, {",
      "Claude Code effort flag"
    );
  }
  if (!text.includes("\n        effort: claudeCodeEffortFromProviderOptions(options11.providerOptions)")) {
    text = replaceOnce(
      text,
      "prompt,\n        abortSignal: options11.abortSignal",
      "prompt,\n        effort: claudeCodeEffortFromProviderOptions(options11.providerOptions),\n        abortSignal: options11.abortSignal",
      "Claude Code doGenerate effort"
    );
  }
  if (!text.includes("\n              effort: claudeCodeEffortFromProviderOptions(options11.providerOptions)")) {
    text = replaceOnce(
      text,
      "prompt,\n              abortSignal: options11.abortSignal",
      "prompt,\n              effort: claudeCodeEffortFromProviderOptions(options11.providerOptions),\n              abortSignal: options11.abortSignal",
      "Claude Code doStream effort"
    );
  }
  if (!text.includes("effort: claudeCodeRequestEffort(request32),")) {
    text = replaceOnce(
      text,
      "prompt,\n        abortSignal: request32.abort",
      "prompt,\n        effort: claudeCodeRequestEffort(request32),\n        abortSignal: request32.abort",
      "Claude Code llmclient effort"
    );
  }
  if (!text.includes("case CLAUDE_CODE_PACKAGE:")) {
    text = replaceOnce(
      text,
      "switch (model8.api.npm) {\n",
      "switch (model8.api.npm) {\n    case CLAUDE_CODE_PACKAGE:\n      return Object.fromEntries(CLAUDE_CODE_EFFORTS.map((effort) => [effort, { effort }]));\n",
      "Claude Code reasoning effort variants"
    );
  }
  if (!text.includes("claudeCodeRouteEffort")) {
    text = replaceOnce(
      text,
      "    return exports_Effect.succeed(route2.with({\n      provider: CLAUDE_CODE_PROVIDER_ID,\n      endpoint: { baseURL: \"http://localhost\" },\n      limits: { context: resolved.limit.context, output: resolved.limit.output }\n    }).model({ id: resolved.api.id }));",
      "    const claudeCodeRouteEffort = claudeCodeNormalizeEffort(resolved.request.body?.effort);\n    return exports_Effect.succeed(route2.with({\n      provider: CLAUDE_CODE_PROVIDER_ID,\n      endpoint: { baseURL: \"http://localhost\" },\n      providerOptions: claudeCodeRouteEffort ? { [CLAUDE_CODE_PROVIDER_ID]: { effort: claudeCodeRouteEffort } } : void 0,\n      limits: { context: resolved.limit.context, output: resolved.limit.output }\n    }).model({ id: resolved.api.id }));",
      "Claude Code route effort"
    );
  }
  return text;
}

function patchRateLimitRunner(text) {
  if (text.includes("rateLimitFallbackEnabled")) return text;
  text = insertBefore(
    text,
    '    const runTurnAttempt = exports_Effect.fn("SessionRunner.runTurn")(function* (sessionID, promotion, recoverOverflow) {',
    '    const modelKey = (ref2) => `${ref2.providerID}/${ref2.id}`;\n    const llmModelKey = (model8) => `${model8.provider}/${model8.id}`;\n    const isRateLimitText = (value4) => {\n      const text82 = typeof value4 === "string" ? value4 : value4 === void 0 || value4 === null ? "" : String(value4);\n      const lower3 = text82.toLowerCase();\n      return lower3.includes("rate limit") || lower3.includes("ratelimit") || lower3.includes("too many requests") || lower3.includes("quota") || lower3.includes("usage limit");\n    };\n    const isRateLimitFailure = (failure2) => {\n      if (!(failure2 instanceof LLMError))\n        return false;\n      const reason = failure2.reason;\n      return reason?._tag === "RateLimit" || reason?._tag === "QuotaExceeded" || isRateLimitText(reason?.message);\n    };\n    const isRateLimitProviderError = (event) => event !== void 0 && event.type === "provider-error" && isRateLimitText(event.message);\n    const rateLimitFallbackEnabled = () => {\n      const settingsPath = process.env.OPENCODE_DESKTOP_SETTINGS_PATH;\n      if (!settingsPath)\n        return true;\n      try {\n        const desktopStore = JSON.parse(fs10__default.readFileSync(settingsPath, "utf8"));\n        const rawSettings = desktopStore?.["settings.v3"];\n        const settings = typeof rawSettings === "string" ? JSON.parse(rawSettings) : rawSettings;\n        return settings?.general?.rateLimitModelFallback !== false;\n      } catch {\n        return true;\n      }\n    };\n    const configuredFallbackModels = exports_Effect.fnUntraced(function* () {\n      const configured = exports_config3.latest(yield* config62.entries(), "model_fallback");\n      if (configured === void 0)\n        return { configured: false, refs: [] };\n      const result5 = [];\n      const seen = /* @__PURE__ */ new Set();\n      for (const item2 of configured) {\n        if (typeof item2 !== "string")\n          continue;\n        const candidate = item2.trim();\n        if (candidate.length === 0 || seen.has(candidate))\n          continue;\n        let parsed;\n        try {\n          parsed = exports_model.parse(candidate);\n        } catch {\n          continue;\n        }\n        seen.add(candidate);\n        result5.push({ id: parsed.modelID, providerID: parsed.providerID });\n      }\n      return { configured: true, refs: result5 };\n    });\n    const fallbackCandidates = exports_Effect.fnUntraced(function* (model8) {\n      const configured = yield* configuredFallbackModels();\n      if (configured.configured)\n        return configured.refs;\n      const ranked = yield* models.ranked();\n      const currentKey = llmModelKey(model8);\n      const currentIndex = ranked.findIndex((ref2) => modelKey(ref2) === currentKey || `${ref2.providerID}/${ref2.apiID ?? ref2.id}` === currentKey);\n      return currentIndex >= 0 ? ranked.slice(currentIndex + 1) : ranked;\n    });\n    const switchToFallbackModel = exports_Effect.fnUntraced(function* (session2, model8, limitedModels) {\n      if (!rateLimitFallbackEnabled())\n        return false;\n      const currentKey = llmModelKey(model8);\n      limitedModels.add(currentKey);\n      for (const candidate of yield* fallbackCandidates(model8)) {\n        const fallback = {\n          id: candidate.id,\n          providerID: candidate.providerID,\n          ...session2.model?.variant === void 0 ? {} : { variant: session2.model.variant }\n        };\n        const fallbackKey = modelKey(fallback);\n        const fallbackApiKey = `${candidate.providerID}/${candidate.apiID ?? candidate.id}`;\n        if (fallbackKey === currentKey || fallbackApiKey === currentKey || limitedModels.has(fallbackKey) || limitedModels.has(fallbackApiKey))\n          continue;\n        const resolved = yield* models.resolve({ ...session2, model: fallback }).pipe(exports_Effect.option);\n        if (!exports_Option.isSome(resolved))\n          continue;\n        yield* exports_Effect.logInfo("switching model after rate limit", {\n          sessionID: session2.id,\n          from: currentKey,\n          to: fallbackKey\n        });\n        yield* events2.publish(exports_event2.ModelSwitched, {\n          sessionID: session2.id,\n          messageID: exports_message.ID.create(),\n          timestamp: yield* exports_DateTime.now,\n          model: fallback\n        });\n        return true;\n      }\n      return false;\n    });\n',
    "switchToFallbackModel",
    "rate limit fallback helpers"
  );
  text = replaceOnce(
    text,
    '    const runTurnAttempt = exports_Effect.fn("SessionRunner.runTurn")(function* (sessionID, promotion, recoverOverflow) {',
    '    const runTurnAttempt = exports_Effect.fn("SessionRunner.runTurn")(function* (sessionID, promotion, recoverOverflow, limitedModels = /* @__PURE__ */ new Set()) {',
    "runTurn limited model set"
  );
  text = replaceOnce(
    text,
    "      let overflowFailure;\n",
    "      let overflowFailure;\n      let rateLimitProviderError;\n",
    "rate limit provider error state"
  );
  text = replaceOnce(
    text,
    '        if (LLMEvent.is.providerError(event)) {\n          if (isContextOverflowFailure(event) && !publisher.hasAssistantStarted()) {\n            overflowFailure = event;\n            return;\n          }\n        }\n',
    '        if (LLMEvent.is.providerError(event)) {\n          if (isContextOverflowFailure(event) && !publisher.hasAssistantStarted()) {\n            overflowFailure = event;\n            return;\n          }\n          if (isRateLimitProviderError(event) && !publisher.hasAssistantStarted()) {\n            rateLimitProviderError = event;\n            return;\n          }\n        }\n',
    "rate limit provider error capture"
  );
  text = replaceOnce(
    text,
    '        if (recoverOverflow && !publisher.hasAssistantStarted() && isContextOverflowFailure(overflowFailure ?? failure2) && (yield* restore(recoverOverflow({ sessionID: session2.id, entries: entries5, model: model8, request: request72 }))))\n          return yield* exports_Effect.die(continueAfterOverflowCompaction);\n        if (overflowFailure)\n',
    '        if (recoverOverflow && !publisher.hasAssistantStarted() && isContextOverflowFailure(overflowFailure ?? failure2) && (yield* restore(recoverOverflow({ sessionID: session2.id, entries: entries5, model: model8, request: request72 }))))\n          return yield* exports_Effect.die(continueAfterOverflowCompaction);\n        const llmFailure = failure2 instanceof LLMError ? failure2 : void 0;\n        if (!publisher.hasAssistantStarted() && (isRateLimitProviderError(rateLimitProviderError) || isRateLimitFailure(llmFailure)) && (yield* switchToFallbackModel(session2, model8, limitedModels)))\n          return yield* exports_Effect.die(rebuildPreparedTurn());\n        if (overflowFailure)\n',
    "rate limit fallback before publish"
  );
  text = text.replace('        const llmFailure = failure2 instanceof LLMError ? failure2 : void 0;\n        if (llmFailure && !publisher.hasProviderError()) {', '        if (llmFailure && !publisher.hasProviderError()) {');
  text = replaceOnce(
    text,
    '        return yield* runTurnAttempt(sessionID, promotion).pipe(exports_Effect.catchDefect(exports_Effect.fnUntraced(function* (defect) {',
    '        return yield* runTurnAttempt(sessionID, promotion, void 0, limitedModels).pipe(exports_Effect.catchDefect(exports_Effect.fnUntraced(function* (defect) {',
    "post-compaction limited model set"
  );
  text = replaceOnce(
    text,
    '    const runAfterOverflowCompaction = exports_Effect.fnUntraced(function* (sessionID, promotion) {',
    '    const runAfterOverflowCompaction = exports_Effect.fnUntraced(function* (sessionID, promotion, limitedModels) {',
    "post-compaction signature"
  );
  text = replaceOnce(
    text,
    '        if (defect.transition._tag === "ContinueAfterOverflowCompaction")\n          return yield* exports_Effect.die("Post-compaction provider attempt cannot recover another overflow");\n        yield* exports_Effect.yieldNow;\n        return yield* runAfterOverflowCompaction(sessionID, defect.transition.promotion);\n',
    '        if (defect.transition._tag === "ContinueAfterOverflowCompaction")\n          return yield* exports_Effect.die("Post-compaction provider attempt cannot recover another overflow");\n        yield* exports_Effect.yieldNow;\n        return yield* runAfterOverflowCompaction(sessionID, defect.transition.promotion, limitedModels);\n',
    "post-compaction recursive limited model set"
  );
  text = replaceOnce(
    text,
    '    const runTurn = exports_Effect.fnUntraced(function* (sessionID, promotion) {\n      return yield* runTurnAttempt(sessionID, promotion, compaction.compactAfterOverflow).pipe(exports_Effect.catchDefect(exports_Effect.fnUntraced(function* (defect) {',
    '    const runTurn = exports_Effect.fnUntraced(function* (sessionID, promotion, limitedModels = /* @__PURE__ */ new Set()) {\n      return yield* runTurnAttempt(sessionID, promotion, compaction.compactAfterOverflow, limitedModels).pipe(exports_Effect.catchDefect(exports_Effect.fnUntraced(function* (defect) {',
    "runTurn limited model set"
  );
  text = replaceOnce(
    text,
    '        if (defect.transition._tag === "ContinueAfterOverflowCompaction")\n          return yield* runAfterOverflowCompaction(sessionID, void 0);\n        return yield* runTurn(sessionID, defect.transition.promotion);\n',
    '        if (defect.transition._tag === "ContinueAfterOverflowCompaction")\n          return yield* runAfterOverflowCompaction(sessionID, void 0, limitedModels);\n        return yield* runTurn(sessionID, defect.transition.promotion, limitedModels);\n',
    "runTurn recursive limited model set"
  );
  return text;
}

function patchNodeChunk(file) {
  let text = read(file);
  text = patchModelSchemas(text);
  text = patchRanking(text);
  text = patchClaudeCodeIntegration(text);
  text = patchRateLimitRunner(text);
  write(file, text);
}

function patchComposer(file) {
  let text = read(file);
  text = insertAfter(
    text,
    'import { Z as PopperArrow,',
    '',
    "import { S as ToggleSwitch } from",
    "noop"
  );
  if (!text.includes('import { S as ToggleSwitch } from "./switch-GFnEuUQr.js";')) {
    text = text.replace(
      'import { T as Tabs, S as Select } from "./select-BSIwtcEB.js";',
      'import { S as ToggleSwitch } from "./switch-GFnEuUQr.js";\nimport { T as Tabs, S as Select } from "./select-BSIwtcEB.js";'
    );
  }
  text = insertAfter(
    text,
    '_tmpl$19 = /* @__PURE__ */ template(`<div class=relative><div class="pointer-events-none absolute left-2 top-1/2 z-10 flex size-4 -translate-y-1/2 items-center justify-center text-v2-icon-icon-muted">`)',
    ', _tmpl$rateLimitFallbackToggle = /* @__PURE__ */ template(`<div data-action=prompt-rate-limit-fallback class="flex h-7 shrink-0 items-center gap-2 rounded px-2 text-[13px] font-[440] leading-5 text-v2-text-text-faint hover:bg-v2-overlay-simple-overlay-hover focus-within:bg-v2-overlay-simple-overlay-hover"><span class=truncate>`)',
    "_tmpl$rateLimitFallbackToggle",
    "rate limit toggle template"
  );
  text = insertAfter(
    text,
    "  const platform = usePlatform();\n",
    "  const settings = useSettings();\n",
    "const settings = useSettings();",
    "composer settings hook"
  );
  text = insertAfter(
    text,
    '  const newProjectTriggerState = createMemo(() => ({\n    action: "prompt-project",\n    icon: "folder-add-left",\n    label: language.t("session.new.project.new"),\n    class: "max-w-[160px]",\n    style: control(),\n    onPress: () => void addProject()\n  }));\n',
    '  const rateLimitFallbackToggle = () => createComponent(RateLimitFallbackToggle, {\n    label: "Auto-switch",\n    style: control,\n    checked: () => settings.general.rateLimitModelFallback(),\n    onChange: (checked) => {\n      settings.general.setRateLimitModelFallback(checked);\n    }\n  });\n',
    "const rateLimitFallbackToggle",
    "composer toggle factory"
  );
  text = insertAfter(
    text,
    '                  insert(_el$12, createComponent(ComposerModelControl, {\n                    get state() {\n                      return modelControlState();\n                    }\n                  }), null);\n',
    '                  insert(_el$12, rateLimitFallbackToggle, null);\n',
    "insert(_el$12, rateLimitFallbackToggle",
    "new layout toggle insertion"
  );
  text = insertBefore(
    text,
    '                    createRenderEffect((_$p) => style(_el$27, {\n',
    '                    insert(_el$30, rateLimitFallbackToggle, null);\n',
    "insert(_el$30, rateLimitFallbackToggle",
    "old layout toggle insertion"
  );
  text = insertBefore(
    text,
    "function ComposerPickerTrigger(props) {\n",
    'function RateLimitFallbackToggle(props) {\n  return (() => {\n    var _el$36 = _tmpl$rateLimitFallbackToggle(), _el$37 = _el$36.firstChild;\n    insert(_el$37, () => props.label);\n    insert(_el$36, createComponent(Tooltip, {\n      placement: "top",\n      value: "Switch model on rate limit",\n      get children() {\n        return createComponent(ToggleSwitch, {\n          hideLabel: true,\n          "class": "flex items-center",\n          get checked() {\n            return props.checked();\n          },\n          get onChange() {\n            return props.onChange;\n          },\n          get children() {\n            return props.label;\n          }\n        });\n      }\n    }), null);\n    createRenderEffect(() => setAttribute(_el$36, "aria-label", props.label));\n    createRenderEffect((_$p) => style(_el$36, props.style?.() ?? void 0, _$p));\n    return _el$36;\n  })();\n}\n',
    "function RateLimitFallbackToggle",
    "toggle component"
  );
  write(file, text);
}

const files = walk(root).filter((file) => file.endsWith(".js"));
const mainIndex = path.join(root, "out/main/index.js");
if (!fs.existsSync(mainIndex)) throw new Error("out/main/index.js not found");

const nodeChunk = mustFind(
  files,
  (file) => /\/out\/main\/chunks\/node-[^/]+\.js$/.test(file) && read(file).includes("SessionRunner.runTurn") && read(file).includes("SessionRunnerModel.resolve"),
  "main node chunk"
);

const rendererMain = mustFind(
  files,
  (file) => /\/out\/renderer\/assets\/main-[^/]+\.js$/.test(file) && read(file).includes("const defaultSettings =") && read(file).includes('persisted("settings.v3"'),
  "renderer main asset"
);

const composer = mustFind(
  files,
  (file) => /\/out\/renderer\/assets\/session-composer-state-[^/]+\.js$/.test(file) && read(file).includes("const PromptInput ="),
  "session composer asset"
);

patchMainIndex(mainIndex);
patchNodeChunk(nodeChunk);
patchRendererSettings(rendererMain);
patchComposer(composer);

for (const file of touched) {
  const result = spawnSync(process.execPath, ["--check", file], { encoding: "utf8" });
  if (result.status !== 0) {
    process.stderr.write(result.stdout || "");
    process.stderr.write(result.stderr || "");
    throw new Error(`node --check failed for ${rel(file)}`);
  }
}

console.log(`Patched files:\n${[...touched].map((file) => `- ${rel(file)}`).join("\n")}`);
NODE

echo "Extracting app.asar..."
npm exec --yes @electron/asar -- extract "$ASAR" "$WORK/app"

echo "Applying patches..."
node "$PATCHER" "$WORK/app"

echo "Packing patched app.asar..."
npm exec --yes @electron/asar -- pack "$WORK/app" "$PATCHED_ASAR"
HASH="$(shasum -a 256 "$PATCHED_ASAR" | awk '{print $1}')"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "Dry run OK. Patched ASAR hash would be: $HASH"
  exit 0
fi

BACKUP="$RESOURCES/app.asar.bak-repatch-$STAMP"
echo "Backing up current ASAR to $BACKUP"
cp "$ASAR" "$BACKUP"

echo "Stopping OpenCode if it is running..."
osascript -e 'tell application id "ai.opencode.desktop" to quit' >/dev/null 2>&1 || true
sleep 2
while pgrep -f "$APP/Contents/MacOS/OpenCode|OpenCode Helper|ai.opencode.desktop" >/dev/null 2>&1; do
  pkill -TERM -f "$APP/Contents/MacOS/OpenCode|OpenCode Helper|ai.opencode.desktop" >/dev/null 2>&1 || true
  sleep 1
  if pgrep -f "$APP/Contents/MacOS/OpenCode|OpenCode Helper|ai.opencode.desktop" >/dev/null 2>&1; then
    pkill -KILL -f "$APP/Contents/MacOS/OpenCode|OpenCode Helper|ai.opencode.desktop" >/dev/null 2>&1 || true
    sleep 1
  fi
done

echo "Installing patched ASAR..."
cp "$PATCHED_ASAR" "$ASAR"

echo "Updating ElectronAsarIntegrity..."
/usr/libexec/PlistBuddy -c "Set :ElectronAsarIntegrity:Resources/app.asar:hash $HASH" "$PLIST"

echo "Removing quarantine/provenance attributes..."
xattr -dr com.apple.quarantine "$APP" >/dev/null 2>&1 || true
xattr -dr com.apple.provenance "$APP" >/dev/null 2>&1 || true

echo "Signing app container locally..."
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP" >/dev/null

echo "Launching OpenCode..."
env -i HOME="$HOME" USER="${USER:-}" LOGNAME="${LOGNAME:-${USER:-}}" PATH="/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="${TMPDIR:-/tmp}" open "$APP"

echo "Done."
echo "Backup: $BACKUP"
echo "ASAR SHA-256: $HASH"
