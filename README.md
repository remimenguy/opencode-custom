# opencode-custom

Patched macOS `OpenCode.app` bundle with rate-limit model fallback changes.

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
git clone https://github.com/remimenguy/opencode-custom.git
```

If the repository is already cloned:

```sh
git lfs pull
```

## Reapply The Patch

The patch script is:

```sh
./repatch-opencode-rate-limit-fallback.sh
```

It extracts `Resources/app.asar`, patches the OpenCode JavaScript bundles,
updates `ElectronAsarIntegrity`, removes quarantine/provenance attributes,
locally signs the app, verifies the signature, and relaunches OpenCode.

Run a dry run first:

```sh
./repatch-opencode-rate-limit-fallback.sh --dry-run
```

Patch the default app:

```sh
./repatch-opencode-rate-limit-fallback.sh
```

Patch a specific app bundle:

```sh
./repatch-opencode-rate-limit-fallback.sh /Applications/OpenCode.app
```

## Requirements

- macOS
- `node`
- `npm`
- `/usr/bin/codesign`
- `/usr/libexec/PlistBuddy`

The script uses `npm exec --yes @electron/asar` to extract and repack
`app.asar`.

## Backups

Before replacing `Resources/app.asar`, the script writes a timestamped backup:

```sh
Resources/app.asar.bak-repatch-YYYYMMDDHHMMSS
```

Keep the latest working backup until the patched app has been verified.
