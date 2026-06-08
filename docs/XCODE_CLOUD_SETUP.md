# Xcode Cloud Setup

This repo is prepared for Xcode Cloud, with one important local step: commit the generated Xcode project.

## Why the project file must be committed

The app uses XcodeGen (`project.yml`) as the source of truth. That works well locally, but Xcode Cloud expects a stable `.xcodeproj` or `.xcworkspace` to already exist in the repository when configuring and running workflows.

Commit `OllamaCloud.xcodeproj` after generating it from `project.yml`.

## One-time local setup

From the repository root:

```bash
brew install xcodegen
xcodegen generate
git add project.yml OllamaCloud.xcodeproj .gitignore
git commit -m "Add generated Xcode project for Xcode Cloud"
git push origin main
```

After this, open `OllamaCloud.xcodeproj` in Xcode and configure Xcode Cloud.

## Required App Store Connect records

Create or verify app records for both bundle IDs:

| Platform | Target | Bundle ID |
|---|---|---|
| iOS | `OllamaCloud` | `com.colecantcode.ollamacloud` |
| macOS | `OllamaCloudMac` | `com.colecantcode.ollamacloud.mac` |

## Recommended workflows

### iOS

- Project: `OllamaCloud.xcodeproj`
- Scheme: `OllamaCloud`
- Branch: `main`
- Actions: Build, Test, Archive
- Distribution: TestFlight / App Store Connect when ready

### macOS App Store

- Project: `OllamaCloud.xcodeproj`
- Scheme: `OllamaCloudMac`
- Branch: `main`
- Actions: Build, Test, Archive
- Distribution: App Store Connect when ready

## Signing

`project.yml` sets `CODE_SIGN_STYLE: Automatic` at the project level. In Xcode, select the correct Apple Developer team for both app targets before configuring Xcode Cloud.

Do not commit private signing assets, certificates, profiles, App Store Connect API keys, or notary credentials.

## Direct macOS distribution

The GitHub Release `.dmg` flow remains separate from Xcode Cloud. Continue using:

```bash
DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="seer-notary" \
scripts/package_macos_direct.sh
```

Use Xcode Cloud for App Store/TestFlight builds. Use `scripts/package_macos_direct.sh` for direct-download notarized DMG releases.
