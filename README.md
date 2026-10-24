# SideScroll

A scrolling window manager for macOS. Windows sit side by side on one endless horizontal strip instead of being squeezed into a grid. Move along it with the keyboard or a trackpad swipe. Inspired by niri and PaperWM.

Free and open source. Native Swift, no SIP changes, needs only the Accessibility permission. macOS 13 Ventura or newer, Apple silicon and Intel.

## Install

Paste this into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/TCYTseven/SideScrollMac/main/install.sh | bash
```

It downloads the latest release, puts `SideScroll.app` in `/Applications`, and opens it. Allow Accessibility access when asked; SideScroll then appears in the menu bar. Run the same line again to update (or use **Check for Updates…** in the menu).

**Prefer a download?** Grab `SideScroll.dmg` from the [latest release](https://github.com/TCYTseven/SideScrollMac/releases/latest) and drag it to Applications. The app isn't notarized by Apple, so the first launch is blocked: open **System Settings → Privacy & Security**, scroll down, click **Open Anyway**. The Terminal line above skips this step.

The installer checks the download against the SHA-256 checksum GitHub publishes for it, updates an existing copy wherever it is installed, and links the `sidescroll` command-line tool.

### Uninstall

Either click the menu bar icon → **Uninstall SideScroll…**, or run:

```bash
curl -fsSL https://raw.githubusercontent.com/TCYTseven/SideScrollMac/main/uninstall.sh | bash
```

Both put every window back on screen, then remove the app, its login item, settings, caches, command-line tool and Accessibility entry.

### Recommended macOS settings

The setup guide (menu bar → Setup Guide…) links straight to each of these:

1. **Trackpad → More Gestures → Swipe between full-screen applications**: turn it off, or set it to the finger count SideScroll doesn't use. SideScroll swipes with 4 fingers by default (3 is an option). Switch desktops with ⌃← / ⌃→.
2. **Desktop & Dock (macOS 15+)**: turn off *Drag windows to screen edges to tile* and *Drag windows to menu bar to fill screen*.
3. Multiple displays: placing the second display above or below the main one keeps scrolled-away windows from peeking onto it. Side by side works too; windows snap flush to the shared edge.

## Features

- **Endless strip.** Every window gets a column. New windows open to the right of the focused one (or at the end) and never shrink the others.
- **Trackpad swipe.** Three- or four-finger swipe scrolls the strip with your fingers, with momentum and snapping to columns. Natural or inverted direction, adjustable sensitivity. Hold ⌃⌥ and use the scroll wheel on a mouse.
- **Spring animations** tied to the display refresh rate; interrupted animations keep their momentum. Speed is adjustable, or turn them off.
- **Width presets.** Cycle each column through 25 / 33 / 50 / 66 / 75 % (your own list), nudge wider or narrower, toggle full width, center a column.
- **Stacks and tabs.** Stack a window into the column on its left or right, pop it back out, reorder inside the stack, make windows taller or shorter. Flip a column between stacked and tabbed; a clickable tab bar shows what's inside.
- **Pinned columns.** Hold a window at the left or right screen edge, full height, while the rest of the strip scrolls past.
- **Floating windows.** Float any window with one key. Dialogs, Quick Look, previews and fixed-size windows float automatically.
- **Native tabs as one column.** Finder, Terminal and other apps with macOS window tabs take a single column.
- **Window rules.** Per app: tile, float, or ignore; give an app a fixed slot on the strip and a default width.
- **Multiple displays.** Each display has its own strip, focus and scroll position. One shortcut moves a window to the next display, another moves focus there. Each Space keeps its own strip too.
- **No focus stealing.** A background app opening a window doesn't take your focus or scroll your strip.
- **Session restore.** Column order, widths, stacks, tabs and pins come back after SideScroll or the Mac restarts.
- **Mouse.** Drag a window onto another column to reorder; resize a window by hand to set its column width; optional focus-follows-mouse.
- **Look.** Configurable gaps and screen padding (down to zero), Dock-aware sizing, optional focus border, optional dimming of everything but the focused window, column position in the menu bar.
- **Shortcuts.** Every action is rebindable, one action can have several shortcuts, and keys are stored by physical position so they work on AZERTY, QWERTZ and Dvorak.
- **Strip indicator.** A frosted bar with each column's app icon appears while you navigate, shows where you are, then fades. Hold ⌃⌥ to keep it up; click a tile to jump there, drag a tile to reorder columns.
- **Apps that refuse a size.** If an app won't go narrower than its minimum, SideScroll lets it keep its size and lays out around it instead of fighting.
- **Ready after sleep.** After sleep, a locked screen or displays waking up, SideScroll sets itself up again on its own.
- **Native fullscreen left alone.** Fullscreen windows leave the strip and come back when you exit fullscreen.
- **Guided start and Mac Setup.** The first run teaches the strip and five shortcuts. Mac Setup checks your macOS settings and warns when another window manager (Rectangle, Magnet, Amethyst, AeroSpace, yabai…) is running.
- **Settings apply instantly.** No Save button, no restart.
- **Mouse follows focus** (optional), alongside focus follows mouse.
- **Automation.** A `sidescroll://` URL scheme, a `sidescroll` command-line tool and Raycast script commands.

