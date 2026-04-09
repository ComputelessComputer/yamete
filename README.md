# Yamete

https://github.com/user-attachments/assets/a0a9cb8c-75cd-406c-8d48-b028a88f0230

Yamete is a native macOS menu bar app that listens to the Apple SPU motion sensors on supported Apple Silicon MacBooks and reacts to physical taps with audio and visual feedback. The sensor path follows the undocumented work in [olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer), but Yamete implements the backend directly in Swift instead of shelling out to external tools.

## What It Does

- Runs as a lightweight SwiftUI menu bar app with no Dock icon
- Reads the Apple SPU accelerometer and gyroscope through IOKit HID callbacks
- Detects impacts and plays one of the bundled voice clips
- Flashes the screen briefly on each detected impact
- Persists total smack counts between launches
- Checks GitHub Releases for updates and can install a newer DMG in place

The current menu UI is intentionally small: counts, update check, reset, and quit.

## Requirements

- macOS 14 or later
- A supported Apple Silicon MacBook that exposes `AppleSPUHIDDevice`
- Root privileges for live sensor capture

If the app is launched without root, it can still start, but it will not stream live SPU motion data.

## Install

Download the latest DMG from the repository's Releases page, open it, and drag `Yamete.app` into `/Applications`.

If you want live impact detection from the installed app, launch the bundled executable from a root shell:

```bash
sudo /Applications/Yamete.app/Contents/MacOS/yamete
```

Launching Yamete normally from Finder will not grant the root access required for the Apple SPU HID devices.

## Development

Build locally:

```bash
swift build
```

Run the app from SwiftPM:

```bash
swift run yamete
```

Run with live sensor access on supported hardware:

```bash
sudo swift run yamete
```

Build local release assets:

```bash
./scripts/build-release-assets.sh v0.1.0 ./dist
```

That script builds a universal binary, wraps it in `Yamete.app`, creates a DMG, and writes a SHA-256 checksum next to it.

Pushing a `v*` tag triggers the GitHub Actions release workflow, which signs, notarizes, and publishes the DMG.

## Detection Backend

Yamete talks directly to the Apple SPU HID devices that surface the accelerometer and gyroscope on supported Apple Silicon MacBook hardware. The current implementation:

- Wakes `AppleSPUHIDDriver` by setting the reporting and power properties
- Opens the `AppleSPUHIDDevice` accelerometer and gyroscope endpoints through IOKit HID
- Reads the 22-byte reports, decodes the three-axis `Int32` payload at offsets `6`, `10`, and `14`, and scales by `65536`
- High-pass filters the accelerometer stream to isolate impact energy, then fuses accel and gyro data into orientation using a Mahony filter

## Notes

- This backend is Apple-private and undocumented, so it may break across macOS updates.
- Yamete targets compatible Apple Silicon MacBook hardware, not every Apple Silicon Mac.
- The older `spank`-based approach is gone. The motion backend is now native Swift.
- The upstream reference repository is here: [olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer?tab=readme-ov-file).
