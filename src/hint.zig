//! Hint mode: small labels over the clickable elements of the foreground
//! window (via UI Automation) plus the taskbar. Typing a label jumps the
//! cursor there. Falls back to a screen grid when no elements are found
//! (games, canvas apps), and the grid can be requested directly.
//!
//! The overlay takes keyboard focus and reads plain WM_KEYDOWN, so no hook
//! is involved.

const std = @import("std");
const win32 = @import("win32.zig");
const uia = @import("uia.zig");
const L = win32.L;

pub const Kind = enum { elements, grid };
pub const Result = struct { p: win32.POINT, clickable: bool };

const MAX = 26 * 26;
const GRID_COLS = 26;
const KEY_COLOR = win32.rgb(255, 0, 255); // transparent background (color key)
// Home row first, so the most common labels are the easiest to type.
const element_alphabet = "ASDFJKLGHQWERUIOPTYZXCVBNM";
const grid_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
// Gradient from the hint's centre outwards (same ramp as mousemaster's example).
const palette = [_]u32{ 0xF97316, 0xEAB308, 0x84CC16, 0x22C55E, 0x14B8A6, 0x06B6D4, 0x3B82F6 };

var hwnd: ?win32.HWND = null;
var done_cb: *const fn (?Result) void = undefined;
var kind: Kind = .elements;
var pts: [MAX]win32.POINT = undefined;
var colors: [MAX]win32.COLORREF = undefined;
var count: usize = 0;
var alphabet: []const u8 = element_alphabet;
var label_len: usize = 1;
var typed: [2]u8 = undefined;
var typed_n: usize = 0;
var vs: win32.RECT = .{}; // virtual screen, overlay covers all of it
var scale: f32 = 1;

pub fn init() void {
    uia.init();
}

pub fn isOpen() bool {
    return hwnd != null;
}

/// Opens the overlay. `on_done` runs after it closes, with the target point,
/// or null when cancelled.
pub fn open(want: Kind, on_done: *const fn (?Result) void) void {
    if (hwnd != null) return;
    done_cb = on_done;
    typed_n = 0;
    count = 0;

    const fg = win32.GetForegroundWindow();
    const dpi = if (fg) |w| win32.GetDpiForWindow(w) else 0;
    scale = @as(f32, @floatFromInt(if (dpi == 0) 96 else dpi)) / 96;

    var region: win32.RECT = .{};
    kind = want;
    if (kind == .elements) {
        if (fg) |w| {
            _ = win32.GetWindowRect(w, &region);
            collectElements(w, region);
        }
        if (count == 0) kind = .grid;
    }
    if (kind == .grid) region = buildGrid();
    alphabet = if (kind == .grid) grid_alphabet else element_alphabet;
    label_len = if (count <= alphabet.len) 1 else 2;
    for (0..count) |i| colors[i] = gradient(pts[i], region);

    vs = .{
        .left = win32.GetSystemMetrics(win32.SM_XVIRTUALSCREEN),
        .top = win32.GetSystemMetrics(win32.SM_YVIRTUALSCREEN),
    };
    vs.right = vs.left + win32.GetSystemMetrics(win32.SM_CXVIRTUALSCREEN);
    vs.bottom = vs.top + win32.GetSystemMetrics(win32.SM_CYVIRTUALSCREEN);

    const hinst = win32.GetModuleHandleW(null);
    const S = struct {
        var registered = false;
    };
    if (!S.registered) {
        const wc = win32.WNDCLASSEXW{ .lpfnWndProc = wndProc, .hInstance = hinst, .lpszClassName = L("keymouse-hint") };
        _ = win32.RegisterClassExW(&wc);
        S.registered = true;
    }
    const h = win32.CreateWindowExW(
        win32.WS_EX_TOPMOST | win32.WS_EX_TOOLWINDOW | win32.WS_EX_LAYERED,
        L("keymouse-hint"),
        L("keymouse hints"),
        win32.WS_POPUP,
        vs.left,
        vs.top,
        vs.right - vs.left,
        vs.bottom - vs.top,
        null,
        null,
        hinst,
        null,
    ) orelse return;
    hwnd = h;
    _ = win32.SetLayeredWindowAttributes(h, KEY_COLOR, 0, win32.LWA_COLORKEY);
    _ = win32.ShowWindow(h, win32.SW_SHOW);
    // Allowed: we just received the hotkey that opened us.
    _ = win32.SetForegroundWindow(h);
    _ = win32.SetFocus(h);
}

// ---------------------------------------------------------------- targets

