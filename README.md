<p align="center">
  <img src=".github/seer_logo.png" alt="SEER" width="320">
</p>

<p align="center">
  iOS client for Ollama Cloud — streaming chat with your models.
</p>

---

## Features

- Stream chat completions from Ollama Cloud API
- Thinking/reasoning display with collapsible disclosure
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

## License

All rights reserved.
