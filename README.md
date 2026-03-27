# OpenMoan

OpenMoan is a native macOS menu bar app that reacts to physical taps on your laptop with spoken responses.

It is modeled after apps like SlapMac, but kept simple: a menu bar UI, a small settings window, impact-triggered audio, combo escalation, and a release flow that ships a downloadable DMG.

## Current State

- Native SwiftUI macOS app
- Menu bar control surface with live slap count and detector status
- Adjustable amplitude threshold and cooldown
- Speech-based response engine with multiple sound packs
- Optional screen flash on impact
- Demo mode for local testing
- Optional `spank` bridge for real accelerometer-backed impact detection

## Requirements

- macOS 14 or later
- Apple Silicon or Intel
- `spank` is optional and only needed for hardware-backed slap detection

## Install

Download the latest DMG from [Releases](https://github.com/ComputelessComputer/openmoan/releases), open it, then drag `OpenMoan.app` into `Applications`.

## Development

Build locally:

```bash
swift build
```

Run a release-style package build locally:

```bash
./scripts/build-release-assets.sh v0.1.0 ./dist
```

That script builds a universal binary, wraps it in `OpenMoan.app`, creates a DMG, and writes a SHA-256 checksum beside it.

## Detection Backend

OpenMoan prefers the `spank` CLI when it is installed and executable on the machine. If `spank` is missing or cannot run, the app falls back to demo mode and the `Test Slap` button drives the response path.

This keeps the app usable while the native hardware detector remains separate from the UI and packaging layer.
