# Prism Drift

[![Build](https://github.com/cayde-6/prism-drift-macos/actions/workflows/build.yml/badge.svg)](https://github.com/cayde-6/prism-drift-macos/actions/workflows/build.yml)

Procedural macOS light-streak visuals built with SwiftUI, MetalKit, and custom Metal shaders.

![Prism Drift preview](Docs/preview.gif)

The repository ships two products:

- `PrismDrift`: a fullscreen preview app for tuning the effect.
- `PrismDriftSaver`: a real `.saver` bundle that can be installed into macOS.

## Highlights

- Fully procedural rendering: no textures, images, or prerecorded assets.
- Shared renderer across the preview app and the screen saver runtime.
- Universal screen saver bundle (`arm64 + x86_64`) for more reliable loading on current macOS releases.

## Requirements

- macOS with Metal support
- Xcode 16 or newer

## Quick Start

```bash
open PrismDrift.xcodeproj
```

Install the screen saver:

```bash
./Scripts/install-saver.sh
```

Export a seamless lock-screen video:

```bash
./Scripts/export-lock-screen-video.sh
```

Prepare that video for the system-managed aerial slot used on the lock screen:

```bash
./Scripts/install-lock-screen-aerial.sh \
  --input Generated/PrismDrift/prism-drift-lockscreen.mov
```

The script prints the final `sudo` command after generating a backup-friendly staged `.mov`.

Preview the active screen saver immediately:

```bash
open -a /System/Library/CoreServices/ScreenSaverEngine.app
```

## Architecture

- `Renderer` owns the Metal device resources, render pipeline, and draw loop.
- `MetalView` is a minimal SwiftUI bridge around `MTKView`.
- `PrismDriftScreenSaverView` embeds the same renderer inside `ScreenSaverView`.
- `VideoExporter` renders an offline seamless HEVC loop directly from the shader.
- `Shaders.metal` contains the procedural fullscreen triangle pass and the diagonal streak fragment shader.

## Project Structure

- [App.swift](App.swift): app entry point and fullscreen preview window setup
- [ContentView.swift](ContentView.swift): minimal SwiftUI container for the Metal canvas
- [MetalView.swift](MetalView.swift): `NSViewRepresentable` bridge around `MTKView`
- [Renderer.swift](Renderer.swift): shared Metal renderer and draw loop
- [VideoExporter.swift](VideoExporter.swift): offline looped video export entry point
- [PrismDriftScreenSaverView.swift](PrismDriftScreenSaverView.swift): `ScreenSaverView` host for the `.saver` bundle
- [Shaders.metal](Shaders.metal): procedural light-streak shader
- [Config/](Config): explicit `Info.plist` files for the app and screen saver bundle
- [Scripts/](Scripts): screen saver install plus optional lock-screen aerial workflow
- [PrismDrift.xcodeproj](PrismDrift.xcodeproj): checked-in Xcode project

## Notes

- `PrismDrift.xcodeproj` is the source of truth and is committed to the repository.
- The install script restarts `legacyScreenSaver`, `WallpaperAgent`, and `ScreenSaverEngine` because current macOS versions may cache an older `.saver` bundle in memory after reinstall.
- `install-lock-screen-aerial.sh` is an unsupported workaround that replaces a system-managed aerial asset under `/Library/Application Support/com.apple.idleassetsd/`.
