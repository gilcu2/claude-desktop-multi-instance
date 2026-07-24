## 1.1.0 - 2026-07-24

### Added

- Add optional `[badge-color-hex]` and `[tint-strength]` arguments to `setup-claude.sh`, so the badge circle can use a color independent of the icon tint, and cool tints (blue/green) can be blended stronger to read clearly against the stock icon's warm background.
- Add a newsfragment-based changelog system: drop a file in `newsfragments/` per change, and `build-changelog.sh <version>` collects them into `CHANGELOG.md`.

### Fixed

- Fix Finder/Dock/taskbar apps showing the same untinted icon for every profile: `Info.plist`'s `CFBundleIconName` (which points at the untouched `Assets.car` asset catalog) was silently overriding our custom `CFBundleIconFile`. `setup-claude.sh` now deletes `CFBundleIconName` after setting the tinted icon.

