# Edgelit

Soft light along the edges of your Mac's screen that moves with your music and lights up for notifications and calls. It lives in the menu bar, stays out of the way, and you choose the colours and the animations.

- **Music:** reacts to whatever your Mac is playing (Spotify, Apple Music, YouTube, anything). Three animations: **Pulse**, **Flow**, **Segments**.
- **Notifications and calls:** a glow when a banner appears, in the app's own colour or one you pick. Calls keep glowing until they end. Three animations: **Pulse**, **Sweep**, **Blink**.
- **Minimal by default:** a thin, even strip of light that never covers the middle of the screen, and the click-through overlay never gets in your way.
- **Yours to edit:** menu bar icon ▸ **Customise…** for colours (presets or up to three of your own), animation types, thickness and brightness. Changes show live.
- **Private:** no network access, no accounts. Audio is turned into a few loudness numbers and thrown away; nothing is recorded or saved.

## What works, and how well

| Feature | Status |
|---|---|
| Edge glow, all animations, colours, settings window | Built and unit-tested; rendering checked as images |
| Music reaction | Uses macOS screen-capture audio (needs the **Screen Recording** permission). **Not yet tried on a real Mac with real music** |
| Notification and call glow | Experimental. macOS has no official way to read other apps' notifications, so Edgelit watches the Notification Center banner through the **Accessibility** API. It may need adjusting on some macOS versions. **Not yet tried on real notifications** |
| Try buttons (menu ▸ Try it) | Show every animation without needing music or a real notification |

## Install

Requires macOS 13 or later.

1. Build it (below) or download the DMG from Releases when one is published.
2. Open **Edgelit**; a small rays icon appears in the menu bar.
3. Menu ▸ **Allow Screen Recording** for music, and **Allow Accessibility** for notifications and calls. Switch Edgelit on in the System Settings page that opens. You may need to quit and reopen Edgelit once after allowing Screen Recording.

The app is ad-hoc signed, so on first launch macOS may ask you to confirm in **System Settings ▸ Privacy & Security ▸ Open Anyway**.

## Trigger it yourself

Other tools can light the edges through links:

```sh
open "edgelit://notify?app=Slack"   # a notification glow
open "edgelit://call"                # a call glow, until cleared
open "edgelit://clear"               # end the call glow
open "edgelit://music-demo"          # 10 seconds of made-up beat
```

## Build from source

```sh
swift build           # debug
swift test            # unit tests
./scripts/build.sh    # dist/Edgelit.app
./scripts/make_dmg.sh # dist/Edgelit.dmg
```

`dist/Edgelit.app` ▸ `Edgelit --preview <folder>` writes sample frames as PNGs; `--bench` times the renderer.

## How it works

```
Sources/EdgelitCore/   no windows: spectrum analysis (FFT), smoothing, colours, the glow renderer
Sources/Edgelit/       the app: overlay windows, audio capture, notification watcher, settings window
```

The glow is drawn small and stretched by the GPU, so a frame costs about 1 to 3 ms and the overlay sleeps completely when nothing is happening.

## License

MIT. See [LICENSE](LICENSE).
