# Usage and implementation details

[简体中文](DETAILS.md) | **English**

[Back to SicGo](../README.en.md)

SicGo is an independent macOS utility for temporary screenshot annotation. It uses native AppKit windows and toolbars and supports English and Simplified Chinese. It reads screenshot files created by macOS rather than capturing the screen itself, so SicGo does not require Screen Recording permission.

The app lives in the menu bar without a Dock icon. Its menu uses native monochrome icons, with sections for capturing and importing images, opening the main window and settings, and quitting. Annotation windows can still become active and receive keyboard input normally.

SicGo remembers the last annotation tool, color, and window position across sessions. When displays change, windows are kept within the visible screen area. New images retain their own aspect ratio. Preferences store interface choices only, not screenshots or annotations.

## Interface language

Click the SicGo menu bar icon and choose **Settings…**, or press **Command–,** while the app is active. The main window also has a Settings button.

Choose **English**, **简体中文**, or **Follow System**. English is the default. Changes immediately update app menus, the main window, editor tooltips, and buttons, and the preference is saved automatically. Changing languages does not recreate editing windows or clear annotations. Follow System selects a supported language in the order of your system preferences, falling back to English if none is supported. The language of macOS file dialogs and Apple's Screenshot app is managed by the system.

## Common settings

- **Launch at login:** Uses the native macOS login item service and is off by default. It is enabled only when you select it. If macOS approval is required, SicGo shows a link to System Settings. Opening Settings refreshes the actual system status; a failed change displays an error and returns the control to the current status.
- **Show main window on launch:** On by default. Turn it off to start with just the menu bar icon. You can still open the main window from the menu, and opening images works as usual.
- **Toolbar order:** Settings shows the same row of icons as the editor. Drag an icon to reposition it, or focus it and use the left and right arrow keys. Dropping applies the order to all editor windows and saves it across restarts. Click **Reset order** to restore the original layout. Drop outside the icon row or press Escape to cancel a drag. Reordering does not change existing annotations.
Tools, colors, and toolbar order are always remembered automatically, with no toggle. Each new image starts with the most recently selected tool and color. Settings has no separate default tool or color controls.

New images use the latest tool and color, while other open editors keep their current state. Language, font, toolbar order, and window position are saved automatically; macOS manages the login item status.

Text uses the system font by default. Settings can select an installed font; the list loads only when opened, with no bundled fonts. This preference is remembered and applies to newly typed annotations. Existing text keeps its font when edited, copied, resized, and exported; unavailable fonts fall back to the system font. The green checkmark is the **Done** action: copy the image and close.

## Updates

**Check for Updates…** is available in the menu bar and Settings. The system URLSession API reads the latest public stable GitHub Release from `sic7en/SicGo`. Numeric version comparison prevents downgrade recommendations; drafts and prereleases are rejected. Missing releases, offline errors, rate limits, and invalid responses show separate messages and allow retrying.

When a newer version is available, **Download Update…** opens its release page. Downloading and replacing the app are manual. Checking does not affect editing or quit the app. Finish your screenshot and quit before installing; preferences are retained.

One request is made only when clicked, without a GitHub login, screenshots, annotations, or preferences. The ephemeral session stores no cookies or disk cache. There are no background timers, automatic downloads, or third-party update frameworks. Responses are limited to 1 MiB and requests time out after 20 seconds.

## Workflow

1. Keep SicGo running. Use the macOS shortcut **Command–Shift–4** to capture a region or **Command–Shift–3** to capture the full screen.
2. Once macOS finishes writing the screenshot, SicGo opens it in an editor. Press Escape during region selection to cancel. The **Screenshot…** button opens Apple's Screenshot app, which is also available with **Command–Shift–5**.
3. Add text, arrows, rectangles, ellipses, pen strokes, or pixelation. Cropping and whole-image rotation are also available.
4. **Copy** copies the current image and keeps the editor open. **Done** copies it and closes the editor.
5. Paste the result into a chat, document, or another app. Closing the window or clicking the trash button discards the editing session.

You can also use **Open Image…** to open a local file, or **From Clipboard** to edit an image on the clipboard. Original files you open are never modified or deleted.

Holding Control with a system screenshot shortcut sends the screenshot to the clipboard. In that case, use **From Clipboard** or **Command–N** to open it. SicGo does not automatically monitor the clipboard.

## Annotation controls

- Copy another image and press Command–V in the editor to add it as a separate image object. Copying an image file in Finder also works. Original files and transparency are preserved. A pasted image is selected and ready to drag; use Select to pick it again later. Corner handles preserve its aspect ratio by default; hold Option to resize freely. Trackpad rotation, duplication, deletion, undo, and redo are supported. Switch to Text, Rectangle, or another drawing tool to annotate over the image.
- Selected tools use neutral corner brackets without changing their icon colors. Rotating, cropping, or undoing keeps the editor window size and position unchanged; the image is centered and fitted proportionally.

- Select an annotation, press Command–C, then Command–V to paste an editable copy with the same color, size, text, and rotation. The copy is slightly offset and automatically selected, ready to drag. You can also paste it into another open image. Use the toolbar's Copy or Done button to copy the entire image; Command–C also copies the image when no annotation is selected. While typing, the text field handles copy and paste normally.
- Type text directly on the image. Click outside the text area or move focus elsewhere to finish. Return also finishes editing; Shift–Return inserts a new line, and Escape cancels.
- Drag completed text directly to move it, or double-click to edit it again. Click other annotations to select them, then drag. With the Select tool, existing annotations can be dragged directly.
- Drag a corner to resize an annotation. Hold Shift to preserve its proportions. You can add more content inside an outline shape.
- Drag either endpoint of an arrow to change its direction and length. Hold Shift to snap to 45° increments.
- With the pointer over a selected object, use a two-finger trackpad rotation gesture to rotate it. Corner handles are for resizing only.
- Strokes stay thin. Resizing a shape does not change its stroke width.
- **Command–Z:** Undo. **Command–Shift–Z:** Redo. **Delete:** Remove the selected annotation.
- **Command–Return:** Copy and close. **Command–W:** Close and discard the editing session.

