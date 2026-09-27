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
| Type in search | Search clip text, source app, group, note, or tags |
| Recent / Pinned / Groups | Filter history without leaving the picker |
| ↑ / ↓ | Leave search and browse clips, wrapping at the ends |
| Return | Paste the selected clip or selection |
| ← / → while browsing | Open actions / formatting |
| ↑ / ↓ in a menu | Choose an action or format |
| ← / → in a menu | Return to clips |
| Escape | Close preview, leave a menu, clear search, or close picker |
| Command + F or Tab | Focus search |
| Space while browsing | Preview |
| Shift + Space while browsing | Add/remove a clip from the ordered selection |
| Command + Delete while browsing | Delete the current clip |
| Command + P while browsing | Pin or unpin the current clip |
| Command + 1…9 | Paste that numbered clip from the current view |
| Home / End while browsing | First / last clip |
| Click / double-click | Select / paste |
| Right-click | Paste, pin, edit, group, save, search, or delete |
| Drag a row onto another | Move a clip before that row within the same pin section |

Search retains normal spaces, punctuation, deletion, selection, and text-editing
shortcuts. The letters H, J, K, and L are search text, not navigation shortcuts.
While search is focused, left/right arrows edit the text; press up/down to browse.

## Clipboard and actions

- Images publish both PNG and TIFF, with optional grayscale conversion.
- Image clips can extract text locally with macOS Vision and paste the result.
- Rich text includes a plain-text fallback. Plain Text explicitly strips formatting.
- Format actions include Markdown for rich text and a quoted JSON string for text.
- Text selections join with newlines. Mixed/image selections retain separate
  pasteboard items; the destination app determines support for pasting multiple items.
- Save a single image as PNG or export text clips as TXT, Markdown, JSON, or HTML.
  Multi-image saving is not supported.
- Finder file clips retain their file URL. Media files can be converted locally to
  M4A audio or MP4 video when macOS supports the source format.
- Search selected text with Google, ChatGPT, Bing, or DuckDuckGo. Unicode, emoji,
  plus signs, ampersands, and URL fragments are encoded safely.
- Restoration preserves all original clipboard representations and never replaces
  a newer copy. Internal clipboard writes do not reappear as history entries.
- Recopying a clip updates its count. Whitespace and rich-text formatting differences
  remain distinct.
- Pins survive Clear History. Edit a clip to change its text, group, note, and tags.
  Editing rich text content converts that clip to plain text; changing metadata does not.
- Create named literal or regular-expression text actions in Settings. They run only
  when chosen from a text clip’s Actions menu and do not run on every copy.

## Settings and privacy

Use the menu-bar Settings item for history limits, duplicate merging, restoration,
keyboard shortcut presets, and search URL templates. Templates must include
`%s` and an HTTP(S) URL. Changes apply when you click Save Changes.

Settings live at `~/.config/better-paste/config.json`. History is saved locally
at `~/Library/Application Support/BetterPaste/history.json` with user-only file
permissions. Disable history persistence in Settings to retain only pinned clips
between launches. Images over 5 MB remain available in the current session but
are skipped in the archive; the archive has a 40 MB data budget, prioritizing
pins and then recent clips. Settings also accept app bundle IDs and text phrases
to exclude from capture. Common password/keychain apps are excluded by default.
Web searches send the selected text to the chosen provider.

## Verification

`swift test` checks image formats, mixed selections, rich-text fallback, Unicode
query encoding, clipboard snapshots, preservation of newer copies, saved clip
metadata, pin clearing, file URLs, and Markdown/JSON output.
Automatic paste depends on macOS Accessibility permission and the destination
app accepting the clipboard format.
