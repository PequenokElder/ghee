# Ghee

A low-latency guitar monitor for macOS. Plug a guitar into your audio interface, hit **Heat the Pan**, and hear yourself with about 9 ms round-trip latency, plus a butter-themed tone rack.

| Knob | Real effect |
|---|---|
| Churn | Input gain |
| Soften | Compression (custom, zero-latency) |
| Brown Butter | Drive |
| Stick / Spread / Sizzle | Bass / Mid / Treble EQ |
| Swirl | Chorus (custom, zero-latency) |
| Melt | Reverb |
| Slather | Volume |

## Build and run

Requires macOS 13+ and the Swift toolchain (Xcode or Command Line Tools).

```bash
./build_app.sh
open Ghee.app
```

Copy `Ghee.app` to `/Applications` and launch it from Finder. On first launch macOS asks for microphone access; allow it. If audio fails to start with error -10875, enable Ghee under System Settings › Privacy & Security › Microphone, then relaunch.

## How it keeps latency low

- Requests a small hardware buffer (32–256 samples, default 64) from Core Audio.
- Keeps the signal path short: sum to mono, compressor, drive, EQ, chorus, reverb, out.
- The compressor and chorus are custom Audio Units with no lookahead, so they add no delay. (Apple's built-in compressor adds about 5 ms.)
- The latency readout is an estimate from the device's reported latency, safety offset and buffer size.

## Layout

- `Sources/GuitarMonitor/GuitarEngine.swift` – audio graph and Core Audio device handling
- `Compressor.swift`, `Chorus.swift` – custom Audio Units
- `ContentView.swift`, `Quips.swift` – SwiftUI interface and the butter banter
- `Resources/` – Info.plist, entitlements, app icon (`make_icon.swift` regenerates it)
