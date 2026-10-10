# keymouse

Keyboard-driven mouse for Windows. Zig 0.16, raw Win32, `zig build` -> `zig-out/bin/keymouse.exe`.

## Hard rule: never use WH_KEYBOARD_LL
Low-level keyboard hooks crash this machine (see zig-switch/CLAUDE.md). Keys are swallowed via
`RegisterHotKey` (action keys registered only while the trigger is held) and state is polled with
`GetAsyncKeyState`. Keep it that way.

## Notes
- The CapsLock hotkey does not stop the toggle flip. Presses are counted (`caps_presses`, GetKeyState is unreliable here); an odd count gets one injected tap on session end, and
  `caps_restores_pending` makes onHotkey ignore the resulting WM_HOTKEY.
- The exe is locked while running: kill `keymouse` before `zig build`.
- Bump `src/version.zig` on changes (shown in the tray menu).