fn collectElements(fg: win32.HWND, region: win32.RECT) void {
    var rects: [1024]win32.RECT = undefined;
    var n: usize = 0;
    uia.collect(fg, &rects, &n);
    const fg_n = n;
    if (win32.FindWindowW(L("Shell_TrayWnd"), null)) |tb| if (tb != fg) uia.collect(tb, &rects, &n);

    const region_area = area(region);
    const min_gap: i32 = @intFromFloat(8 * scale);
    for (rects[0..n], 0..) |r, i| {
        // Skip containers that cover most of the window (documents, panes).
        if (i < fg_n and region_area > 0 and area(r) * 5 > region_area * 2) continue;
        const p = win32.POINT{ .x = @divTrunc(r.left + r.right, 2), .y = @divTrunc(r.top + r.bottom, 2) };
        if (i < fg_n and !inside(p, region)) continue;
        if (win32.MonitorFromPoint(p, win32.MONITOR_DEFAULTTONULL) == null) continue;
        // Nested elements (a link inside a list item) share a centre: keep one.
        var dup = false;
        for (pts[0..count]) |q| {
            if (@abs(q.x - p.x) < min_gap and @abs(q.y - p.y) < min_gap) {
                dup = true;
                break;
            }
        }
        if (dup) continue;
        pts[count] = p;
        count += 1;
        if (count == MAX) break;
    }
    // Reading order, so labels run left-to-right, top-to-bottom.
    std.mem.sort(win32.POINT, pts[0..count], {}, struct {
        fn lt(_: void, a: win32.POINT, b: win32.POINT) bool {
            const ra = @divTrunc(a.y, 16);
            const rb = @divTrunc(b.y, 16);
            return if (ra != rb) ra < rb else a.x < b.x;
        }
    }.lt);
}

fn buildGrid() win32.RECT {
    var c: win32.POINT = undefined;
    _ = win32.GetCursorPos(&c);
    var mi = win32.MONITORINFO{};
    const hm = win32.MonitorFromPoint(c, win32.MONITOR_DEFAULTTONEAREST) orelse return .{};
    if (win32.GetMonitorInfoW(hm, &mi) == 0) return .{};
    const m = mi.rcMonitor;
    const w = m.right - m.left;
    const h = m.bottom - m.top;
    // Near-square cells: 26 columns, rows scaled by aspect ratio.
    const rows: usize = @intCast(std.math.clamp(@divTrunc(h * GRID_COLS + @divTrunc(w, 2), w), 1, 26));
    count = 0;
    for (0..rows) |r| for (0..GRID_COLS) |col| {
        const ri: i32 = @intCast(r);
        const ci: i32 = @intCast(col);
        pts[count] = .{
            .x = m.left + @divTrunc((2 * ci + 1) * w, 2 * GRID_COLS),
            .y = m.top + @divTrunc((2 * ri + 1) * h, 2 * @as(i32, @intCast(rows))),
        };
        count += 1;
    };
    return m;
}

fn area(r: win32.RECT) i64 {
    return @as(i64, r.right - r.left) * @as(i64, r.bottom - r.top);
}

fn inside(p: win32.POINT, r: win32.RECT) bool {
    return p.x >= r.left and p.x < r.right and p.y >= r.top and p.y < r.bottom;
}

/// Colour by how far out the hint sits: palette[0] at the centre of
/// `region`, the last colour at any of its edges.
fn gradient(p: win32.POINT, region: win32.RECT) win32.COLORREF {
    const hw: f32 = @floatFromInt(@max(@divTrunc(region.right - region.left, 2), 1));
    const hh: f32 = @floatFromInt(@max(@divTrunc(region.bottom - region.top, 2), 1));
    const dx = @abs(@as(f32, @floatFromInt(p.x - @divTrunc(region.left + region.right, 2)))) / hw;
    const dy = @abs(@as(f32, @floatFromInt(p.y - @divTrunc(region.top + region.bottom, 2)))) / hh;
    const t = std.math.clamp(@max(dx, dy), 0, 1) * @as(f32, palette.len - 1);
    const i: usize = @min(@as(usize, @intFromFloat(t)), palette.len - 2);
    const f = t - @as(f32, @floatFromInt(i));
    const a = palette[i];
    const b = palette[i + 1];
    var out: [3]u8 = undefined;
    inline for (0..3) |k| {
        const sh = 16 - 8 * k;
        const ca: f32 = @floatFromInt((a >> sh) & 0xFF);
        const cb: f32 = @floatFromInt((b >> sh) & 0xFF);
        out[k] = @intFromFloat(ca + (cb - ca) * f);
    }
    return win32.rgb(out[0], out[1], out[2]);
}

// ---------------------------------------------------------------- input

fn labelOf(i: usize, buf: *[2]u8) []const u8 {
    if (label_len == 1) {
        buf[0] = alphabet[i];
        return buf[0..1];
    }
    buf[0] = alphabet[i / alphabet.len];
    buf[1] = alphabet[i % alphabet.len];
    return buf[0..2];
}

fn matches(i: usize) bool {
    var buf: [2]u8 = undefined;
    return std.mem.startsWith(u8, labelOf(i, &buf), typed[0..typed_n]);
}

fn close(result: ?Result) void {
    const h = hwnd orelse return;
    hwnd = null;
    _ = win32.DestroyWindow(h);
    done_cb(result);
}

