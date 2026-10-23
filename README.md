# TextAnywhere

A macOS menu bar app for writing, translating, dictating, and recognizing text, then pasting the result straight into the app you were using.

Press a shortcut in any app, type or dictate in the floating editor, and send the text, translated or as-is, back to where your cursor was.

## Features

- **Floating editor anywhere.** Press <kbd>⌃</kbd><kbd>⌥</kbd><kbd>Space</kbd> to open the editor over any app. The result is inserted into the window that was active when you opened it.
- **Translation with your own model.** Bring an API key for Anthropic, OpenAI, OpenRouter, xAI, Bailian, DeepSeek, or BigModel, or run models locally with Ollama.
- **Automatic target language.** Set a primary and secondary language. Text in your primary language is translated into the secondary one, and everything else into the primary one. You can also pick the target in the editor.
- **One-key send.** The primary button either pastes the text as-is or translates and pastes it. <kbd>⌘</kbd><kbd>↩</kbd> triggers it.
- **Voice input.** Dictate into the editor with Qwen speech recognition through Bailian.
- **OCR.** Recognize text with GLM-OCR through BigModel from a screen selection, pasted or dropped images and PDFs, or a file. Optionally translate the result and convert HTML tables to Markdown tables.
- **Markdown editing.** Switch the editor between plain text and rendered Markdown.
- **Automatic updates.** TextAnywhere checks GitHub Releases daily and can install new versions itself.

## Requirements

- macOS 26 or later
- An API key for at least one supported provider, or a local [Ollama](https://ollama.com) server

## Installation

1. Download the latest `TextAnywhere-<version>.zip` from [Releases](https://github.com/ktiays/TextAnywhere/releases/latest).
2. Unzip it and move **TextAnywhere.app** to your Applications folder.
3. Open TextAnywhere. It runs in the menu bar.

Releases are signed with a Developer ID certificate and notarized by Apple.

## Getting Started

1. Open **Settings** from the menu bar icon.
2. In **Providers**, enable a provider, enter its API key, and choose a model.
3. In **General**, choose your primary and secondary languages, and grant Accessibility access.
4. Press <kbd>⌃</kbd><kbd>⌥</kbd><kbd>Space</kbd> in any app to open the editor.

## Permissions

| Permission | Used for | Without it |
|---|---|---|
| Accessibility | Inserting text into the app you were using | Text is copied to the clipboard instead |
| Microphone | Voice input | Voice input is unavailable |
| Screen Recording | OCR screen capture and the OCR shortcut | Use paste, drop, or Choose File for OCR |

## Privacy

TextAnywhere has no server of its own. Text, audio, and images go directly from your Mac to the provider you configure, under that provider's terms. API keys are stored in your Keychain. The only other network request is the update check, which reads the latest release from the GitHub API.

## Updates

TextAnywhere checks for a new stable release once a day. You can turn this off or check manually in **Settings → General → Updates**, or choose **Check for Updates…** from the menu bar icon. Before installing, it verifies that the download is notarized and signed by the same developer as the installed app.

## Building from Source

Requirements: Xcode 27.

```bash
git clone https://github.com/ktiays/TextAnywhere.git
cd TextAnywhere
open TextAnywhere.xcodeproj
```

Select your own team under **Signing & Capabilities** for the TextAnywhere target, then build and run the **TextAnywhere** scheme.

To run the tests:

```bash
xcodebuild test -project TextAnywhere.xcodeproj -scheme TextAnywhere -destination 'platform=macOS'
```

Builds you sign yourself can't install updates from GitHub Releases, because the updater only accepts apps signed by the official developer team.

## Releasing

Pushing a tag in the form `vMAJOR.MINOR.PATCH` (for example `v1.14.0`) runs the [release workflow](.github/workflows/release.yml). It archives the app with Xcode 27, signs it with Developer ID, notarizes and staples it, and publishes a GitHub release. Tags with a pre-release suffix, such as `v2.0.0-beta.1`, are published as pre-releases and aren't offered as updates.

The workflow needs these repository secrets:

| Secret | Contents |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_P12_BASE64` | Base64 of the Developer ID Application certificate and private key (`.p12`) |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password of that `.p12` |
| `NOTARY_API_KEY_P8_BASE64` | Base64 of an App Store Connect API key (`.p8`) |
| `NOTARY_API_KEY_ID` | Key ID of that API key |
| `NOTARY_API_ISSUER_ID` | Issuer ID of that API key |

To package a notarized build locally, see [`script/package_and_notarize.sh`](script/package_and_notarize.sh).

## Acknowledgements

- [MD4C](https://github.com/mity/md4c) by Martin Mitáš, used for Markdown parsing (MIT License).

## License

TextAnywhere is available under the [MIT License](LICENSE).
