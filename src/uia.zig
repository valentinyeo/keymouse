//! Minimal UI Automation client: find the on-screen clickable elements of a
//! window and return their bounding rectangles. Raw COM vtable calls; indices
//! are from uiautomationclient.h (mingw, shipped with Zig).

const std = @import("std");
const win32 = @import("win32.zig");

const HRESULT = i32;

const Obj = extern struct { vtbl: [*]const *const anyopaque };

fn call(comptime T: type, obj: *Obj, idx: usize) T {
    return @ptrCast(obj.vtbl[idx]);
}

fn release(obj: *Obj) void {
    _ = call(*const fn (*Obj) callconv(.winapi) u32, obj, 2)(obj);
}

const VARIANT = extern struct {
    vt: u16,
    r1: u16 = 0,
    r2: u16 = 0,
    r3: u16 = 0,
    val: extern union { lVal: i32, boolVal: i16, pad: [2]u64 },
};

fn vBool(b: bool) VARIANT {
    return .{ .vt = 11, .val = .{ .boolVal = if (b) -1 else 0 } }; // VT_BOOL
}

fn vInt(i: i32) VARIANT {
    return .{ .vt = 3, .val = .{ .lVal = i } }; // VT_I4
}

// IUIAutomation
const UA_ElementFromHandle = 6;
const UA_CreateCacheRequest = 20;
const UA_CreatePropertyCondition = 23;
const UA_CreateAndCondition = 25;
const UA_CreateOrConditionFromNativeArray = 30;
// IUIAutomationElement
const EL_FindAllBuildCache = 8;
const EL_get_CachedBoundingRectangle = 75;
// IUIAutomationElementArray
const ARR_get_Length = 3;
const ARR_GetElement = 4;
// IUIAutomationCacheRequest
const CR_AddProperty = 3;
const CR_put_AutomationElementMode = 11;

const PROP_BoundingRectangle = 30001;
const PROP_ControlType = 30003;
const PROP_IsOffscreen = 30022;
const PROP_IsExpandCollapsePatternAvailable = 30028;
const PROP_IsInvokePatternAvailable = 30031;
const PROP_IsSelectionItemPatternAvailable = 30036;
const PROP_IsTogglePatternAvailable = 30041;
const CT_Button = 50000;
const CT_ComboBox = 50003;
const CT_Edit = 50004;
const CT_Hyperlink = 50005;
const CT_MenuItem = 50011;
const CT_TabItem = 50019;

const TreeScope_Descendants = 4;

const CLSID_CUIAutomation = win32.GUID{ .a = 0xff48dba4, .b = 0x60ef, .c = 0x4201, .d = .{ 0xaa, 0x87, 0x54, 0x10, 0x3e, 0xef, 0x59, 0x4e } };
const IID_IUIAutomation = win32.GUID{ .a = 0x30cbe57d, .b = 0xd9d0, .c = 0x452a, .d = .{ 0xab, 0x13, 0x7a, 0xc5, 0xac, 0x48, 0x25, 0xee } };

extern "ole32" fn CoInitializeEx(pvReserved: ?*anyopaque, dwCoInit: u32) callconv(.winapi) HRESULT;
extern "ole32" fn CoCreateInstance(rclsid: *const win32.GUID, pUnkOuter: ?*anyopaque, dwClsContext: u32, riid: *const win32.GUID, ppv: *?*Obj) callconv(.winapi) HRESULT;

var automation: ?*Obj = null;
var condition: ?*Obj = null;
var cache: ?*Obj = null;

