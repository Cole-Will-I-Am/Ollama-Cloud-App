<p align="center">
  <img src=".github/seer_logo_white.png#gh-dark-mode-only" alt="SEER" width="320">
  <img src=".github/seer_logo_black.png#gh-light-mode-only" alt="SEER" width="320">
</p>

<p align="center">
  SEER is an iOS client for Ollama Cloud with streaming chat and model controls.
</p>

---

## Features

- Stream chat completions from Ollama Cloud API
- Thinking/reasoning display with collapsible disclosure
- Live streaming stats during generation (thinking chars, chars, chunks, throughput)
- Conversation management with pin/unpin and delete actions
- Per-conversation model selection and parameter tuning (temperature, top-p, top-k, penalties, etc.)
- Keychain-secured API key storage
- Network monitoring with offline detection, retry logic, and certificate pinning
- Dark-mode-first UI with wide-tracked typography

## Requirements

- iOS 17.0+
- Xcode 16+
- An [Ollama Cloud](https://ollama.com) API key

## Build

```
brew install xcodegen
cd /path/to/repo
xcodegen generate
open OllamaCloud.xcodeproj
```

## Run In Simulator (Deterministic)

Always use this script to avoid installing stale builds from multiple DerivedData folders:

```
./scripts/run_ios_sim.sh
```

Defaults:
- Device: `iPhone 17 Pro`
- Derived data: `/tmp/OllamaCloud-DerivedData`

## Optional Backend Relay

This repo includes a lightweight relay backend in `backend/` for rate limiting, model policy, and observability while keeping the same app UX.

```
cd backend
cp .env.example .env
set -a && source .env && set +a
npm install
npm run start
```

To point the app to the relay in development, set one or both environment variables in your Xcode scheme:

- `OLLAMA_API_BASE_URL` (example: `http://localhost:8787`)
- `OLLAMA_BACKEND_BEARER_TOKEN` (only if backend auth is enabled)

See `backend/README.md` for production deployment configuration.

## License

All rights reserved. No license granted at this time.
