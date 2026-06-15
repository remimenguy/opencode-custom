# opencode-custom

Patched macOS `OpenCode.app` bundle with local model fallback and Claude Code
provider integration.

This repository stores the app bundle contents from:

```sh
/Applications/OpenCode.app/Contents
```

Large binary payloads are tracked with Git LFS, including `Resources/app.asar`
and the Electron framework binary.

## Clone

Install Git LFS before cloning or pulling this repository:

```sh
git lfs install
git clone <repository-url>
```

If the repository is already cloned:

```sh
git lfs pull
```

## Included Changes

- Automatic model switch on rate-limit/quota errors.
- The retry keeps the OpenCode conversation context and continues the same turn.
- Default model selection prefers stronger available models, then falls back to
  equivalent or slightly weaker models when needed.
- Prompt input toggle: `Auto-switch`.
- Native-style `claude-code` provider when the local `claude` CLI is installed.

Claude Code models exposed in OpenCode:

```text
claude-code/opus
claude-code/sonnet
claude-code/haiku
```

The Claude Code provider uses the local `claude` command and the account already
configured in Claude Code. It does not require an Anthropic API key. OpenCode
still owns tool execution, file edits, permissions, and conversation state;
Claude Code internal tools are disabled with `--tools ""`.

## Reapply The Patch

The patch script is:

```sh
bash ./repatch-opencode-rate-limit-fallback.sh
```

It extracts `Resources/app.asar`, patches the OpenCode JavaScript bundles,
updates `ElectronAsarIntegrity`, removes quarantine/provenance attributes,
locally signs the app, verifies the signature, and relaunches OpenCode.

Run a dry run first:

```sh
bash ./repatch-opencode-rate-limit-fallback.sh --dry-run
```

Patch the default app:

```sh
bash ./repatch-opencode-rate-limit-fallback.sh
```

Patch a specific app bundle:

```sh
bash ./repatch-opencode-rate-limit-fallback.sh /Applications/OpenCode.app
```

## Requirements

- macOS
- `node`
- `npm`
- `/usr/bin/codesign`
- `/usr/libexec/PlistBuddy`
- Optional for the Claude Code provider: `claude` in `PATH` or
  `CLAUDE_CODE_PATH=/absolute/path/to/claude`

The script uses `npm exec --yes @electron/asar` to extract and repack
`app.asar`.

## Backups

Before replacing `Resources/app.asar`, the script writes a timestamped backup:

```sh
Resources/app.asar.bak-repatch-YYYYMMDDHHMMSS
```

Keep the latest working backup until the patched app has been verified.
