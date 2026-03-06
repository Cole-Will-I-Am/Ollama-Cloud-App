# macOS Direct Distribution (Outside App Store)

For the canonical multi-platform release process (iOS + macOS versioning, tags, labels, and sequencing), see:

- `docs/RELEASE_WORKFLOW.md`

This is the same distribution model used by many desktop apps downloaded from vendor websites:

1. Build Release app
2. Sign with Developer ID
3. Notarize with Apple
4. Staple ticket
5. Ship `.zip` or `.dmg`

## Prerequisites

- Apple Developer Program membership
- A valid `Developer ID Application` certificate in your keychain
- Xcode command line tools
- `xcodegen` (`brew install xcodegen`)
- A notarytool keychain profile

Create notarytool profile once:

```bash
xcrun notarytool store-credentials "seer-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID1234" \
  --password "app-specific-password"
```

## Build + Sign + Notarize + Package

From repo root:

```bash
chmod +x scripts/package_macos_direct.sh

DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID1234)" \
NOTARY_PROFILE="seer-notary" \
scripts/package_macos_direct.sh
```

Artifacts are written to:

- `dist/macos/SEER-<version>-<build>-macos.zip`
- `dist/macos/SEER-<version>-<build>-macos.dmg` (default enabled)
- `dist/macos/SEER-macos.zip` (stable filename)
- `dist/macos/SEER-macos.dmg` (stable filename)

Use the stable filenames for GitHub Releases so your README link never changes across versions.

Recommended README link:

- `https://github.com/Cole-Cant-Code/Ollama-Cloud-App/releases/latest/download/SEER-macos.dmg`

## Fast local test without signing/notary

```bash
SIGN_APP=0 NOTARIZE=0 scripts/package_macos_direct.sh
```

## Send to testers

Share the notarized `.dmg` or `.zip` URL.

If sharing `.zip`, tester install command:

```bash
curl -L -o SEER.zip "https://your-host/SEER-<version>-<build>-macos.zip"
unzip -q SEER.zip
mv -f SEER.app /Applications/SEER.app
open /Applications/SEER.app
```

If notarized and stapled, Gatekeeper prompts should be minimal.
