const std = @import("std");

pub const HWND = std.os.windows.HWND;
pub const HINSTANCE = std.os.windows.HINSTANCE;
pub const HANDLE = std.os.windows.HANDLE;
pub const HICON = *opaque {};
pub const HMENU = *opaque {};
pub const HCURSOR = *opaque {};
pub const HBRUSH = *opaque {};
pub const HKEY = *opaque {};
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;
pub const BOOL = i32;
pub const DWORD = u32;
pub const UINT = u32;
pub const ATOM = u16;

pub const POINT = extern struct { x: i32, y: i32 };

pub const MSG = extern struct {
    hwnd: ?HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
    lPrivate: DWORD,
};

pub const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;

pub const WNDCLASSEXW = extern struct {
    cbSize: UINT = @sizeOf(WNDCLASSEXW),
    style: UINT = 0,
    lpfnWndProc: WNDPROC,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: ?HINSTANCE = null,
    hIcon: ?HICON = null,
    hCursor: ?HCURSOR = null,
    hbrBackground: ?HBRUSH = null,
    lpszMenuName: ?[*:0]const u16 = null,
    lpszClassName: [*:0]const u16,
    hIconSm: ?HICON = null,
};

pub const MOUSEINPUT = extern struct {
    dx: i32 = 0,
    dy: i32 = 0,
    mouseData: u32 = 0,
    dwFlags: u32 = 0,
    time: u32 = 0,
    dwExtraInfo: usize = 0,
};

// Only the mouse arm of the INPUT union is used; on x64 MOUSEINPUT is the
// largest member, so @sizeOf(INPUT) matches the Win32 definition (40 bytes).
pub const INPUT = extern struct {
    type: u32 = INPUT_MOUSE,
    mi: MOUSEINPUT,
};

pub const KEYBDINPUT = extern struct {
    wVk: u16 = 0,
    wScan: u16 = 0,
    dwFlags: u32 = 0,
    time: u32 = 0,
    dwExtraInfo: usize = 0,
};

/// Keyboard flavour of INPUT, padded to the same 40 bytes as INPUT so arrays
/// of it can be passed to SendInput with cbSize = @sizeOf(INPUT).
pub const KEYINPUT = extern struct {
    type: u32 = INPUT_KEYBOARD,
    ki: KEYBDINPUT,
    _pad: [8]u8 = [_]u8{0} ** 8,
};

comptime {
    if (@sizeOf(KEYINPUT) != @sizeOf(INPUT)) @compileError("KEYINPUT size mismatch");
}

pub const GUID = extern struct { a: u32 = 0, b: u16 = 0, c: u16 = 0, d: [8]u8 = [_]u8{0} ** 8 };

pub const NOTIFYICONDATAW = extern struct {
    cbSize: DWORD = @sizeOf(NOTIFYICONDATAW),
    hWnd: ?HWND = null,
    uID: UINT = 0,
    uFlags: UINT = 0,
    uCallbackMessage: UINT = 0,
    hIcon: ?HICON = null,
    szTip: [128]u16 = [_]u16{0} ** 128,
    dwState: DWORD = 0,
    dwStateMask: DWORD = 0,
    szInfo: [256]u16 = [_]u16{0} ** 256,
    uVersion: UINT = 0,
    szInfoTitle: [64]u16 = [_]u16{0} ** 64,
    dwInfoFlags: DWORD = 0,
    guidItem: GUID = .{},
    hBalloonIcon: ?HICON = null,
};

// Messages
pub const WM_DESTROY: UINT = 0x0002;
pub const WM_COMMAND: UINT = 0x0111;
pub const WM_HOTKEY: UINT = 0x0312;
pub const WM_QUIT: UINT = 0x0012;
pub const WM_APP: UINT = 0x8000;
pub const WM_RBUTTONUP: UINT = 0x0205;
pub const WM_LBUTTONUP: UINT = 0x0202;
pub const WM_NULL: UINT = 0x0000;

// Hotkeys
pub const MOD_SHIFT: UINT = 0x0004;
pub const MOD_NOREPEAT: UINT = 0x4000;

