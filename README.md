# Ostrovok

A native macOS app that lives in the MacBook notch: catch a thought in two seconds, run a focus timer around the notch, and browse your thoughts in a library. Everything stays local — no cloud, no accounts.

## Build

```sh
brew install xcodegen
xcodegen generate
open Ostrovok.xcodeproj   # ⌘R
```

Requires macOS 14+. Signed locally (ad-hoc).

## Shortcuts

| | |
|---|---|
| `⌃⌥Space` | Catch a thought |
| `⌃⌥F` | Start / pause focus |
| `⌃⌥L` | Library |

All shortcuts can be changed in Settings.

## Notch states

S0 idle · S1 focus in the wings · S2 peek (hover ≥150 ms) · S3 panel (click) · S5 "Saved" with ⌘Z · S6 focus done · S7 break.

## Design

White accent, dark surfaces, restrained glass input. Native SwiftUI takes on three interaction patterns:

- **Border glow** on thought cards — a mesh-gradient rim that follows the cursor and intensifies near the edges; the newest card sweeps once.
- **Animated list** in the library and calendar — rows spring into view, a gliding selection follows hover and arrow keys, edges fade out.
- **Gooey nav** for filters and the Recent / Calendar switch — the active pill flows to the new item with a droplet burst.

Icons animate on hover and press; the sparkle in the input breathes when empty and bursts when you start typing.

## Data

`~/Library/Application Support/Ostrovok/` — SwiftData store and images. Export everything to Markdown from Settings.

## Debugging

- "Emulate notch" in Settings for displays without a notch.
- Debug builds with `OSTROVOK_SNAPSHOT_DIR=<dir>` render every notch state to PNG; `OSTROVOK_DATA_DIR=<dir>` uses a separate store.

## Tests

```sh
xcodebuild -scheme Ostrovok -destination 'platform=macOS' test
```
