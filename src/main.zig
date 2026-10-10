//! keymouse: hold a trigger (Right Ctrl by default) and drive the mouse with
//! WASD.
//!
//! No WH_KEYBOARD_LL hook (those crash this machine). Instead:
//!   - Right Ctrl / Right Alt are watched with Raw Input (passive, can't block
//!     input, tells left from right). The trigger itself isn't swallowed; alone
//!     it does nothing in apps. CapsLock mode uses a RegisterHotKey hotkey.
//!   - while the trigger is held, the action keys (WASD etc.) are registered as
//!     hotkeys under every relevant modifier combo, so they never reach the
//!     focused app;
//!   - before mouse buttons/wheel are sent, the trigger modifier is released
//!     logically, so a click isn't a Ctrl+click and a scroll isn't a zoom;
//!   - action key hold/release state comes from polling GetAsyncKeyState on a
//!     high-resolution waitable timer, which only runs while mouse mode is on.
//! Idle cost is near zero: the thread sleeps in MsgWaitForMultipleObjects and
//! only wakes briefly for raw keyboard events.

const std = @import("std");
const win32 = @import("win32.zig");
const config = @import("config.zig");
const hint = @import("hint.zig");
const version = @import("version.zig").version;
const L = win32.L;

const HK_CAPSLOCK: i32 = 1;
const HK_ACTION_BASE: i32 = 100; // + modifier combo * 32 + key index

// Action keys are swallowed under each of these, since the trigger modifier
// (and Shift for convenience) may be logically down when they're pressed.
const action_mods = [_]win32.UINT{
    0,
    win32.MOD_SHIFT,
    win32.MOD_CONTROL,
    win32.MOD_CONTROL | win32.MOD_SHIFT,
    win32.MOD_ALT,
    win32.MOD_ALT | win32.MOD_SHIFT,
    win32.MOD_CONTROL | win32.MOD_ALT,
};

/// dwExtraInfo on keys we inject, so the raw input handler ignores them.
const INJECT_TAG: usize = 0x4B4D;
/// Unassigned VK, tapped so releasing a lone Alt doesn't open the menu bar.
const VK_MASK: u16 = 0xE8;

const Key = struct {
    const W = 'W';
    const A = 'A';
    const S = 'S';
    const D = 'D';
    const LEFT_CLICK = 'Q';
    const RIGHT_CLICK = 'E';
    const SCROLL_UP = 'R';
    const SCROLL_DOWN = 'F';
    const PRECISION = win32.VK_SPACE;
    const HINT = 'G';
    const GRID = 'T';
};

const action_keys = [_]i32{ Key.W, Key.A, Key.S, Key.D, Key.LEFT_CLICK, Key.RIGHT_CLICK, Key.SCROLL_UP, Key.SCROLL_DOWN, Key.PRECISION, Key.HINT, Key.GRID };

const Trigger = enum { none, capslock, key };

const WM_TRAY: win32.UINT = win32.WM_APP + 1;
const CMD_PAUSE: usize = 1;
const CMD_AUTOSTART: usize = 2;
const CMD_CONFIG: usize = 3;
const CMD_EXIT: usize = 4;

const TICK_100NS: i64 = 80_000; // 8 ms -> ~125 Hz cursor updates

var cfg: config.Config = .{};
var hwnd: win32.HWND = undefined;
var timer: ?win32.HANDLE = null;
var qpc_freq: f32 = 1;

var paused = false;
var trigger: Trigger = .none;
var last_tick: i64 = 0;
var move_held_s: f32 = 0;
var pos_x: f32 = 0;
var pos_y: f32 = 0;
var last_set: win32.POINT = .{ .x = 0, .y = 0 };
var left_down = false;
var right_down = false;
var scroll_wait_s: f32 = 0;
var hint_was_down = false;
var grid_was_down = false;
var raw_trigger_down = false; // physical state of Right Ctrl / Right Alt
// The CapsLock hotkey swallows the key, but Windows still flips the toggle
// state. Reading that state back (GetKeyState) is unreliable from a thread
// that never sees the key, so count the presses instead: an odd count at the
// end of a session means one injected tap restores the original state. That
// tap fires our own hotkey, which caps_restores_pending tells onHotkey to skip.
var caps_presses: u32 = 0;
var caps_restores_pending: u32 = 0;

