# Better Paste

A minimal native macOS clipboard picker. Normal copy and paste stay unchanged. Press `Control + V` to open a small picker near the cursor, choose a recent clipboard item with arrow keys or `J`/`K`, then press Return to paste.

## Features

- Watches text, rich text, and image clipboard history.
- Merges duplicate clips automatically and moves the reused clip to the top.
- Shows only a configurable number of recent items.
- Uses a JSON config file at `~/.config/better-paste/config.json`.
- Provides a native menu bar app, liquid-glass SwiftUI settings, and an AppKit floating picker.
- Supports Quick Look previews, multi-select paste, text transforms, and image black-and-white transforms.
- Adds left-arrow actions for native Save As and Search, with Google, ChatGPT, Bing, and DuckDuckGo options nested under Search.
- Restores the previous clipboard after pasting by default.
- Ignores common password/keychain apps by bundle identifier.

## Build

```sh
swift build
```

Run the debug executable:

```sh
.build/debug/BetterPaste
```

Package a local `.app` bundle:

```sh
bash scripts/package_app.sh
open dist/BetterPaste.app
```

For paste automation into other apps, macOS may require Accessibility permission for the built executable or terminal app that launches it.
