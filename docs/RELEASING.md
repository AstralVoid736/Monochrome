# Release checklist

Publishing is a maintainer action, not an automatic side effect of CI.

1. Choose a version and update the changelog. Keep the release tag and bundle version relationship explicit.
2. Run `bash scripts/test.sh` and `bash scripts/build.sh --universal` on a trusted Mac.
3. For native behavior changes, separately perform an opted-in real-display test and human observation. Do not reuse an old runtime result for changed code.
4. Verify the exact app with `codesign --verify --strict dist/Monochrome.app` and inspect architectures with `xcrun lipo -archs dist/Monochrome.app/Contents/MacOS/Monochrome`.
5. Package only the application, user-facing docs and license. Do not include work logs, machine paths, task state, fetched snapshots or credentials.
6. Generate SHA-256 checksums, reopen the ZIP, verify its exact entries and signature after extraction.
7. Confirm the public commit and its GitHub Actions run. Tag that exact commit.
8. Create an explicit **prerelease** for alpha software, with signing/API/compatibility caveats and no unsupported platform claims.
9. Read back repository visibility, commit, tag and release; download the assets and compare hashes. A successful upload command is not verification.

Developer ID signing and notarization require a separately configured Apple developer workflow. See the [signing and notarization checklist](SIGNING.md). Never commit signing keys or disable Gatekeeper as a workaround.
