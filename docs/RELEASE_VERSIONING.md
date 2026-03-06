# Release Versioning and Platform Tracking

For the full end-to-end process (including GitHub release naming, direct-download artifacts, and App Store sequencing), use:

- `docs/RELEASE_WORKFLOW.md`

This repo ships two Apple platform apps from one shared codebase:

- iOS app: `com.colecantcode.ollamacloud`
- macOS app: `com.colecantcode.ollamacloud.mac`

## Why this file exists

App Store Connect tracks iOS and macOS submissions independently. GitHub should mirror that so version history is unambiguous.

## Versioning policy

- `CFBundleShortVersionString` (marketing version):
  - Keep aligned across platforms for the same product milestone (example: `1.0.0`).
- `CFBundleVersion` (build number):
  - Unique per platform submission.
  - Recommended format: `YYYYMMDDHHmm` (example: `202603051104`).
  - Any numeric value is valid, but timestamp format is easiest to keep monotonic.

## Git tags for clean platform history

Use platform-specific annotated tags on the commit that produced each submitted binary:

- iOS: `ios/v<marketing>-b<build>`
- macOS: `macos/v<marketing>-b<build>`

Examples:

- `ios/v1.0.0-b202603051104`
- `macos/v1.0.0-b202603061530`

Optional shared milestone tag (for source-level milestones):

- `v<marketing>` (example: `v1.0.1`)

Helper script:

```bash
scripts/tag_release.sh ios 1.0.0 202603051104 --push
scripts/tag_release.sh macos 1.0.0 202603061530 --push
```

## GitHub Releases naming

Create one release entry per platform submission:

- `iOS 1.0.0 (202603051104)`
- `macOS 1.0.0 (202603061530)`

This avoids ambiguity when one platform is in review and the other is not.

## Submission checklist (per platform)

1. Confirm target bundle ID and platform in Xcode.
2. Set marketing version + build number.
3. Archive and validate.
4. Tag the exact commit used for the archive with platform-specific tag.
5. Push tag and create GitHub Release for that platform build.
6. Submit to App Store Connect.

## Current status snapshot

As of March 6, 2026:

- iOS: `1.0.0 (202603051104)` submitted / under review
- macOS: not submitted yet