pub fn main() void {
    _ = win32.CreateMutexW(null, 0, L("keymouse-single-instance"));
    if (win32.GetLastError() == win32.ERROR_ALREADY_EXISTS) return;

    _ = win32.SetProcessDpiAwarenessContext(win32.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    cfg = config.load();
    hint.init();

    var freq: i64 = 1;
    _ = win32.QueryPerformanceFrequency(&freq);
    qpc_freq = @floatFromInt(freq);

    timer = win32.CreateWaitableTimerExW(null, null, win32.CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, win32.TIMER_ALL_ACCESS) orelse
        win32.CreateWaitableTimerExW(null, null, 0, win32.TIMER_ALL_ACCESS);

    const hinst = win32.GetModuleHandleW(null);
    const wc = win32.WNDCLASSEXW{ .lpfnWndProc = wndProc, .hInstance = hinst, .lpszClassName = L("keymouse") };
    _ = win32.RegisterClassExW(&wc);
    hwnd = win32.CreateWindowExW(0, L("keymouse"), L("keymouse"), 0, 0, 0, 0, 0, null, null, hinst, null) orelse return;

    if (!registerTriggers()) {
        _ = win32.MessageBoxW(null, L("keymouse could not register its trigger key."), L("keymouse"), 0x10);
        return;
    }
    trayAdd();
    defer trayRemove();

    var msg: win32.MSG = undefined;
    while (true) {
        const n: win32.DWORD = if (trigger != .none and !hint.isOpen() and timer != null) 1 else 0;
        const handles = [_]win32.HANDLE{timer orelse undefined};
        const r = win32.MsgWaitForMultipleObjects(n, &handles, 0, win32.INFINITE, win32.QS_ALLINPUT);
        if (n == 1 and r == win32.WAIT_OBJECT_0) {
            tick();
            continue;
        }
        while (win32.PeekMessageW(&msg, null, 0, 0, win32.PM_REMOVE) != 0) {
            if (msg.message == win32.WM_QUIT) {
                deactivate();
                return;
            }
            if (msg.message == win32.WM_HOTKEY) {
                onHotkey(@intCast(msg.wParam));
            } else {
                _ = win32.TranslateMessage(&msg);
                _ = win32.DispatchMessageW(&msg);
            }
        }
    }
}

// ---------------------------------------------------------------- triggers

fn registerTriggers() bool {
    if (cfg.activation == .capslock)
        return win32.RegisterHotKey(null, HK_CAPSLOCK, win32.MOD_NOREPEAT, win32.VK_CAPITAL) != 0;
    // Keyboard raw input, delivered even when we're not focused.
    const dev = [_]win32.RAWINPUTDEVICE{.{ .usUsagePage = 1, .usUsage = 6, .dwFlags = win32.RIDEV_INPUTSINK, .hwndTarget = hwnd }};
    return win32.RegisterRawInputDevices(&dev, 1, @sizeOf(win32.RAWINPUTDEVICE)) != 0;
}

fn unregisterTriggers() void {
    // Raw input stays registered; activate() ignores it while paused.
    _ = win32.UnregisterHotKey(null, HK_CAPSLOCK);
}

fn onRawKey(lp: win32.LPARAM) void {
    var buf: win32.RAWINPUT = undefined;
    var size: win32.UINT = @sizeOf(win32.RAWINPUT);
    if (win32.GetRawInputData(lp, win32.RID_INPUT, &buf, &size, @sizeOf(win32.RAWINPUTHEADER)) == std.math.maxInt(u32)) return;
    if (buf.header.dwType != win32.RIM_TYPEKEYBOARD) return;
    const k = buf.keyboard;
    if (k.ExtraInformation == INJECT_TAG) return;
    const e0 = k.Flags & win32.RI_KEY_E0 != 0;
    const is_trigger = switch (cfg.activation) {
        .rctrl => k.VKey == win32.VK_RCONTROL or (k.VKey == win32.VK_CONTROL and e0),
        .ralt => k.VKey == win32.VK_RMENU or (k.VKey == win32.VK_MENU and e0),
        .capslock => false,
    };
    if (!is_trigger) return;
    if (k.Flags & win32.RI_KEY_BREAK != 0) {
        raw_trigger_down = false;
        if (trigger == .key and !hint.isOpen()) deactivate();
    } else if (!raw_trigger_down) { // ignore auto-repeat
        raw_trigger_down = true;
        if (cfg.activation == .ralt and !paused) tapKey(VK_MASK);
        activate(.key);
    }
}

fn tapKey(vk: u16) void {
    const in = [_]win32.KEYINPUT{
        .{ .ki = .{ .wVk = vk, .dwExtraInfo = INJECT_TAG } },
        .{ .ki = .{ .wVk = vk, .dwFlags = win32.KEYEVENTF_KEYUP, .dwExtraInfo = INJECT_TAG } },
    };
    _ = win32.SendInput(2, @ptrCast(&in), @sizeOf(win32.INPUT));
}

/// Logically lifts a held Right Ctrl/Alt so injected clicks and wheel events
/// arrive unmodified. Auto-repeat puts it back down, so this runs before every
/// mouse event and on each tick while a button is held.
fn liftTriggerModifier() void {
    if (trigger != .key) return;
    const vk: u16 = if (cfg.activation == .ralt) win32.VK_RMENU else win32.VK_RCONTROL;
    if (!down(vk)) return;
    const in = [_]win32.KEYINPUT{.{ .ki = .{ .wVk = vk, .dwFlags = win32.KEYEVENTF_KEYUP | win32.KEYEVENTF_EXTENDEDKEY, .dwExtraInfo = INJECT_TAG } }};
    _ = win32.SendInput(1, @ptrCast(&in), @sizeOf(win32.INPUT));
}

fn onHotkey(id: i32) void {
    switch (id) {
        HK_CAPSLOCK => {
            if (caps_restores_pending > 0) {
                caps_restores_pending -= 1;
                return;
            }
            if (trigger == .none and !paused) caps_presses = 0;
            caps_presses += 1;
            activate(.capslock);
        },
        else => {}, // action keys: state is read by polling in tick()
    }
}

fn down(vk: i32) bool {
    return win32.GetAsyncKeyState(vk) < 0;
}

fn triggerHeld() bool {
    return switch (trigger) {
        .none => false,
        .capslock => down(win32.VK_CAPITAL),
        .key => raw_trigger_down,
    };
}

fn activate(t: Trigger) void {
    if (trigger != .none or paused) return;
    trigger = t;
    startMouseLoop();
}

fn startMouseLoop() void {
    registerActionKeys();
    var p: win32.POINT = undefined;
    _ = win32.GetCursorPos(&p);
    syncPos(p);
    move_held_s = 0;
    scroll_wait_s = 0;
    hint_was_down = down(Key.HINT);
    grid_was_down = down(Key.GRID);
    _ = win32.QueryPerformanceCounter(&last_tick);
    armTimer();
}

fn actionId(m: usize, i: usize) i32 {
    return HK_ACTION_BASE + @as(i32, @intCast(m * 32 + i));
}

fn registerActionKeys() void {
    for (action_mods, 0..) |mods, m| for (action_keys, 0..) |vk, i| {
        _ = win32.RegisterHotKey(null, actionId(m, i), mods, @intCast(vk));
    };
}

fn unregisterActionKeys() void {
    for (0..action_mods.len) |m| for (0..action_keys.len) |i| {
        _ = win32.UnregisterHotKey(null, actionId(m, i));
    };
}

fn releaseButtons() void {
    // Never leave a button stuck down when the trigger is released mid-drag.
    if (left_down) sendMouse(win32.MOUSEEVENTF_LEFTUP, 0);
    if (right_down) sendMouse(win32.MOUSEEVENTF_RIGHTUP, 0);
    left_down = false;
    right_down = false;
}

fn deactivate() void {
    if (trigger == .none) return;
    trigger = .none;
    unregisterActionKeys();
    releaseButtons();
    restoreCapsToggle();
}

// The overlay needs the letter keys, so mouse mode's hotkeys are dropped while
// it is open. The trigger stays "active" so a new trigger press is ignored.
fn enterHint(kind: hint.Kind) void {
    unregisterActionKeys();
    releaseButtons();
    hint.open(kind, onHintDone);
    if (!hint.isOpen()) onHintDone(null);
}

fn onHintDone(result: ?hint.Result) void {
    if (result) |r| _ = win32.SetCursorPos(r.p.x, r.p.y);
    if (trigger == .none) return;
    // Still holding the trigger: continue in mouse mode to fine-tune, no click.
    if (triggerHeld()) return startMouseLoop();
    deactivate();
    // Trigger already released: an element hint clicks it, like Vimium.
    if (result) |r| if (r.clickable) {
        sendMouse(win32.MOUSEEVENTF_LEFTDOWN, 0);
        sendMouse(win32.MOUSEEVENTF_LEFTUP, 0);
    };
}

fn restoreCapsToggle() void {
    defer caps_presses = 0;
    if (caps_presses % 2 == 0) return;
    caps_restores_pending += 1;
    tapKey(win32.VK_CAPITAL);
}

// ---------------------------------------------------------------- mouse loop

fn armTimer() void {
    const due: i64 = -TICK_100NS; // negative = relative
    if (timer) |t| _ = win32.SetWaitableTimer(t, &due, 0, null, null, 0);
}

fn syncPos(p: win32.POINT) void {
    pos_x = @floatFromInt(p.x);
    pos_y = @floatFromInt(p.y);
    last_set = p;
}

fn tick() void {
    if (!triggerHeld()) {
        deactivate();
        return;
    }
    var now: i64 = 0;
    _ = win32.QueryPerformanceCounter(&now);
    const dt = @min(@as(f32, @floatFromInt(now - last_tick)) / qpc_freq, 0.05);
    last_tick = now;

    // Movement
    var dx: f32 = 0;
    var dy: f32 = 0;
    if (down(Key.A)) dx -= 1;
    if (down(Key.D)) dx += 1;
    if (down(Key.W)) dy -= 1;
    if (down(Key.S)) dy += 1;
    if (dx != 0 or dy != 0) {
        var p: win32.POINT = undefined;
        _ = win32.GetCursorPos(&p);
        // The physical mouse moved (or the cursor got clamped): follow it.
        if (p.x != last_set.x or p.y != last_set.y) syncPos(p);

        move_held_s += dt;
        const ramp = @min(move_held_s * 1000 / cfg.accel_ms, 1);
        var speed = cfg.speed_start + (cfg.speed_max - cfg.speed_start) * ramp * ramp;
        if (down(Key.PRECISION)) speed *= cfg.precision_factor;
        const norm: f32 = if (dx != 0 and dy != 0) std.math.sqrt1_2 else 1;
        pos_x += dx * norm * speed * dt;
        pos_y += dy * norm * speed * dt;
        const nx: i32 = @intFromFloat(@round(pos_x));
        const ny: i32 = @intFromFloat(@round(pos_y));
        if (nx != last_set.x or ny != last_set.y) {
            _ = win32.SetCursorPos(nx, ny);
            // Read back: Windows clamps at screen edges; don't accumulate past it.
            _ = win32.GetCursorPos(&p);
            if (p.x != nx) pos_x = @floatFromInt(p.x);
            if (p.y != ny) pos_y = @floatFromInt(p.y);
            last_set = p;
        }
    } else {
        move_held_s = 0;
    }

    const hint_down = down(Key.HINT);
    const grid_down = down(Key.GRID);
    defer hint_was_down = hint_down;
    defer grid_was_down = grid_down;
    if (hint_down and !hint_was_down) return enterHint(.elements);
    if (grid_down and !grid_was_down) return enterHint(.grid);

    if (left_down or right_down) liftTriggerModifier();

    // Buttons: press on key down, release on key up, so hold = drag.
    button(Key.LEFT_CLICK, &left_down, win32.MOUSEEVENTF_LEFTDOWN, win32.MOUSEEVENTF_LEFTUP);
    button(Key.RIGHT_CLICK, &right_down, win32.MOUSEEVENTF_RIGHTDOWN, win32.MOUSEEVENTF_RIGHTUP);

    // Scroll: one notch immediately, then repeat while held.
    const up = down(Key.SCROLL_UP);
    const dn = down(Key.SCROLL_DOWN);
    if (up != dn) {
        scroll_wait_s -= dt;
        if (scroll_wait_s <= 0) {
            sendMouse(win32.MOUSEEVENTF_WHEEL, if (up) 120 else @bitCast(@as(i32, -120)));
            scroll_wait_s = cfg.scroll_repeat_ms / 1000;
        }
    } else {
        scroll_wait_s = 0;
    }

    armTimer();
}

fn button(vk: i32, state: *bool, down_flag: u32, up_flag: u32) void {
    const now = down(vk);
    if (now == state.*) return;
    state.* = now;
    sendMouse(if (now) down_flag else up_flag, 0);
}

fn sendMouse(flags: u32, data: u32) void {
    liftTriggerModifier();
    const in = [_]win32.INPUT{.{ .mi = .{ .dwFlags = flags, .mouseData = data } }};
    _ = win32.SendInput(1, &in, @sizeOf(win32.INPUT));
}

// ---------------------------------------------------------------- tray

fn trayData() win32.NOTIFYICONDATAW {
    var nid = win32.NOTIFYICONDATAW{
        .hWnd = hwnd,
        .uID = 1,
        .uFlags = win32.NIF_MESSAGE | win32.NIF_ICON | win32.NIF_TIP,
        .uCallbackMessage = WM_TRAY,
        .hIcon = win32.LoadIconW(null, win32.IDI_APPLICATION),
    };
    const tip = if (paused) "keymouse (paused)" else "keymouse";
    for (tip, 0..) |c, i| nid.szTip[i] = c;
    return nid;
}

fn trayAdd() void {
    var nid = trayData();
    _ = win32.Shell_NotifyIconW(win32.NIM_ADD, &nid);
}

fn trayRemove() void {
    var nid = trayData();
    _ = win32.Shell_NotifyIconW(win32.NIM_DELETE, &nid);
}

fn trayMenu() void {
    const menu = win32.CreatePopupMenu() orelse return;
    defer _ = win32.DestroyMenu(menu);
    const title = comptime L("keymouse v" ++ version);
    const usage = switch (cfg.activation) {
        .rctrl => L("Hold Right Ctrl: WASD move, Q/E click, R/F scroll, Space slow, G hints, T grid"),
        .ralt => L("Hold Right Alt: WASD move, Q/E click, R/F scroll, Space slow, G hints, T grid"),
        .capslock => L("Hold CapsLock: WASD move, Q/E click, R/F scroll, Space slow, G hints, T grid"),
    };
    _ = win32.AppendMenuW(menu, win32.MF_STRING | win32.MF_GRAYED, 0, title);
    _ = win32.AppendMenuW(menu, win32.MF_STRING | win32.MF_GRAYED, 0, usage);
    _ = win32.AppendMenuW(menu, win32.MF_SEPARATOR, 0, null);
    _ = win32.AppendMenuW(menu, win32.MF_STRING | (if (paused) win32.MF_CHECKED else 0), CMD_PAUSE, L("Paused"));
    _ = win32.AppendMenuW(menu, win32.MF_STRING | (if (autostartEnabled()) win32.MF_CHECKED else 0), CMD_AUTOSTART, L("Start with Windows"));
    _ = win32.AppendMenuW(menu, win32.MF_STRING, CMD_CONFIG, L("Edit config (restart to apply)"));
    _ = win32.AppendMenuW(menu, win32.MF_SEPARATOR, 0, null);
    _ = win32.AppendMenuW(menu, win32.MF_STRING, CMD_EXIT, L("Exit"));

    var p: win32.POINT = undefined;
    _ = win32.GetCursorPos(&p);
    _ = win32.SetForegroundWindow(hwnd);
    const cmd = win32.TrackPopupMenu(menu, win32.TPM_RIGHTBUTTON | win32.TPM_RETURNCMD | win32.TPM_NONOTIFY, p.x, p.y, 0, hwnd, null);
    _ = win32.PostMessageW(hwnd, win32.WM_NULL, 0, 0);
    switch (@as(usize, @intCast(cmd))) {
        CMD_PAUSE => {
            paused = !paused;
            if (paused) {
                deactivate();
                unregisterTriggers();
            } else _ = registerTriggers();
            var nid = trayData();
            _ = win32.Shell_NotifyIconW(win32.NIM_MODIFY, &nid);
        },
        CMD_AUTOSTART => setAutostart(!autostartEnabled()),
        CMD_CONFIG => {
            var path: [520]u16 = undefined;
            if (config.iniPath(&path)) _ = win32.ShellExecuteW(null, L("open"), @ptrCast(&path), null, null, win32.SW_SHOWNORMAL);
        },
        CMD_EXIT => win32.PostQuitMessage(0),
        else => {},
    }
}

fn wndProc(h: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM) callconv(.winapi) win32.LRESULT {
    if (msg == win32.WM_INPUT) {
        onRawKey(lp);
        return win32.DefWindowProcW(h, msg, wp, lp);
    }
    if (msg == WM_TRAY) {
        const ev: win32.UINT = @truncate(@as(usize, @bitCast(lp)));
        if (ev == win32.WM_RBUTTONUP or ev == win32.WM_LBUTTONUP) trayMenu();
        return 0;
    }
    return win32.DefWindowProcW(h, msg, wp, lp);
}

// ---------------------------------------------------------------- autostart

const run_key = L("Software\\Microsoft\\Windows\\CurrentVersion\\Run");
const run_value = L("keymouse");

fn autostartEnabled() bool {
    var key: win32.HKEY = undefined;
    if (win32.RegOpenKeyExW(win32.HKEY_CURRENT_USER, run_key, 0, win32.KEY_QUERY_VALUE, &key) != 0) return false;
    defer _ = win32.RegCloseKey(key);
    return win32.RegQueryValueExW(key, run_value, null, null, null, null) == 0;
}

fn setAutostart(on: bool) void {
    var key: win32.HKEY = undefined;
    if (win32.RegOpenKeyExW(win32.HKEY_CURRENT_USER, run_key, 0, win32.KEY_SET_VALUE, &key) != 0) return;
    defer _ = win32.RegCloseKey(key);
    if (!on) {
        _ = win32.RegDeleteValueW(key, run_value);
        return;
    }
    var path: [512]u16 = undefined;
    const n = win32.GetModuleFileNameW(null, &path, 510);
    if (n == 0 or n >= 510) return;
    path[n] = 0;
    _ = win32.RegSetValueExW(key, run_value, 0, win32.REG_SZ, @ptrCast(&path), (n + 1) * 2);
}