fn onKey(vk: usize) void {
    if (vk == win32.VK_ESCAPE) return close(null);
    if (vk == win32.VK_BACK) {
        if (typed_n == 0) return close(null);
        typed_n -= 1;
        _ = win32.InvalidateRect(hwnd, null, 0);
        return;
    }
    if (vk < 'A' or vk > 'Z') return;
    typed[typed_n] = @intCast(vk);
    typed_n += 1;
    var hits: usize = 0;
    var last: usize = 0;
    for (0..count) |i| if (matches(i)) {
        hits += 1;
        last = i;
    };
    if (hits == 0) {
        typed_n -= 1; // not a label: ignore the key
        return;
    }
    if (typed_n == label_len) return close(.{ .p = pts[last], .clickable = kind == .elements });
    _ = win32.InvalidateRect(hwnd, null, 0);
}

// ---------------------------------------------------------------- drawing

fn px(v: f32) i32 {
    return @intFromFloat(@round(v * scale));
}

fn paint(h: win32.HWND) void {
    var ps: win32.PAINTSTRUCT = undefined;
    const dc = win32.BeginPaint(h, &ps) orelse return;
    defer _ = win32.EndPaint(h, &ps);
    const w = vs.right - vs.left;
    const ht = vs.bottom - vs.top;

    // Draw into a back buffer so all labels appear in one blit.
    const mem = win32.CreateCompatibleDC(dc) orelse return;
    defer _ = win32.DeleteDC(mem);
    const bmp = win32.CreateCompatibleBitmap(dc, w, ht) orelse return;
    defer _ = win32.DeleteObject(bmp);
    _ = win32.SelectObject(mem, bmp);

    const bg = win32.CreateSolidBrush(KEY_COLOR) orelse return;
    defer _ = win32.DeleteObject(bg);
    _ = win32.FillRect(mem, &.{ .right = w, .bottom = ht }, bg);

    const font = win32.CreateFontW(-px(if (kind == .grid) 15 else 13), 0, 0, 0, win32.FW_BOLD, 0, 0, 0, 0, 0, 0, win32.CLEARTYPE_QUALITY, 0, L("Segoe UI")) orelse return;
    defer _ = win32.DeleteObject(font);
    _ = win32.SelectObject(mem, font);
    _ = win32.SetBkMode(mem, win32.TRANSPARENT);
    _ = win32.SelectObject(mem, win32.GetStockObject(win32.DC_BRUSH).?);
    _ = win32.SelectObject(mem, win32.GetStockObject(win32.DC_PEN).?);

    // Box size from the widest label so every box is the same size.
    var size: win32.SIZE = .{};
    const probe = [2]u16{ 'W', 'W' };
    _ = win32.GetTextExtentPoint32W(mem, &probe, @intCast(label_len), &size);
    const bw = size.cx + px(8);
    const bh = size.cy + px(2);
    const radius = px(6);

    for (0..count) |i| {
        if (!matches(i)) continue;
        const cx = pts[i].x - vs.left;
        const cy = pts[i].y - vs.top;
        var box = win32.RECT{ .left = cx - @divTrunc(bw, 2), .top = cy - @divTrunc(bh, 2), .right = cx - @divTrunc(bw, 2) + bw, .bottom = cy - @divTrunc(bh, 2) + bh };
        const col = colors[i];
        _ = win32.SetDCBrushColor(mem, col);
        _ = win32.SetDCPenColor(mem, darken(col));
        _ = win32.RoundRect(mem, box.left, box.top, box.right, box.bottom, radius, radius);

        // Only the letters still to type.
        var buf: [2]u8 = undefined;
        const label = labelOf(i, &buf)[typed_n..];
        var text: [2]u16 = undefined;
        for (label, 0..) |ch, k| text[k] = ch;
        _ = win32.SetTextColor(mem, if (luma(col) > 150) win32.rgb(17, 17, 17) else win32.rgb(255, 255, 255));
        _ = win32.DrawTextW(mem, &text, @intCast(label.len), &box, win32.DT_CENTER | win32.DT_VCENTER | win32.DT_SINGLELINE | win32.DT_NOPREFIX);
    }
    _ = win32.BitBlt(dc, 0, 0, w, ht, mem, 0, 0, win32.SRCCOPY);
}

fn luma(c: win32.COLORREF) u32 {
    const r = c & 0xFF;
    const g = (c >> 8) & 0xFF;
    const b = (c >> 16) & 0xFF;
    return (r * 299 + g * 587 + b * 114) / 1000;
}

fn darken(c: win32.COLORREF) win32.COLORREF {
    const r: u8 = @intCast((c & 0xFF) * 3 / 5);
    const g: u8 = @intCast(((c >> 8) & 0xFF) * 3 / 5);
    const b: u8 = @intCast(((c >> 16) & 0xFF) * 3 / 5);
    return win32.rgb(r, g, b);
}

fn wndProc(h: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM) callconv(.winapi) win32.LRESULT {
    switch (msg) {
        win32.WM_PAINT => {
            paint(h);
            return 0;
        },
        win32.WM_ERASEBKGND => return 1,
        win32.WM_KEYDOWN, win32.WM_SYSKEYDOWN => {
            onKey(wp);
            return 0;
        },
        win32.WM_ACTIVATE => {
            // Lost focus (clicked elsewhere, Alt+Tab): cancel.
            if (wp & 0xFFFF == 0 and hwnd == h) close(null);
            return 0;
        },
        else => return win32.DefWindowProcW(h, msg, wp, lp),
    }
}
