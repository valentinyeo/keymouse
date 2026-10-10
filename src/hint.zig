//! Hint mode: a full-monitor overlay of 2-letter labels laid out on a grid.
//! Typing a label jumps the cursor to that cell's centre. The overlay takes
//! keyboard focus and reads plain WM_KEYDOWN, so no hook is involved.

const std = @import("std");
const win32 = @import("win32.zig");
const L = win32.L;

const COLS = 26;
const MAX_ROWS = 26;
const KEY_COLOR = win32.rgb(255, 0, 255); // transparent background (color key)

var hwnd: ?win32.HWND = null;
var mon: win32.RECT = .{};
var rows: i32 = 1;
var first: ?u8 = null; // typed row letter, 0-based
var done_cb: *const fn () void = undefined;

pub fn isOpen() bool {
    return hwnd != null;
}

/// Opens the overlay on the monitor under the cursor. `on_done` runs after it
/// closes (jumped or cancelled).
pub fn open(on_done: *const fn () void) void {
    if (hwnd != null) return;
    done_cb = on_done;
    first = null;

    var p: win32.POINT = undefined;
    _ = win32.GetCursorPos(&p);
    var mi = win32.MONITORINFO{};
    const hm = win32.MonitorFromPoint(p, win32.MONITOR_DEFAULTTONEAREST) orelse return;
    if (win32.GetMonitorInfoW(hm, &mi) == 0) return;
    mon = mi.rcMonitor;
    const w = mon.right - mon.left;
    const h = mon.bottom - mon.top;
    // Near-square cells: 26 columns, rows scaled by aspect ratio.
    rows = std.math.clamp(@divTrunc(h * COLS + @divTrunc(w, 2), w), 1, MAX_ROWS);

    const hinst = win32.GetModuleHandleW(null);
    const S = struct {
        var registered = false;
    };
    if (!S.registered) {
        const wc = win32.WNDCLASSEXW{ .lpfnWndProc = wndProc, .hInstance = hinst, .lpszClassName = L("keymouse-hint") };
        _ = win32.RegisterClassExW(&wc);
        S.registered = true;
    }
    const h_wnd = win32.CreateWindowExW(
        win32.WS_EX_TOPMOST | win32.WS_EX_TOOLWINDOW | win32.WS_EX_LAYERED,
        L("keymouse-hint"),
        L("keymouse hints"),
        win32.WS_POPUP,
        mon.left,
        mon.top,
        w,
        h,
        null,
        null,
        hinst,
        null,
    ) orelse return;
    hwnd = h_wnd;
    _ = win32.SetLayeredWindowAttributes(h_wnd, KEY_COLOR, 235, win32.LWA_COLORKEY | win32.LWA_ALPHA);
    _ = win32.ShowWindow(h_wnd, win32.SW_SHOW);
    // Allowed: we just received the hotkey that opened us.
    _ = win32.SetForegroundWindow(h_wnd);
    _ = win32.SetFocus(h_wnd);
}

fn close(jump: ?win32.POINT) void {
    const h = hwnd orelse return;
    hwnd = null;
    _ = win32.DestroyWindow(h);
    if (jump) |p| _ = win32.SetCursorPos(p.x, p.y);
    done_cb();
}

fn cellRect(r: i32, c: i32) win32.RECT {
    const w = mon.right - mon.left;
    const h = mon.bottom - mon.top;
    return .{
        .left = @divTrunc(c * w, COLS),
        .top = @divTrunc(r * h, rows),
        .right = @divTrunc((c + 1) * w, COLS),
        .bottom = @divTrunc((r + 1) * h, rows),
    };
}

fn onKey(vk: usize) void {
    if (vk == win32.VK_ESCAPE) return close(null);
    if (vk == win32.VK_BACK) {
        if (first == null) return close(null);
        first = null;
        _ = win32.InvalidateRect(hwnd, null, 0);
        return;
    }
    if (vk < 'A' or vk > 'Z') return;
    const idx: u8 = @intCast(vk - 'A');
    if (first) |r| {
        if (idx >= COLS) return;
        const rc = cellRect(r, idx);
        close(.{ .x = mon.left + @divTrunc(rc.left + rc.right, 2), .y = mon.top + @divTrunc(rc.top + rc.bottom, 2) });
    } else {
        if (idx >= rows) return;
        first = idx;
        _ = win32.InvalidateRect(hwnd, null, 0);
    }
}

