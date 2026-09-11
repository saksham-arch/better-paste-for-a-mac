# A second chance at your clipboard

Better Paste keeps your recent text, rich text, and images one shortcut away.
Press **Control + V**, choose a clip, and press **Return**.

[Source code on GitHub](https://github.com/saksham-arch/better-paste-for-a-mac)

## Made for the keyboard

Type to search your retained history. Use the up and down arrows to browse.
Press the left arrow for actions or the right arrow for formatting.
Escape takes you back; Command + F returns to search.

Space previews a clip. Shift + Space adds it to a selection.
Right-click a clip for paste, save, search, and delete actions.

## Text and images

Paste text without formatting, change its case, or encode it as a URL or Base64.
Images are placed on the clipboard as PNG and TIFF, with an optional grayscale conversion.
Search actions support Unicode, emoji, and punctuation.

Mixed selections keep their image and text representations. Whether multiple
items paste together depends on the destination app.

## Get started

Requires macOS 14 or later and a current Xcode toolchain with the macOS 26 SDK to build.

    git clone https://github.com/saksham-arch/better-paste-for-a-mac.git
    cd better-paste-for-a-mac
    bash scripts/package_app.sh
    open dist/BetterPaste.app

Grant Better Paste Accessibility permission in System Settings to let it paste into other apps.
The local build is ad-hoc signed, not notarized.

## Your history

History stays in memory and clears when you quit. Clipboard restoration preserves
all original formats and leaves newer copies alone. Web search sends the selected
text to the provider you choose.

[Report a problem](https://github.com/saksham-arch/better-paste-for-a-mac/issues)