## Default shortcuts

⌃ = Control, ⌥ = Option, ⇧ = Shift. All of them can be changed in Settings → Shortcuts.

| Action | Shortcut |
| --- | --- |
| Focus column left / right | ⌃⌥H / ⌃⌥L or ⌃⌥← / ⌃⌥→ |
| Focus window up / down in a stack | ⌃⌥K / ⌃⌥J or ⌃⌥↑ / ⌃⌥↓ |
| Move column left / right | ⌃⌥⇧H / ⌃⌥⇧L or ⌃⌥⇧← / ⌃⌥⇧→ |
| Move window up / down in a stack | ⌃⌥⇧K / ⌃⌥⇧J or ⌃⌥⇧↑ / ⌃⌥⇧↓ |
| Focus column 1–9 | ⌃⌥1 … ⌃⌥9 |
| Move column to position 1–9 | ⌃⌥⇧1 … ⌃⌥⇧9 |
| Focus first / last column | ⌃⌥Home / ⌃⌥End |
| Cycle width presets | ⌃⌥R |
| Wider / narrower | ⌃⌥= / ⌃⌥- |
| Toggle full width | ⌃⌥F |
| Center column | ⌃⌥C |
| Taller / shorter in a stack | ⌃⌥⇧= / ⌃⌥⇧- |
| Reset heights in a stack | ⌃⌥⇧R |
| Stack into left / right column | ⌃⌥[ / ⌃⌥] |
| Pop out to the left / right | ⌃⌥⇧[ / ⌃⌥⇧] |
| Toggle tabbed column | ⌃⌥⇧T |
| Float / unfloat window | ⌃⌥T |
| Pin to left / right edge (same key unpins) | ⌃⌥P / ⌃⌥⇧P |
| Focus next display | ⌃⌥D |
| Send window to next display | ⌃⌥N or ⌃⌥⇧D |
| Re-tile everything | ⌃⌥⇧0 |
| Pause / resume tiling, close window | unbound; set them in Settings |

## Automation

Every action has a URL, so anything that can open a link can drive SideScroll:

```bash
open -g sidescroll://focus-right
open -g sidescroll://cycle-width
open -g sidescroll://pause      # also: resume, toggle, settings
```

The installer links a `sidescroll` command (or use Settings → General → Install Command-Line Tool):

```bash
sidescroll focus-left
sidescroll move-to-next-display
sidescroll --list               # every command
```

For Raycast, add the [`raycast`](raycast) folder under Settings → Extensions → Script Commands. Closing windows is deliberately not available from URLs, so a link can never close your work.

## Build from source

Needs Xcode or the Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/TCYTseven/SideScrollMac.git
cd SideScrollMac
swift test                 # model and layout tests
scripts/build-app.sh       # -> build/SideScroll.app (universal)
scripts/package.sh         # -> dist/SideScroll.zip, dist/SideScroll.dmg
open build/SideScroll.app
```

`ARCHS=arm64 scripts/build-app.sh` builds for one architecture only. Every push to `main` builds on GitHub Actions and publishes a release that the installer and the in-app updater pick up.

### Layout

| Path | What |
| --- | --- |
| `Sources/SideScrollCore` | Strip model, layout maths, springs, settings, shortcuts, session restore. No AppKit; unit tested. |
| `Sources/SideScroll` | The app: Accessibility window control, observers, animation, hotkeys, trackpad, overlays, settings UI. |
| `Sources/CMultitouch` | Small C bridge to macOS's trackpad touch stream for multi-finger swipes. |
| `scripts/` | Build and packaging. |
| `install.sh`, `uninstall.sh` | One-line install and removal. |

## Notes

- Settings, shortcuts and the saved session are JSON files in `~/Library/Application Support/SideScroll`.
- Builds are signed ad hoc, so after an update macOS asks for Accessibility access again. The installer clears the old entry so the prompt comes up cleanly.
- macOS won't let a window go fully off screen, so scrolled-away windows are parked with one point showing at the screen edge (on a side with no neighbouring display).
- Quitting SideScroll (including `kill` / `pkill`) moves every parked window back onto the screen.
- Updates from the menu download the release zip, verify its SHA-256 against the digest GitHub publishes and check it's a SideScroll bundle before replacing the app. No downloaded script is executed.

## License

MIT