// Virtual keys
pub const VK_RETURN: i32 = 0x0D;
pub const VK_SHIFT: i32 = 0x10;
pub const VK_CAPITAL: i32 = 0x14;
pub const VK_SPACE: i32 = 0x20;

// SendInput
pub const INPUT_MOUSE: u32 = 0;
pub const INPUT_KEYBOARD: u32 = 1;
pub const KEYEVENTF_KEYUP: u32 = 0x0002;
pub const MOUSEEVENTF_LEFTDOWN: u32 = 0x0002;
pub const MOUSEEVENTF_LEFTUP: u32 = 0x0004;
pub const MOUSEEVENTF_RIGHTDOWN: u32 = 0x0008;
pub const MOUSEEVENTF_RIGHTUP: u32 = 0x0010;
pub const MOUSEEVENTF_MIDDLEDOWN: u32 = 0x0020;
pub const MOUSEEVENTF_MIDDLEUP: u32 = 0x0040;
pub const MOUSEEVENTF_WHEEL: u32 = 0x0800;

// Tray / menus
pub const NIM_ADD: DWORD = 0;
pub const NIM_MODIFY: DWORD = 1;
pub const NIM_DELETE: DWORD = 2;
pub const NIF_MESSAGE: UINT = 0x1;
pub const NIF_ICON: UINT = 0x2;
pub const NIF_TIP: UINT = 0x4;
pub const MF_STRING: UINT = 0x0;
pub const MF_GRAYED: UINT = 0x1;
pub const MF_CHECKED: UINT = 0x8;
pub const MF_SEPARATOR: UINT = 0x800;
pub const TPM_RIGHTBUTTON: UINT = 0x2;
pub const TPM_RETURNCMD: UINT = 0x100;
pub const TPM_NONOTIFY: UINT = 0x80;
pub const IDI_APPLICATION: usize = 32512;
pub const SW_SHOWNORMAL: i32 = 1;

// Wait / timers
pub const QS_ALLINPUT: DWORD = 0x04FF;
pub const WAIT_OBJECT_0: DWORD = 0;
pub const INFINITE: DWORD = 0xFFFFFFFF;
pub const PM_REMOVE: UINT = 0x1;
pub const CREATE_WAITABLE_TIMER_HIGH_RESOLUTION: DWORD = 0x2;
pub const TIMER_ALL_ACCESS: DWORD = 0x1F0003;
pub const ERROR_ALREADY_EXISTS: DWORD = 183;

// Files
pub const GENERIC_READ: DWORD = 0x80000000;
pub const GENERIC_WRITE: DWORD = 0x40000000;
pub const FILE_SHARE_READ: DWORD = 0x1;
pub const OPEN_EXISTING: DWORD = 3;
pub const CREATE_NEW: DWORD = 1;
pub const FILE_ATTRIBUTE_NORMAL: DWORD = 0x80;
pub const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(std.math.maxInt(usize));

// Registry
pub const HKEY_CURRENT_USER: HKEY = @ptrFromInt(0x80000001);
pub const KEY_QUERY_VALUE: DWORD = 0x0001;
pub const KEY_SET_VALUE: DWORD = 0x0002;
pub const REG_SZ: DWORD = 1;

pub const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: isize = -4;

