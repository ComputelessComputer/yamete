# Yamete

https://github.com/user-attachments/assets/a0a9cb8c-75cd-406c-8d48-b028a88f0230

Yamete is a native macOS menu bar app that reacts to physical taps on your Mac with spoken responses. This rewrite uses the undocumented Apple SPU accelerometer and gyroscope path described in [olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer), but implements the sensor backend natively in Swift instead of shelling out to `spank`.

## Features

- Native SwiftUI macOS menu bar app
- Native Apple SPU motion backend using IOKit HID callbacks
- Live acceleration, gyroscope, dynamic impact, and orientation telemetry
- Speech-based response engine with multiple sound packs (Pain, Flirty, Chaos, Goat, Claude)
- Combo escalation system with tier-based responses
- **Claude Code whipping** — slapping your laptop sends Ctrl+C and an encouraging message to Claude Code. If Claude Code isn't running, opens Ghostty and launches it.
- Adjustable impact threshold, cooldown, and live sample rate
- Optional screen flash on impact
- Demo mode for testing without hardware detection

## Requirements

- macOS 14 or later
- Apple Silicon Mac with the Apple SPU IMU exposed by `AppleSPUHIDDevice`
- Root privileges for live sensor access
- Accessibility permissions required for Claude Code whipping (System Settings → Privacy → Accessibility)

## Install

Download the latest DMG from this repository's Releases page, open it, then drag `Yamete.app` into `Applications`.

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

Yamete now talks directly to the Apple SPU HID devices that surface the accelerometer and gyroscope on supported Apple Silicon MacBook hardware. The implementation follows the same report path documented by [olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer):

- Wake `AppleSPUHIDDriver` by setting the reporting and power properties.
- Open the `AppleSPUHIDDevice` accelerometer and gyroscope endpoints through IOKit HID.
- Read the 22-byte reports, decode the three-axis `Int32` payload at offsets `6/10/14`, and scale by `65536`.
- High-pass the accelerometer stream to isolate impact energy, then fuse accel + gyro into orientation with a Mahony filter.

Because that HID path requires elevated privileges, Yamete will only stream live impacts when the executable is launched with root access. On unsupported hardware or without root, the app stays usable in preview mode and the `Preview Test Slap` button continues to drive the full response path.

## Notes

- This backend is Apple-private and undocumented. It may break across macOS updates.
- The rewrite deliberately drops the old `spank` dependency and release bundling path.
- The upstream reference repository is public here: [olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer?tab=readme-ov-file).
