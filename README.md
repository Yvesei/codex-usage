<p align="center">
  <img src="Resources/AppIcon.png" alt="Codex Usage logo" width="120" height="120" />
</p>

<h1 align="center">Codex Usage</h1>

<p align="center">Codex usage tracker for macOS 12 and later.</p>

<p align="center">
  <a href="#features">Features</a>
  · <a href="#build-and-run">Build and run</a>
  · <a href="#development">Development</a>
</p>

<p align="center">
  <img src="docs/images/menu-preview.png" alt="Codex Usage menu in dark mode" width="420" />
</p>

## Features

- Five-hour and weekly usage remaining, with reset times.
- A stacked daily model-usage chart covering today and the previous six dates. Hover over a bar for its model breakdown.
- Additional limits, model names, and reset credits when Codex reports them.
- Optional notifications at 10% or 5% remaining.
- Automatic refresh every two minutes and after waking your Mac. The last successful reading stays visible while refreshing or if a request fails.

The chart uses the same account-level model analytics as the ChatGPT usage page. It shows relative usage or credits when reported, rather than per-model token counts. Dates use UTC reporting buckets, and missing data is shown as unavailable.

## Requirements

- macOS 12 or later.
- A recent [Codex CLI](https://developers.openai.com/codex/cli/) signed in with a ChatGPT account. Run `codex login` in Terminal if needed.

The app finds Codex in common installation paths, including Homebrew, npm, pnpm, and nvm. It uses your existing Codex sign-in; it does not need a separate API key. An API-key-only Codex login is not supported.

## Install

Download `Codex-Usage.dmg` from the [latest release](https://github.com/Yvesei/codex-usage/releases/latest). Open it, drag **Codex Usage** to **Applications**, and launch the app. The download supports Intel and Apple silicon Macs.

The app is not signed with an Apple Developer ID or notarized. macOS may block its first launch; after attempting to open it, you can choose **Open Anyway** in System Settings → Privacy & Security. See [Apple's instructions](https://support.apple.com/en-us/102445) for details.

## Build and run

Building from source also requires Xcode Command Line Tools (`xcode-select --install`).

Clone the repository, open its directory in Terminal, and run:

```sh
bash scripts/build.sh
open "build/Codex Usage.app"
```

The app appears in the menu bar rather than the Dock. Click its indicator to see details, change settings, refresh, or quit. To keep the app somewhere else, copy the built app to your Applications folder.

The build is signed locally for use on your Mac; it is not a notarized distribution. Anyone building from source needs the tools listed above.

## Notifications

On first launch, macOS asks for notification permission. Alerts are optional and can be enabled in the app's Settings menu at either 10% or 5% remaining. macOS remembers your permission choice.

## How it works and privacy

The app starts the local Codex app server to request account information and rate limits. For the model chart, it reads the existing Codex file-based ChatGPT login and sends its access token directly to ChatGPT's analytics endpoint over HTTPS. It does not save the token or read browser cookies. The chart requires a file-based Codex login; keychain-only and API-key logins aren't supported for model analytics.

The latest reported limits, model usage, and account identifiers are stored locally in macOS preferences for display on the next launch. Cached data can remain visible when a refresh fails. The app checks account and user identity before reusing model data and clears it when the identity changes.

The analytics endpoint is not a documented public API and can change or become unavailable. This app does not calculate costs or derive token counts from model usage.

The app relies on the Codex app-server interface; changes to Codex or account availability may affect the information it can display. It is an independent project and is not affiliated with OpenAI.

## Development

The project uses Swift and AppKit, with no third-party dependencies. Source files are organized by app lifecycle, Codex communication, models, storage, notifications, and UI.

Run the parser, reader, and native menu checks with:

```sh
bash scripts/test.sh
```

The reader checks use local fake Codex responses and do not require an account. The menu checks require macOS and AppKit.