// user32
pub extern "user32" fn RegisterHotKey(hWnd: ?HWND, id: i32, fsModifiers: UINT, vk: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn UnregisterHotKey(hWnd: ?HWND, id: i32) callconv(.winapi) BOOL;
pub extern "user32" fn GetKeyState(nVirtKey: i32) callconv(.winapi) i16;
pub extern "user32" fn GetAsyncKeyState(vKey: i32) callconv(.winapi) i16;
pub extern "user32" fn PeekMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) BOOL;
pub extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn MsgWaitForMultipleObjects(nCount: DWORD, pHandles: ?[*]const HANDLE, fWaitAll: BOOL, dwMilliseconds: DWORD, dwWakeMask: DWORD) callconv(.winapi) DWORD;
pub extern "user32" fn PostQuitMessage(nExitCode: i32) callconv(.winapi) void;
pub extern "user32" fn DefWindowProcW(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn RegisterClassExW(lpWndClass: *const WNDCLASSEXW) callconv(.winapi) ATOM;
pub extern "user32" fn CreateWindowExW(dwExStyle: DWORD, lpClassName: [*:0]const u16, lpWindowName: [*:0]const u16, dwStyle: DWORD, x: i32, y: i32, nWidth: i32, nHeight: i32, hWndParent: ?HWND, hMenu: ?HMENU, hInstance: ?HINSTANCE, lpParam: ?*anyopaque) callconv(.winapi) ?HWND;
pub extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn LoadIconW(hInstance: ?HINSTANCE, lpIconName: usize) callconv(.winapi) ?HICON;
pub extern "user32" fn GetCursorPos(lpPoint: *POINT) callconv(.winapi) BOOL;
pub extern "user32" fn SetCursorPos(x: i32, y: i32) callconv(.winapi) BOOL;
pub extern "user32" fn SendInput(cInputs: UINT, pInputs: [*]const INPUT, cbSize: i32) callconv(.winapi) UINT;
pub extern "user32" fn CreatePopupMenu() callconv(.winapi) ?HMENU;
pub extern "user32" fn AppendMenuW(hMenu: HMENU, uFlags: UINT, uIDNewItem: usize, lpNewItem: ?[*:0]const u16) callconv(.winapi) BOOL;
pub extern "user32" fn TrackPopupMenu(hMenu: HMENU, uFlags: UINT, x: i32, y: i32, nReserved: i32, hWnd: HWND, prcRect: ?*const anyopaque) callconv(.winapi) BOOL;
pub extern "user32" fn DestroyMenu(hMenu: HMENU) callconv(.winapi) BOOL;
pub extern "user32" fn SetForegroundWindow(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn PostMessageW(hWnd: ?HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) BOOL;
pub extern "user32" fn MessageBoxW(hWnd: ?HWND, lpText: [*:0]const u16, lpCaption: [*:0]const u16, uType: UINT) callconv(.winapi) i32;
pub extern "user32" fn SetProcessDpiAwarenessContext(value: isize) callconv(.winapi) BOOL;

// kernel32
pub extern "kernel32" fn GetModuleHandleW(lpModuleName: ?[*:0]const u16) callconv(.winapi) ?HINSTANCE;
pub extern "kernel32" fn GetModuleFileNameW(hModule: ?HINSTANCE, lpFilename: [*]u16, nSize: DWORD) callconv(.winapi) DWORD;
pub extern "kernel32" fn CreateMutexW(lpMutexAttributes: ?*anyopaque, bInitialOwner: BOOL, lpName: [*:0]const u16) callconv(.winapi) ?HANDLE;
pub extern "kernel32" fn GetLastError() callconv(.winapi) DWORD;
pub extern "kernel32" fn CreateWaitableTimerExW(lpTimerAttributes: ?*anyopaque, lpTimerName: ?[*:0]const u16, dwFlags: DWORD, dwDesiredAccess: DWORD) callconv(.winapi) ?HANDLE;
pub extern "kernel32" fn SetWaitableTimer(hTimer: HANDLE, lpDueTime: *const i64, lPeriod: i32, pfnCompletionRoutine: ?*anyopaque, lpArgToCompletionRoutine: ?*anyopaque, fResume: BOOL) callconv(.winapi) BOOL;
pub extern "kernel32" fn QueryPerformanceCounter(lpPerformanceCount: *i64) callconv(.winapi) BOOL;
pub extern "kernel32" fn QueryPerformanceFrequency(lpFrequency: *i64) callconv(.winapi) BOOL;
pub extern "kernel32" fn CreateFileW(lpFileName: [*:0]const u16, dwDesiredAccess: DWORD, dwShareMode: DWORD, lpSecurityAttributes: ?*anyopaque, dwCreationDisposition: DWORD, dwFlagsAndAttributes: DWORD, hTemplateFile: ?HANDLE) callconv(.winapi) HANDLE;
pub extern "kernel32" fn ReadFile(hFile: HANDLE, lpBuffer: [*]u8, nNumberOfBytesToRead: DWORD, lpNumberOfBytesRead: *DWORD, lpOverlapped: ?*anyopaque) callconv(.winapi) BOOL;
pub extern "kernel32" fn WriteFile(hFile: HANDLE, lpBuffer: [*]const u8, nNumberOfBytesToWrite: DWORD, lpNumberOfBytesWritten: *DWORD, lpOverlapped: ?*anyopaque) callconv(.winapi) BOOL;
pub extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) BOOL;

// shell32
pub extern "shell32" fn Shell_NotifyIconW(dwMessage: DWORD, lpData: *NOTIFYICONDATAW) callconv(.winapi) BOOL;
pub extern "shell32" fn ShellExecuteW(hwnd: ?HWND, lpOperation: ?[*:0]const u16, lpFile: [*:0]const u16, lpParameters: ?[*:0]const u16, lpDirectory: ?[*:0]const u16, nShowCmd: i32) callconv(.winapi) ?HINSTANCE;

// advapi32
pub extern "advapi32" fn RegOpenKeyExW(hKey: HKEY, lpSubKey: [*:0]const u16, ulOptions: DWORD, samDesired: DWORD, phkResult: *HKEY) callconv(.winapi) i32;
pub extern "advapi32" fn RegSetValueExW(hKey: HKEY, lpValueName: [*:0]const u16, Reserved: DWORD, dwType: DWORD, lpData: [*]const u8, cbData: DWORD) callconv(.winapi) i32;
pub extern "advapi32" fn RegQueryValueExW(hKey: HKEY, lpValueName: [*:0]const u16, lpReserved: ?*DWORD, lpType: ?*DWORD, lpData: ?[*]u8, lpcbData: ?*DWORD) callconv(.winapi) i32;
pub extern "advapi32" fn RegDeleteValueW(hKey: HKEY, lpValueName: [*:0]const u16) callconv(.winapi) i32;
pub extern "advapi32" fn RegCloseKey(hKey: HKEY) callconv(.winapi) i32;

/// Comptime ASCII -> null-terminated UTF-16.
pub fn L(comptime s: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(s);
}

// ---------------------------------------------------------------- overlay (hint mode)

pub const HDC = *opaque {};
pub const HFONT = *opaque {};
pub const HBITMAP = *opaque {};
pub const HMONITOR = *opaque {};
pub const COLORREF = DWORD;

pub const RECT = extern struct { left: i32 = 0, top: i32 = 0, right: i32 = 0, bottom: i32 = 0 };

pub const PAINTSTRUCT = extern struct {
    hdc: ?HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]u8,
};

