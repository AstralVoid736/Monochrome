# Signing and notarizing Monochrome for macOS

For direct distribution without asking users to override Gatekeeper, use the publisher’s **Developer ID Application** signing identity, enable Hardened Runtime, and notarize the app. After Apple accepts the submitted archive, staple the ticket to the app before making the final ZIP.[1] Ad-hoc signing does not satisfy these requirements.

## Prerequisites and checks

- Install the publisher's Developer ID Application certificate **with its private key** in the local signing keychain. Select the intended identity with `security find-identity -v -p codesigning`.
- Set up an authorized `notarytool` keychain profile locally. Never put credentials in the repo, a command transcript, or a release asset.
- Use a fresh staging directory containing a copy of the tested universal `Monochrome.app`. Do not re-sign a running or installed copy. Check the output still contains `arm64` and `x86_64`.

## Release order

1. Run the tests and build a universal app. Verify the build locally before copying it into the staging directory.
2. With `$APP` pointing to the staged app and `$IDENTITY` set to the selected Developer ID Application identity, sign with `codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"`.
3. Check `codesign --verify --strict "$APP"`. Test switching the real filter with this **Hardened Runtime** build before distributing it; a successful ad-hoc test does not cover that configuration.
4. Archive the signed `.app` with `ditto -c -k --keepParent`, then submit that ZIP with `xcrun notarytool submit "$SUBMISSION_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 20m`. Check the returned status. If the wait times out, look up the same submission ID rather than sending a duplicate.
5. Only if the submission status is `Accepted`, run `xcrun stapler staple "$APP"`, `xcrun stapler validate "$APP"` and `codesign --verify --strict "$APP"`. Package the **stapled app** in a new final ZIP; don't ship the ZIP from step 4.
6. Unpack the final ZIP in a clean staging directory. Verify its signature and ticket, run `syspolicy_check distribution` where available, and test a fresh Finder launch with Gatekeeper enabled. Generate the checksum from that ZIP. Publish only the verified final archive; do not replace an old prerelease silently.

## Sources

[1] https://developer.apple.com/tutorials/data/documentation/security/notarizing-macos-software-before-distribution.json — Apple: Notarizing macOS software before distribution