fn paint(h: win32.HWND) void {
    var ps: win32.PAINTSTRUCT = undefined;
    const dc = win32.BeginPaint(h, &ps) orelse return;
    defer _ = win32.EndPaint(h, &ps);
    const w = mon.right - mon.left;
    const ht = mon.bottom - mon.top;

    // Draw into a back buffer so the 400-odd labels appear in one blit.
    const mem = win32.CreateCompatibleDC(dc) orelse return;
    defer _ = win32.DeleteDC(mem);
    const bmp = win32.CreateCompatibleBitmap(dc, w, ht) orelse return;
    defer _ = win32.DeleteObject(bmp);
    _ = win32.SelectObject(mem, bmp);

    const bg = win32.CreateSolidBrush(KEY_COLOR) orelse return;
    defer _ = win32.DeleteObject(bg);
    const label_bg = win32.CreateSolidBrush(win32.rgb(255, 214, 51)) orelse return;
    defer _ = win32.DeleteObject(label_bg);
    const label_border = win32.CreateSolidBrush(win32.rgb(140, 100, 0)) orelse return;
    defer _ = win32.DeleteObject(label_border);

    _ = win32.FillRect(mem, &.{ .right = w, .bottom = ht }, bg);

    const cell_h = @divTrunc(ht, rows);
    const font = win32.CreateFontW(-@as(i32, @max(@divTrunc(cell_h * 30, 100), 10)), 0, 0, 0, win32.FW_BOLD, 0, 0, 0, 0, 0, 0, win32.CLEARTYPE_QUALITY, 0, L("Segoe UI")) orelse return;
    defer _ = win32.DeleteObject(font);
    _ = win32.SelectObject(mem, font);
    _ = win32.SetBkMode(mem, win32.TRANSPARENT);
    _ = win32.SetTextColor(mem, win32.rgb(20, 20, 20));

    const box_w = @divTrunc(@divTrunc(w, COLS) * 62, 100);
    const box_h = @divTrunc(cell_h * 48, 100);
    var r: i32 = 0;
    while (r < rows) : (r += 1) {
        if (first) |f| if (r != f) continue;
        var c: i32 = 0;
        while (c < COLS) : (c += 1) {
            const cell = cellRect(r, c);
            const cx = @divTrunc(cell.left + cell.right, 2);
            const cy = @divTrunc(cell.top + cell.bottom, 2);
            var box = win32.RECT{ .left = cx - @divTrunc(box_w, 2), .top = cy - @divTrunc(box_h, 2), .right = cx + @divTrunc(box_w, 2), .bottom = cy + @divTrunc(box_h, 2) };
            _ = win32.FillRect(mem, &box, label_border);
            var inner = win32.RECT{ .left = box.left + 1, .top = box.top + 1, .right = box.right - 1, .bottom = box.bottom - 1 };
            _ = win32.FillRect(mem, &inner, label_bg);
            const text = [2]u16{ @as(u16, 'A') + @as(u16, @intCast(r)), @as(u16, 'A') + @as(u16, @intCast(c)) };
            // After the first letter, show only the remaining one.
            if (first != null) {
                _ = win32.DrawTextW(mem, text[1..].ptr, 1, &box, win32.DT_CENTER | win32.DT_VCENTER | win32.DT_SINGLELINE | win32.DT_NOPREFIX);
            } else {
                _ = win32.DrawTextW(mem, &text, 2, &box, win32.DT_CENTER | win32.DT_VCENTER | win32.DT_SINGLELINE | win32.DT_NOPREFIX);
            }
        }
    }
    _ = win32.BitBlt(dc, 0, 0, w, ht, mem, 0, 0, win32.SRCCOPY);
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
