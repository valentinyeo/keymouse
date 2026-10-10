# keymouse

Drive the Windows mouse from the keyboard. Hold **Right Ctrl**, then use WASD with your left hand.
It's a single ~105 KB native exe (Zig + raw Win32) with no runtime and no installer.

## Keys (while holding the trigger)

| Key | Action |
|---|---|
| W A S D | move cursor (accelerates while held, diagonals work) |
| Space | precision mode (slow) |
| Q | left click; hold to drag |
| E | right click |
| R / F | scroll up / down (repeats while held) |
| G | element hints (see below) |
| T | grid hints |

Trigger (set in `keymouse.ini`): `rctrl` (default), `ralt`, or `capslock`.
Don't use `ralt` on layouts where Right Alt is AltGr (German, for example).

## Hints (Right Ctrl+G)

Puts small labels on the clickable elements of the foreground window and the taskbar: links, buttons, tabs, menu items, inputs.
The elements come from UI Automation, the Windows accessibility API.
Type a label:
- **Right Ctrl already released:** the cursor jumps there and clicks, like Vimium.
- **Still holding Right Ctrl:** the cursor jumps there without clicking, so you can fine-tune with WASD and click with Q.

Esc cancels. Backspace undoes a letter.
If no elements are found (games, canvas apps), it falls back to a screen grid. Right Ctrl+T always shows the grid.

## How it works

No low-level keyboard hook (`WH_KEYBOARD_LL`).
- **Trigger:** Right Ctrl/Alt is watched through Raw Input, which is passive, can't block input, and tells left from right. It isn't swallowed; Right Ctrl alone does nothing in apps.
- **Action keys:** while the trigger is held, they're registered as `RegisterHotKey` hotkeys under each modifier combo, so they never reach the focused app.
- **Clicks and scroll:** keymouse logically releases Ctrl before sending them, so you don't get Ctrl+click or Ctrl+wheel zoom.
- **Polling:** key state is read with `GetAsyncKeyState` on a 125 Hz high-resolution timer that only runs in mouse mode.

## Build

```
zig build            # Zig 0.16, ReleaseSmall by default -> zig-out/bin/keymouse.exe
```

## Usage

Run `keymouse.exe`. A tray icon appears with Pause, Start with Windows, Edit config, and Exit.
On first run it writes `keymouse.ini` next to the exe. Restart after editing it.

## Limitations

- Clicks into elevated (admin) windows are blocked by UIPI unless keymouse also runs elevated.
- Chromium browsers build their accessibility tree on first request, so the first hint pass on a page can find fewer elements than later passes.
