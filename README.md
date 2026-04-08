# Yamete

Yamete is a native macOS menu bar app that reacts to physical taps on your laptop with spoken responses. Slap your laptop and it moans. Slap it while Claude Code is running and it whips Claude into working faster.

## Features

- Native SwiftUI macOS menu bar app
- Real impact detection via `spank` accelerometer bridge
- Speech-based response engine with multiple sound packs (Pain, Flirty, Chaos, Goat, Claude)
- Combo escalation system with tier-based responses
- **Claude Code whipping** — slapping your laptop sends Ctrl+C and an encouraging message to Claude Code. If Claude Code isn't running, opens Ghostty and launches it.
- Adjustable amplitude threshold and cooldown
- Optional screen flash on impact
- Demo mode for testing without hardware detection

## Requirements

- macOS 14 or later
- Apple Silicon or Intel
- `spank` is optional and only needed for hardware-backed slap detection
- Accessibility permissions required for Claude Code whipping (System Settings → Privacy → Accessibility)

## Install

Download the latest DMG from [Releases](https://github.com/ComputelessComputer/openmoan/releases), open it, then drag `Yamete.app` into `Applications`.

## Development

Build locally:

```bash
swift build
```

Run a release-style package build locally:

```bash
./scripts/build-release-assets.sh v0.1.0 ./dist
```

That script builds a universal binary, wraps it in `Yamete.app`, creates a DMG, and writes a SHA-256 checksum beside it.

## Detection Backend

Yamete first looks for a bundled `spank` binary inside the app, then falls back to an installed `spank` CLI on the machine. If neither is available or the detector cannot run, the app falls back to demo mode and the `Preview Test Slap` button drives the response path.

`./scripts/build-release-assets.sh` will bundle `spank` automatically when it is already installed on the release machine. You can also point it at a specific detector binary with `SPANK_BINARY=/path/to/spank ./scripts/build-release-assets.sh <tag> <output-dir>`.
