# Contributing to SEER

Thanks for your interest in improving SEER.

## Before you start

- Search existing issues and pull requests before opening a new one.
- For larger changes, open an issue first so we can align on scope.
- Keep pull requests focused. Smaller PRs review faster and ship faster.

## Development setup

```bash
brew install xcodegen
xcodegen generate
open OllamaCloud.xcodeproj
```

- Build iOS target with `OllamaCloud`
- Build macOS target with `OllamaCloudMac`

## Code quality expectations

- Preserve platform gates (`#if os(iOS)` / `#if os(macOS)`) where required.
- Keep iOS and macOS behavior consistent unless a platform capability differs.
- Add or update tests where practical for behavior changes.
- Do not include secrets, API keys, or machine-specific config in commits.

## Pull request checklist

- Explain the user-facing impact
- Include screenshots for UI changes
- Include testing notes (what you ran)
- Keep commit history clear and descriptive

## Contributor License Agreement (CLA)

To keep future licensing and commercialization options clear, maintainers may require a CLA before merging substantial contributions.

By opening a pull request, you agree that if requested you will sign a contributor agreement granting the project owner rights to use, relicense, and distribute your contribution.

If a CLA is required for your PR, maintainers will provide the signing instructions in the pull request thread.
