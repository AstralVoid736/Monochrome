# Acknowledgements and implementation provenance

Monochrome is a new Swift/AppKit implementation. It uses system function names and the documented-in-the-community calling sequence discussed in:

- Brett Gutstein's [grayscale Bridge.h](https://github.com/brettferdosi/grayscale/blob/master/Sources/Bridge.h).
- Sriranga R. Veeraraghavan's [displayutil grayscale implementation](https://github.com/srirangav/displayutil/blob/main/displayutil_grayscale.m).

These references informed the distinction between legacy CoreGraphics forced grayscale and modern MediaAccessibility filters. Their source files are not vendored here. Monochrome does not depend on either project or MASShortcut. The local implementation, tests and docs are covered by this repository's MIT license; that does not relicense the linked upstream projects.

See [implementation notes](docs/IMPLEMENTATION.md) for the specific cited behavior and verification limitations.
