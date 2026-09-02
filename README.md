# Floater

Floater is a personal macOS menu-bar music controller that extends the MacBook
notch into a compact Spotify-focused interface.

This repository is the source of truth for the installed Floater app on this
Mac. It is intentionally private and does not provide an automatic updater.

## Current behavior

- Spotify now-playing artwork, title, artist, progress, and playback controls.
- Smooth hover, peek, open, and close notch interactions.
- Album-art-tinted progress and waveform presentation.
- Bluetooth connection activity for paired audio devices.
- Music-only settings: General, Appearance, Media, and About.
- Launch-at-login support for the installed app.

Calendar, battery, HUD replacement, shelf, webcam, and global shortcut
integrations are disabled so they cannot be enabled accidentally.

## Running Floater

The installed app lives at `/Applications/Floater.app`. Launch it from
Spotlight by searching for **Floater**. To start it automatically after login,
open Floater's menu-bar settings and enable **Launch at login**.

For development, open `boringNotch.xcodeproj` in Xcode and run the
`boringNotch` scheme. The produced app is named `Floater.app`.

## Project structure

- `boringNotch/` — the Floater macOS app source and assets.
- `BoringNotchXPCHelper/` — the embedded helper used for required macOS
  accessibility operations.
- `mediaremote-adapter/` — media-control adapter framework source.
- `THIRD_PARTY_LICENSES` — notices for bundled dependencies.

## Maintenance

Automatic upstream Boring Notch updates are deliberately disabled. If a future
macOS update exposes a real compatibility issue, create a Git commit first,
then review and selectively apply only the required upstream fix. Do not replace
this app with a stock Boring Notch binary.

## License and attribution

Floater is a modified personal fork of Boring Notch and remains licensed under
the GNU General Public License v3.0. See [LICENSE](LICENSE),
[NOTICE.md](NOTICE.md), and [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES).
