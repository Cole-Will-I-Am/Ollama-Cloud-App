# Xcode Cloud Setup

This repo is prepared for Xcode Cloud. The generated Xcode project is already committed, so you can open it directly in Xcode and start configuring workflows.

## Why the project file must be committed

The app uses XcodeGen (`project.yml`) as the source of truth. That works well locally, but Xcode Cloud expects a stable `.xcodeproj` or `.xcworkspace` to already exist in the repository when configuring and running workflows.

`OllamaCloud.xcodeproj` is therefore committed to the repo, generated from `project.yml`.

## Project file (already committed)

`OllamaCloud.xcodeproj` has been generated from `project.yml` and committed to the
repository, including the shared schemes (`OllamaCloud`, `OllamaCloudMac`) that Xcode
Cloud needs to select a build target. No local `xcodegen` run is required to get
started — just clone and open the project in Xcode.

### Regenerating after editing `project.yml`

If you change `project.yml`, regenerate and re-commit the project:

```bash
brew install xcodegen   # first time only
xcodegen generate
git add project.yml OllamaCloud.xcodeproj
git commit -m "Regenerate Xcode project"
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