pub fn init() void {
    _ = CoInitializeEx(null, 0); // COINIT_MULTITHREADED, as UIA recommends for clients
    var ua: ?*Obj = null;
    if (CoCreateInstance(&CLSID_CUIAutomation, null, 1, &IID_IUIAutomation, &ua) < 0) return; // CLSCTX_INPROC_SERVER
    const a = ua orelse return;

    const createProp = call(*const fn (*Obj, i32, VARIANT, *?*Obj) callconv(.winapi) HRESULT, a, UA_CreatePropertyCondition);
    // Clickable = supports a click-like pattern, or is a control type people click.
    var any: [10]?*Obj = [_]?*Obj{null} ** 10;
    _ = createProp(a, PROP_IsInvokePatternAvailable, vBool(true), &any[0]);
    _ = createProp(a, PROP_IsTogglePatternAvailable, vBool(true), &any[1]);
    _ = createProp(a, PROP_IsSelectionItemPatternAvailable, vBool(true), &any[2]);
    _ = createProp(a, PROP_IsExpandCollapsePatternAvailable, vBool(true), &any[3]);
    _ = createProp(a, PROP_ControlType, vInt(CT_Button), &any[4]);
    _ = createProp(a, PROP_ControlType, vInt(CT_Hyperlink), &any[5]);
    _ = createProp(a, PROP_ControlType, vInt(CT_Edit), &any[6]);
    _ = createProp(a, PROP_ControlType, vInt(CT_ComboBox), &any[7]);
    _ = createProp(a, PROP_ControlType, vInt(CT_MenuItem), &any[8]);
    _ = createProp(a, PROP_ControlType, vInt(CT_TabItem), &any[9]);
    for (any) |c| if (c == null) return;

    var clickable: ?*Obj = null;
    _ = call(*const fn (*Obj, [*]const ?*Obj, i32, *?*Obj) callconv(.winapi) HRESULT, a, UA_CreateOrConditionFromNativeArray)(a, &any, any.len, &clickable);
    for (any) |c| release(c.?);
    var onscreen: ?*Obj = null;
    _ = createProp(a, PROP_IsOffscreen, vBool(false), &onscreen);
    if (clickable == null or onscreen == null) return;
    var both: ?*Obj = null;
    _ = call(*const fn (*Obj, *Obj, *Obj, *?*Obj) callconv(.winapi) HRESULT, a, UA_CreateAndCondition)(a, onscreen.?, clickable.?, &both);
    release(onscreen.?);
    release(clickable.?);

    var cr: ?*Obj = null;
    _ = call(*const fn (*Obj, *?*Obj) callconv(.winapi) HRESULT, a, UA_CreateCacheRequest)(a, &cr);
    if (cr) |c| {
        _ = call(*const fn (*Obj, i32) callconv(.winapi) HRESULT, c, CR_AddProperty)(c, PROP_BoundingRectangle);
        // Only cached properties, no live element references: much cheaper cross-process.
        _ = call(*const fn (*Obj, i32) callconv(.winapi) HRESULT, c, CR_put_AutomationElementMode)(c, 0);
    }
    automation = a;
    condition = both;
    cache = cr;
}

/// Appends the bounding rects of clickable elements under `hwnd` to `out`
/// starting at `n.*`. Returns silently on any failure.
pub fn collect(hwnd: win32.HWND, out: []win32.RECT, n: *usize) void {
    const a = automation orelse return;
    const cond = condition orelse return;
    const cr = cache orelse return;

    var el: ?*Obj = null;
    if (call(*const fn (*Obj, win32.HWND, *?*Obj) callconv(.winapi) HRESULT, a, UA_ElementFromHandle)(a, hwnd, &el) < 0) return;
    const root = el orelse return;
    defer release(root);

    var arr_opt: ?*Obj = null;
    if (call(*const fn (*Obj, i32, *Obj, *Obj, *?*Obj) callconv(.winapi) HRESULT, root, EL_FindAllBuildCache)(root, TreeScope_Descendants, cond, cr, &arr_opt) < 0) return;
    const arr = arr_opt orelse return;
    defer release(arr);

    var len: i32 = 0;
    _ = call(*const fn (*Obj, *i32) callconv(.winapi) HRESULT, arr, ARR_get_Length)(arr, &len);
    var i: i32 = 0;
    while (i < len and n.* < out.len) : (i += 1) {
        var e: ?*Obj = null;
        if (call(*const fn (*Obj, i32, *?*Obj) callconv(.winapi) HRESULT, arr, ARR_GetElement)(arr, i, &e) < 0) continue;
        const elem = e orelse continue;
        var r: win32.RECT = .{};
        const hr = call(*const fn (*Obj, *win32.RECT) callconv(.winapi) HRESULT, elem, EL_get_CachedBoundingRectangle)(elem, &r);
        release(elem);
        if (hr < 0 or r.right <= r.left or r.bottom <= r.top) continue;
        out[n.*] = r;
        n.* += 1;
    }
}
