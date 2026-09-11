# Better Paste

A native macOS menu-bar clipboard picker for text, rich text, and images.

[Project guide](https://github.com/saksham-arch/better-paste-for-a-mac/blob/main/docs/index.md) · [Report a bug](https://github.com/saksham-arch/better-paste-for-a-mac/issues)

## Build and run

Requires macOS 14+ and Xcode with the macOS 26 SDK (the app falls back to standard materials on older macOS versions).

```sh
swift test
bash scripts/package_app.sh
open dist/BetterPaste.app
```

The packaging script builds the release executable and creates an ad-hoc signed app.
It is not notarized. Grant the built Better Paste app Accessibility permission in
System Settings → Privacy & Security → Accessibility for automatic pasting.

## Keyboard and mouse

| Input | Behavior |
| --- | --- |
| Control + V | Open or close the picker |
| Type in search | Search text or source app across retained history |
| ↑ / ↓ | Leave search and browse clips, wrapping at the ends |
| Return | Paste the selected clip or selection |
| ← / → while browsing | Open actions / formatting |
| ← / → in a menu | Cycle choices in both directions |
| Escape | Close preview, leave a menu, clear search, or close picker |
| Command + F or Tab | Focus search |
| Space while browsing | Preview |
| Shift + Space while browsing | Add/remove a clip from the ordered selection |
| Command + Delete while browsing | Delete the current clip |
| Home / End while browsing | First / last clip |
| Click / double-click | Select / paste |
| Right-click | Paste, select, save, search, or delete |

Search retains normal spaces, punctuation, deletion, selection, and text-editing
shortcuts. The letters H, J, K, and L are search text, not navigation shortcuts.
While search is focused, left/right arrows edit the text; press up/down to browse.

## Clipboard and actions

- Images publish both PNG and TIFF, with optional grayscale conversion.
- Rich text includes a plain-text fallback. Plain Text explicitly strips formatting.
- Text selections join with newlines. Mixed/image selections retain separate
  pasteboard items; the destination app determines support for pasting multiple items.
- Save a single image as PNG or text clips as UTF-8. Multi-image saving is not supported.
- Search selected text with Google, ChatGPT, Bing, or DuckDuckGo. Unicode, emoji,
  plus signs, ampersands, and URL fragments are encoded safely.
- Restoration preserves all original clipboard representations and never replaces
  a newer copy. Internal clipboard writes do not reappear as history entries.
- Recopying a clip updates its count. Whitespace and rich-text formatting differences
  remain distinct.

## Settings and privacy

Use the menu-bar Settings item for history limits, duplicate merging, restoration,
keyboard shortcut presets, and search URL templates. Templates must include
`%s` and an HTTP(S) URL. Changes apply when you click Save Changes.

Settings live at `~/.config/better-paste/config.json`. History stays in memory and
clears when the app quits. Common password/keychain apps are excluded by bundle
identifier; the list is editable in the config. Web searches send the selected
text to the chosen provider.

## Verification

`swift test` checks image formats, mixed selections, rich-text fallback, Unicode
query encoding, clipboard snapshots, and preservation of newer copies.
Automatic paste depends on macOS Accessibility permission and the destination
app accepting the clipboard format.
