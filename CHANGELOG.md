# Changelog

## 0.1.1-alpha.1

The bundle reports version 0.1.1, build 2.

- Prevent two copies of this version from adding separate menu bar icons, including launches from different paths. An already running 0.1.0 copy must be quit before upgrading.
- Add an English interface alongside Russian and a custom Finder icon.
- Add an animated illustration of the menu bar toggle.
- Document the Gatekeeper limitation of the published alpha download.

## 0.1.0-alpha.1

First public test release. The bundle reports version 0.1.0, build 1.

### Added

- Native Swift/AppKit menu bar toggle for the system grayscale filter.
- Left-click switching, right-click menu and explicit error messages.
- Protection against replacing another active accessibility color filter.
- Controller, programmatic AppKit and opt-in native integration tests.
- Universal arm64/x86_64 build script, English/Russian documentation and build CI.

### Known limitations

- Undocumented APIs; no promise of future macOS compatibility.
- Ad-hoc signing only, no Apple notarization.
- Local runtime verified on Apple Silicon/macOS 15.6; Intel and other versions not yet physically tested.
- No Windows/Linux version, auto-start, updater or global keyboard shortcut.
- Quitting leaves the current system filter unchanged.