pub const MONITORINFO = extern struct {
    cbSize: DWORD = @sizeOf(MONITORINFO),
    rcMonitor: RECT = .{},
    rcWork: RECT = .{},
    dwFlags: DWORD = 0,
};

pub const WM_ACTIVATE: UINT = 0x0006;
pub const WM_PAINT: UINT = 0x000F;
pub const WM_ERASEBKGND: UINT = 0x0014;
pub const WM_KEYDOWN: UINT = 0x0100;
pub const WM_SYSKEYDOWN: UINT = 0x0104;
pub const WS_POPUP: DWORD = 0x80000000;
pub const WS_EX_TOPMOST: DWORD = 0x00000008;
pub const WS_EX_TOOLWINDOW: DWORD = 0x00000080;
pub const WS_EX_LAYERED: DWORD = 0x00080000;
pub const SW_HIDE: i32 = 0;
pub const SW_SHOW: i32 = 5;
pub const LWA_COLORKEY: DWORD = 0x1;
pub const LWA_ALPHA: DWORD = 0x2;
pub const MONITOR_DEFAULTTONEAREST: DWORD = 2;
pub const TRANSPARENT: i32 = 1;
pub const FW_BOLD: i32 = 700;
pub const CLEARTYPE_QUALITY: DWORD = 5;
pub const SRCCOPY: DWORD = 0x00CC0020;
pub const DT_CENTER: UINT = 0x1;
pub const DT_VCENTER: UINT = 0x4;
pub const DT_SINGLELINE: UINT = 0x20;
pub const DT_NOPREFIX: UINT = 0x800;
pub const VK_BACK: usize = 0x08;
pub const VK_ESCAPE: usize = 0x1B;

