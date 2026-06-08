# Build & upload to TestFlight without a Mac

This repo can build the iOS app and upload it to App Store Connect / TestFlight
entirely on GitHub's hosted macOS runners. You do **not** need a Mac — not even
for signing. The workflow uses an App Store Connect API key so Xcode creates a
cloud-managed distribution certificate automatically.

Everything below is done in a web browser.

## 0. Activate the workflow file (one-time)

The workflow is checked in at **`ci/ios-release.yml`**. It must live at
`.github/workflows/ios-release.yml` for GitHub Actions to run it. It was placed
under `ci/` because the automation token used to push this repo lacks GitHub's
`workflow` scope — but you can move it in the browser in under a minute:

1. On GitHub, open `ci/ios-release.yml` and copy its full contents.
2. Click **Add file → Create new file**.
3. Name it exactly `.github/workflows/ios-release.yml` (typing the slashes
   creates the folders).
4. Paste the contents, then **Commit changes**.
5. (Optional) delete `ci/ios-release.yml` afterward.

Web-UI commits are allowed to add workflows even when API tokens aren't, so this
just works. After this, the workflow appears under the **Actions** tab.

## 1. Create an App Store Connect API key

1. Go to <https://appstoreconnect.apple.com> → **Users and Access** → **Integrations** tab → **App Store Connect API**.
2. Under **Team Keys**, click **+** to generate a key.
   - Name: e.g. `GitHub Actions`
   - Access role: **App Manager** (needed to upload builds).
3. Note the **Issuer ID** (shown above the key list) and the **Key ID** (the row).
4. Click **Download API Key** — this gives you a file named `AuthKey_XXXXXXXXXX.p8`.
   You can only download it once; keep it safe.

## 2. Find your Apple Team ID

In <https://developer.apple.com/account> → **Membership details**, copy the
**Team ID** (10 characters, e.g. `A1B2C3D4E5`).

## 3. Base64-encode the .p8 key

The key has to go into a GitHub secret as one line. Encode it:

- **macOS/Linux:** `base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '\n'`
- **Windows (PowerShell):** `[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXXXXXXXX.p8"))`
- **No terminal at all:** use any "file to base64" web tool (the key is sensitive — prefer a local/offline encoder).

Copy the resulting single-line string.

## 4. Add the four repository secrets

In GitHub: repo → **Settings** → **Secrets and variables** → **Actions** →
**New repository secret**. Add each of:

| Secret name | Value |
|---|---|
| `ASC_KEY_ID` | The Key ID from step 1 (e.g. `XXXXXXXXXX`) |
| `ASC_ISSUER_ID` | The Issuer ID from step 1 |
| `ASC_KEY_P8_BASE64` | The base64 string from step 3 |
| `APPLE_TEAM_ID` | The Team ID from step 2 |

## 5. Bump the version for the resubmission

Because this build is a new version that addresses the App Review rejection,
bump the marketing version in `project.yml` before building (e.g. `1.0.0` → `1.0.1`):

```yaml
settings:
  base:
    MARKETING_VERSION: "1.0.1"
```

The build number is set automatically to the GitHub run number, so each run
gets a unique build number without any manual change.

> If you edit `project.yml`, regenerate and commit the project — see
> `docs/XCODE_CLOUD_SETUP.md` (or ask and it can be regenerated for you).

## 6. Run the workflow

GitHub → **Actions** tab → **iOS — TestFlight Release** → **Run workflow**.
Leave “Upload to TestFlight” checked.

The job will:
1. Build and sign the app on a macOS runner (no Mac of yours involved).
2. Upload the `.ipa` to App Store Connect.
3. Also attach the `.ipa` as a downloadable build artifact.

After Apple finishes processing (a few minutes), the build appears under
**TestFlight** and can be attached to your App Store submission.

## Notes & limits

- **iOS only.** The macOS target currently has empty entitlements and isn't set
  up for Mac App Store distribution (no app sandbox). A macOS lane can be added
  once the entitlements/signing are configured.
- **First run may surface signing/config errors** that can't be checked without
  actually building. If the run fails, the log will show exactly what xcodebuild
  is unhappy about — send it over and it can be fixed.
- The API key is **only** stored as encrypted GitHub secrets and written to a
  temporary file on the ephemeral runner; it is never committed to the repo.
- This is independent of Xcode Cloud — you can use either. This path needs no Mac
  at all; Xcode Cloud needs a Mac once for onboarding.
