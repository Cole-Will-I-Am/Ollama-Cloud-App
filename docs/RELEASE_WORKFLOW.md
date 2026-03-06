# Release Workflow (Canonical)

This is the source of truth for how SEER releases are versioned, tagged, labeled, and shipped across:

- iOS App Store
- macOS direct download (GitHub Releases)
- macOS App Store (when enabled)

## App Identity

- iOS bundle ID: `com.colecantcode.ollamacloud`
- macOS bundle ID: `com.colecantcode.ollamacloud.mac`

## Versioning Rules

Use shared marketing versions and per-platform build numbers.

- Marketing version (`CFBundleShortVersionString`): same on both platforms for the same milestone
  - Example: `1.0.0`
- Build number (`CFBundleVersion`): unique per platform submission
  - Recommended: `YYYYMMDDHHmm` (example: `202603051104`)
  - Numeric-only values are valid.

## Tagging Rules (GitHub)

Every shipped build must have a platform tag on the exact source commit used to produce the binary.

- iOS tag format: `ios/v<marketing>-b<build>`
- macOS tag format: `macos/v<marketing>-b<build>`

Examples:

- `ios/v1.0.0-b202603051104`
- `macos/v1.0.0-b1`
- `macos/v1.0.0-b202603061530`

Create tags with:

```bash
scripts/tag_release.sh ios 1.0.0 202603051104 --push
scripts/tag_release.sh macos 1.0.0 202603061530 --push
```

## GitHub Release Labeling Rules

Create one GitHub Release per platform build with this naming:

- `iOS <marketing> (<build>)`
- `macOS <marketing> (<build>)`

Examples:

- `iOS 1.0.0 (202603051104)`
- `macOS 1.0.0 (202603061530)`

If both platforms ship together, create two release entries (one per platform) to keep audit history clear.

## macOS Direct Download Rules

The README "Download macOS (Direct)" link points to:

- `https://github.com/Cole-Cant-Code/Ollama-Cloud-App/releases/latest/download/SEER-macos.dmg`

To keep that link working forever:

1. Build/sign/notarize with `scripts/package_macos_direct.sh`
2. Upload `SEER-macos.dmg` to every new macOS GitHub Release

Reference: `docs/MACOS_DIRECT_DISTRIBUTION.md`

## Standard Release Sequence

Use this sequence unless there is a hotfix incident.

1. Finalize code on `main`.
2. Confirm target version/build values.
3. Build archive/binary for platform.
4. Tag source commit with platform tag.
5. Publish GitHub Release with platform naming.
6. Submit to App Store Connect (if applicable).

## iOS-First / macOS-Second Sequence

When iOS goes first and macOS follows:

1. Submit iOS build.
2. Keep macOS direct-download available through GitHub Releases.
3. After iOS approval, submit macOS App Store build.
4. Keep tags and release entries for each build.

## Submission Checklists

### iOS App Store

1. Verify iOS bundle ID and target.
2. Verify marketing version and build number.
3. Archive and validate.
4. Tag exact source commit (`ios/v...`).
5. Create GitHub Release entry (`iOS ...`).
6. Submit build in App Store Connect.

### macOS Direct Download

1. Ensure `Developer ID Application` certificate is available.
2. Ensure notary profile exists (`xcrun notarytool store-credentials ...`).
3. Run packaging script:
   - `DEVELOPER_ID_APP="..." NOTARY_PROFILE="..." scripts/package_macos_direct.sh`
4. Upload `SEER-macos.dmg` to GitHub Release.
5. Tag exact source commit (`macos/v...`).
6. Verify README download link works against `latest` release.

### macOS App Store

1. Verify macOS bundle ID and target.
2. Verify marketing version and build number.
3. Archive and validate App Store build.
4. Tag exact source commit (`macos/v...`).
5. Create GitHub Release entry (`macOS ...`).
6. Submit build in App Store Connect.

## Current Snapshot

As of March 6, 2026:

- iOS build in review: `1.0.0 (202603051104)` (tag: `ios/v1.0.0-b202603051104`)
- macOS GitHub tag created: `macos/v1.0.0-b1`

Update this section whenever submission state changes.
