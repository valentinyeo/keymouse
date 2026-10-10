const std = @import("std");
const win32 = @import("win32.zig");

pub const Activation = enum { capslock, shift_enter, both };

pub const Config = struct {
    activation: Activation = .capslock,
    /// Cursor speed (physical px/s) when a direction key is first pressed.
    speed_start: f32 = 400,
    /// Cursor speed after `accel_ms` of holding.
    speed_max: f32 = 2400,
    accel_ms: f32 = 350,
    /// Speed multiplier while Space is held.
    precision_factor: f32 = 0.25,
    /// Wheel repeat interval while R/F is held.
    scroll_repeat_ms: f32 = 60,
};

const default_ini =
    \\; keymouse config. Restart keymouse (tray > Exit, relaunch) after editing.
    \\;
    \\; activation: capslock | shift_enter | both
    \\;   capslock    - hold CapsLock (CapsLock no longer toggles caps)
    \\;   shift_enter - hold Shift+Enter (WARNING: swallows Shift+Enter in every app)
    \\activation=capslock
    \\
    \\; cursor speed in physical pixels per second
    \\speed_start=400
    \\speed_max=2400
    \\accel_ms=350
    \\; speed multiplier while Space is held
    \\precision_factor=0.25
    \\scroll_repeat_ms=60
    \\
;

/// Fills `out` with "<exe dir>\keymouse.ini". Returns false on failure.
pub fn iniPath(out: *[520]u16) bool {
    const n = win32.GetModuleFileNameW(null, out, 500);
    if (n == 0 or n >= 500) return false;
    var i: usize = n;
    while (i > 0 and out[i - 1] != '\\') i -= 1;
    const name = std.unicode.utf8ToUtf16LeStringLiteral("keymouse.ini");
    for (name, 0..) |c, j| out[i + j] = c;
    out[i + name.len] = 0;
    return true;
}

pub fn load() Config {
    var cfg = Config{};
    var path: [520]u16 = undefined;
    if (!iniPath(&path)) return cfg;
    const p: [*:0]const u16 = @ptrCast(&path);

    var h = win32.CreateFileW(p, win32.GENERIC_READ, win32.FILE_SHARE_READ, null, win32.OPEN_EXISTING, win32.FILE_ATTRIBUTE_NORMAL, null);
    if (h == win32.INVALID_HANDLE_VALUE) {
        // First run: write defaults so the user has something to edit.
        h = win32.CreateFileW(p, win32.GENERIC_WRITE, 0, null, win32.CREATE_NEW, win32.FILE_ATTRIBUTE_NORMAL, null);
        if (h != win32.INVALID_HANDLE_VALUE) {
            var written: win32.DWORD = 0;
            _ = win32.WriteFile(h, default_ini.ptr, default_ini.len, &written, null);
            _ = win32.CloseHandle(h);
        }
        return cfg;
    }
    defer _ = win32.CloseHandle(h);

    var buf: [4096]u8 = undefined;
    var len: win32.DWORD = 0;
    if (win32.ReadFile(h, &buf, buf.len, &len, null) == 0) return cfg;

    var lines = std.mem.tokenizeAny(u8, buf[0..len], "\r\n");
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t");
        if (line.len == 0 or line[0] == ';' or line[0] == '#') continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const val = std.mem.trim(u8, line[eq + 1 ..], " \t");
        if (std.mem.eql(u8, key, "activation")) {
            cfg.activation = std.meta.stringToEnum(Activation, val) orelse cfg.activation;
        } else inline for (.{ "speed_start", "speed_max", "accel_ms", "precision_factor", "scroll_repeat_ms" }) |name| {
            if (std.mem.eql(u8, key, name)) {
                if (std.fmt.parseFloat(f32, val)) |v| {
                    if (v > 0) @field(cfg, name) = v;
                } else |_| {}
            }
        }
    }
    return cfg;
}
