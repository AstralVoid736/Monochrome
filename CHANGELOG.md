# Changelog

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
