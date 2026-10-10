# keymouse

Drive the Windows mouse from the keyboard. Hold a trigger key, then use WASD.
It's a single ~90 KB native exe (Zig + raw Win32) with no runtime and no installer.

## Keys (while holding the trigger)

| Key | Action |
|---|---|
| W A S D | move cursor (accelerates while held, diagonals work) |
| Space | precision mode (slow) |
| Q | left click; hold to drag |
| E | right click |
| R / F | scroll up / down (repeats while held) |
| G | hint mode (see below) |

## Hint mode (CapsLock+G)

Covers the current monitor with a grid of 2-letter labels, like Vimium but for the whole screen.
Type a label and the cursor jumps to that cell's center.
If you're still holding CapsLock, keep going with WASD to fine-tune, then Q to click.
Esc cancels. Backspace undoes the first letter.

Trigger (set in `keymouse.ini`): `capslock` (default), `shift_enter`, or `both`.
With `capslock` the CapsLock toggle state is preserved, so holding it never leaves caps on.

## How it works

No low-level keyboard hook (`WH_KEYBOARD_LL`). The trigger is a `RegisterHotKey` hotkey.
While it's held, the action keys are registered as hotkeys too, so they never reach the focused app.
Key hold/release is polled with `GetAsyncKeyState` on a 125 Hz high-resolution timer that only runs in mouse mode.
When idle the process sleeps in `MsgWaitForMultipleObjects` and uses no CPU.

## Build

```
zig build            # Zig 0.16, ReleaseSmall by default -> zig-out/bin/keymouse.exe
```

## Usage

Run `keymouse.exe`. A tray icon appears with Pause, Start with Windows, Edit config, and Exit.
On first run it writes `keymouse.ini` next to the exe. Restart after editing it.

## Limitations

- `shift_enter` swallows Shift+Enter in every app (a newline in chat apps, for example). `RegisterHotKey` can't tell left Shift from right Shift.
- Clicks into elevated (admin) windows are blocked by UIPI unless keymouse also runs elevated.
- The CapsLock LED flickers briefly while CapsLock is held.