pub extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(.winapi) BOOL;
pub extern "user32" fn SetWindowPos(hWnd: HWND, hWndInsertAfter: ?HWND, X: i32, Y: i32, cx: i32, cy: i32, uFlags: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn SetLayeredWindowAttributes(hWnd: HWND, crKey: COLORREF, bAlpha: u8, dwFlags: DWORD) callconv(.winapi) BOOL;
pub extern "user32" fn SetFocus(hWnd: ?HWND) callconv(.winapi) ?HWND;
pub extern "user32" fn InvalidateRect(hWnd: ?HWND, lpRect: ?*const RECT, bErase: BOOL) callconv(.winapi) BOOL;
pub extern "user32" fn BeginPaint(hWnd: HWND, lpPaint: *PAINTSTRUCT) callconv(.winapi) ?HDC;
pub extern "user32" fn EndPaint(hWnd: HWND, lpPaint: *const PAINTSTRUCT) callconv(.winapi) BOOL;
pub extern "user32" fn FillRect(hDC: HDC, lprc: *const RECT, hbr: HBRUSH) callconv(.winapi) i32;
pub extern "user32" fn DrawTextW(hdc: HDC, lpchText: [*]const u16, cchText: i32, lprc: *RECT, format: UINT) callconv(.winapi) i32;
pub extern "user32" fn MonitorFromPoint(pt: POINT, dwFlags: DWORD) callconv(.winapi) ?HMONITOR;
pub extern "user32" fn GetMonitorInfoW(hMonitor: HMONITOR, lpmi: *MONITORINFO) callconv(.winapi) BOOL;

pub extern "gdi32" fn CreateCompatibleDC(hdc: ?HDC) callconv(.winapi) ?HDC;
pub extern "gdi32" fn CreateCompatibleBitmap(hdc: HDC, cx: i32, cy: i32) callconv(.winapi) ?HBITMAP;
pub extern "gdi32" fn SelectObject(hdc: HDC, h: *anyopaque) callconv(.winapi) ?*anyopaque;
pub extern "gdi32" fn BitBlt(hdc: HDC, x: i32, y: i32, cx: i32, cy: i32, hdcSrc: HDC, x1: i32, y1: i32, rop: DWORD) callconv(.winapi) BOOL;
pub extern "gdi32" fn DeleteDC(hdc: HDC) callconv(.winapi) BOOL;
pub extern "gdi32" fn DeleteObject(ho: *anyopaque) callconv(.winapi) BOOL;
pub extern "gdi32" fn CreateSolidBrush(color: COLORREF) callconv(.winapi) ?HBRUSH;
pub extern "gdi32" fn CreateFontW(cHeight: i32, cWidth: i32, cEscapement: i32, cOrientation: i32, cWeight: i32, bItalic: DWORD, bUnderline: DWORD, bStrikeOut: DWORD, iCharSet: DWORD, iOutPrecision: DWORD, iClipPrecision: DWORD, iQuality: DWORD, iPitchAndFamily: DWORD, pszFaceName: [*:0]const u16) callconv(.winapi) ?HFONT;
pub extern "gdi32" fn SetTextColor(hdc: HDC, color: COLORREF) callconv(.winapi) COLORREF;
pub extern "gdi32" fn SetBkMode(hdc: HDC, mode: i32) callconv(.winapi) i32;

pub fn rgb(r: u8, g: u8, b: u8) COLORREF {
    return @as(COLORREF, r) | (@as(COLORREF, g) << 8) | (@as(COLORREF, b) << 16);
}