## Temporary data

While running, SicGo temporarily redirects system screenshots to its own cache folder and disables the system's floating screenshot thumbnail to avoid opening two editors for the same capture. A screenshot file is deleted after it has finished writing and has been successfully read into memory. Incomplete files or files that cannot yet be read are retained for retries. SicGo processes only new images created during the current session that carry the macOS screenshot metadata flag. It leaves pre-existing files, ordinary images, symbolic links, and videos alone.

On normal exit, including SIGTERM, SicGo restores the previous screenshot destination, output target, and thumbnail settings while preserving changes you made yourself during the session. On macOS 27 it uses screenshot-specific settings, leaving the screen recording destination unchanged. Earlier versions of macOS share a destination setting between screenshots and recordings; SicGo does not delete video files.

After an unexpected termination, a recovery record allows SicGo to restore the original settings the next time it starts. Files that were not successfully imported may remain in the cache. Old files are not automatically imported or deleted. The cache folder is `~/Library/Caches/local.makstton.SicGo/System Screenshots`.

Pasted images retain their original pixels in memory; preview scaling does not change those pixels. Image imports support up to about 33.5 megapixels, with a 64 MiB limit on image clipboard data.

Annotations and undo history live only in memory and are released when the editor closes. There is no screenshot history, autosave, annotation sidecar storage, or screenshot shelf at the top of the screen. Images copied to the system clipboard remain available until something else replaces them. File reception uses filesystem change notifications, with no periodic directory scanning while idle.

## Resource use

- The main window and Settings window are created when first needed and reused afterward, avoiding repeated creation and destruction of native controls. Screenshot editors release their images and annotations when closed.
- During each draw, each pixelated region generates its low-resolution patch once. Later overlapping pixelated regions reuse those patches, which are released after drawing. Preview and copied output retain their existing resolution and drawing order.
- Undo and redo share a limit of 30 steps and a budget of 128 MiB for additional retained history data. Shared source and pasted images are counted once. Images needed by the current canvas are excluded from that budget. History estimates also account for annotation arrays, pen points, and text. The budget is checked after cropping, rotation, undo, and redo. More distant history entries are discarded when the budget is exceeded; the current image is always retained. This budget is not a cap on the app's total memory use.

Run `bash scripts/benchmark.sh` from the project root to measure median rendering time for a 1080p image with different numbers of pixelated regions. Test files and build intermediates are not included in the app bundle.

Measurements from October 24, 2026, using the same test image on the development Mac, a Release-optimized build, and the median of three runs per case:

| Pixelated regions | Before optimization | After optimization |
| --- | --- | --- |
| 6 | 4.79 ms | 3.83 ms |
| 10 | 18.83 ms | 5.25 ms |
| 12 | 59.79 ms | 5.95 ms |

These are rendering measurements for a fixed test scenario. Actual times depend on the image and hardware. Regression checks compare output pixel by pixel for overlapping and rotated annotations at different preview scales.

## Building

You need macOS 14 or later, a Swift toolchain, and the macOS SDK. Run these commands from the project root:

```sh
bash scripts/build.sh
open build/SicGo.app
```

The build script uses the current system SDK, produces a Release app, and applies an ad hoc code signature. The project has no third-party package dependencies.

Run the regression checks:

```sh
bash scripts/check.sh
```

## Publishing updates

Increase the version and build in `scripts/build.sh`, then run `bash scripts/check.sh` and `bash scripts/package.sh`. Upload the generated DMG to a **public, non-prerelease GitHub Release** in `sic7en/SicGo`, tag it `vX.Y.Z`, and mark it as the latest release. Publish source and installer for the same version. A source commit or tag alone does not make an update available. Older apps without the check button need one manual update first.

## Source layout

| File | Responsibility |
| --- | --- |
| `App.swift` | App entry point, menus, and opening or pasting images |
| `HomeWindow.swift` | Native welcome window and capture/import actions |
| `Capture.swift` | Receiving system screenshots, cleaning up successfully imported files, and restoring screenshot settings |
| `EditorWindow.swift` | Native toolbar, Copy, and Done actions |
| `ToolbarLayout.swift` | Toolbar item definitions, drag reordering, and keyboard adjustment |
| `EditorPreferences.swift` | Lightweight preferences for tools, colors, and window position |
| `SettingsWindow.swift` | Native settings, language changes, login items, toolbar order, and fonts |
| `UpdateChecker.swift` | On-demand GitHub stable-release checks, version comparison, and update state |
| `Localization.swift` | Interface strings and system language matching |
| `EditorCanvas.swift` | Clicking, dragging, resizing, rotation, and inline text editing |
| `EditorDocument.swift` | In-memory images, annotations, undo, and redo |
| `AnnotationClipboard.swift` | Editable annotation copies, pasted images, and local image file imports without persistent storage |
| `Drawing.swift` | Annotation geometry, hit testing, and rendering at the image's original resolution |

This is an independently written project with no third-party packages, screenshot history database, or direct screen capture code. macOS manages the global screenshot shortcuts.
