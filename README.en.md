# SicGo

[简体中文](README.md) | **English**

**Clearer feedback for Codex and Claude Code, right on your screenshots.**

SicGo is a lightweight macOS screenshot annotation tool for everyday work with AI coding tools such as Codex and Claude Code. Take a screenshot, circle a problem, draw an arrow, or add a note. Then copy it and share it with your AI assistant.

**Capture → Annotate → Copy → Paste.**

A few simple features that come in handy when refining interfaces and reporting issues.

## Why SicGo?

When asking AI to change an interface, you often need to explain things like “align this,” “move this button to the left,” or “there's too much space here.” Words alone can make it hard to identify the exact area you mean.

A box, an arrow, and a short note can show exactly what needs to change. SicGo brings those steps together so that sharing visual feedback feels as simple as copying and pasting.

For example:

- **Refine an interface:** Draw a box around a component and add “Align the left edge with the heading above.”
- **Report a bug:** Point to misplaced or obscured content and describe what is happening.
- **Explain a reference:** Open a reference image and mark the layout, spacing, or details you want to keep.
- **Prepare an image to share:** Pixelate details you do not want to share, then copy the image.

## How to use it

1. Launch SicGo. It stays in the macOS menu bar.
2. Press **⌘⇧4** to capture a region. Once macOS finishes the screenshot, it opens automatically in the annotation window.
3. Use text, arrows, or boxes to point out what you want to change.
4. Click the green checkmark (**Done**) to copy the image to the clipboard and close the editor.
5. Paste it into a Codex, Claude Code, or other client that supports image pasting, then add your instructions.

Click **Copy** if you want to keep editing. You can also open a local image or start from an image on the clipboard.

SicGo prepares the image. It requires no model setup or API key and does not send screenshots to AI automatically. How you paste images depends on the client you use.

## Everyday essentials

| Feature | What it helps you do |
| --- | --- |
| Text, arrows, rectangles, ellipses, and a pen | Point out problems and explain the changes you want |
| Pixelation, cropping, and image rotation | Prepare the image before sharing |
| Move, resize, and rotate annotations | Adjust marks you have already made |
| Paste an image onto the current image | Move, resize, and annotate a reference image as a separate object |
| Undo and redo | Correct changes as you go |
| Copy, or copy and close | Get the result ready to paste |
| English and Chinese interfaces, remembered tools and colors | Continue with your last choices, with no extra toggle |
| Reorder the toolbar | Drag icons in Settings; changes apply immediately and persist |

Type directly on the image and click elsewhere to finish. Drag existing text to move it, or double-click to edit it again. Text uses the system font by default; choose another installed font in Settings.

Copy another image and press **⌘V** in the editor to add it to the current canvas. It stays editable as a separate object that you can move, resize, rotate, or delete. Rotating the whole image keeps the window size and position unchanged.

Select an annotation and press **⌘C → ⌘V** to make an editable copy with the same color, size, and rotation. Move, resize, or edit the copy, and undo the paste if needed. The toolbar's **Copy** and **Done** buttons always copy the entire image.

## Lightweight and temporary

- **Native macOS app:** Built with Swift and AppKit, with no third-party package dependencies.
- **Lives in the menu bar:** No Dock icon, with an optional launch-at-login setting.
- **Uses system screenshots:** Reads images created by macOS. SicGo does not require Screen Recording permission.
- **Local editing:** No account, cloud sync, or built-in AI service.
- **No screenshot history:** Successfully imported system screenshot files are deleted. Annotations and undo history stay in memory only.

Closing the editor discards the current editing session. Images you have copied remain on the system clipboard and can still be pasted. Local images you open are never modified or deleted.

While running, SicGo temporarily changes the system screenshot destination and disables the floating screenshot thumbnail. It restores those settings on normal exit. Temporary files may remain after an unexpected exit or a failed image import. See [Usage and implementation details](docs/DETAILS.en.md) for the full behavior.

## Installation

[Download the latest release](https://github.com/sic7en/SicGo/releases/latest)

The current DMG is for **Apple silicon Macs running macOS 14 or later**.

Open `SicGo-1.3.3-AppleSilicon.dmg`, drag **SicGo** into **Applications**, and launch it.

The current app uses an ad hoc code signature and has not been notarized by Apple.

## Check for updates

Choose **Check for Updates…** in the menu bar or Settings. When a newer version is available, click **Download Update…** to open its GitHub release page, download the installer, and replace the app.

Checks run only when requested, with no background polling or screenshot uploads. SicGo never quits automatically to update. Finish editing and quit before replacing the app; your preferences are retained.

## Build from source

You need macOS 14 or later, a Swift toolchain, and the macOS SDK. Run these commands from the project root:

```sh
bash scripts/build.sh
open build/SicGo.app
```

Run the regression checks:

```sh
bash scripts/check.sh
```

For more shortcuts, settings, temporary file behavior, and performance notes, see [Usage and implementation details](docs/DETAILS.en.md).

## Author

**Sic7en**

SicGo is an independent utility and is not affiliated with OpenAI or Anthropic.
