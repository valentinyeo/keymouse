# keymouse

Keyboard-driven mouse for Windows. Zig 0.16, raw Win32, `zig build` -> `zig-out/bin/keymouse.exe`.

## Hard rule: never use WH_KEYBOARD_LL
Low-level keyboard hooks crash this machine (see zig-switch/CLAUDE.md). Instead:
- Right Ctrl/Alt trigger: Raw Input (`RIDEV_INPUTSINK`), not swallowed. Our own injected keys carry
  `INJECT_TAG` in dwExtraInfo and are ignored by `onRawKey`.
- Action keys: `RegisterHotKey` under every combo in `action_mods`, only while the trigger is held.
- `liftTriggerModifier` injects a Right Ctrl/Alt key-up before mouse events (no Ctrl+click / zoom).
- CapsLock mode: hotkey can't stop the toggle flip; presses are counted (`caps_presses`) and an odd
  count gets one injected tap on session end.
- RegisterHotKey can't trigger on a lone RAlt/RCtrl/PrtSc/Copilot key (probed 2026-10-10); only
  Ctrl-as-hotkey and Apps fire, and a Ctrl hotkey would break Ctrl+C. Hence raw input.

## Hints
- `uia.zig`: raw COM vtable calls into IUIAutomation (indices from mingw uiautomationclient.h).
  FindAllBuildCache, cached BoundingRectangle only, AutomationElementMode_None.
- `hint.zig`: overlay over the whole virtual screen, color-key transparent; labels at element centres.

## Notes
- The exe is locked while running: kill `keymouse` before `zig build`.
- Bump `src/version.zig` on changes (shown in the tray menu).
