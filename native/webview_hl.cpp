// webview_hl.cpp - HashLink native extension (webview.hdll) for the Heaps target.
//
// Wraps the same webview/webview header HxWebView uses on hxcpp, plus the Win32
// host glue that NativeHostWindows does with __cpp__ on hxcpp.
//
// @:hlNative("webview") maps a Haxe extern `foo` to the export `hlp_foo`, which
// DEFINE_PRIM generates and points at HL_NAME(foo) = webview_foo.
//
// Strings cross the boundary as NUL-terminated UTF-8 hl.Bytes; the Haxe side
// converts with String.toUtf8() / String.fromUTF8().

#define HL_NAME(n) webview_##n

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <objbase.h>
#include <string>
#include <map>

#include <hl.h>
#include <webview.h>

#pragma comment(lib, "gdi32.lib")

#define _WEBVIEW _ABSTRACT(webview)

static bool g_is_destroyed = false;

// Copies a std::string into GC memory as NUL-terminated UTF-8
static vbyte* to_hl_bytes(const std::string& s)
{
    return hl_copy_bytes((const vbyte*)s.c_str(), (int)s.size() + 1);
}

// Closures handed to bind/dispatch must stay alive while native code holds them
struct Callback
{
    vclosure* fn;
    vdynamic* arg;
};

static Callback* callback_create(vclosure* fn, vdynamic* arg)
{
    Callback* cb = (Callback*)malloc(sizeof(Callback));
    cb->fn = fn;
    cb->arg = arg;
    hl_add_root(&cb->fn);
    hl_add_root(&cb->arg);
    return cb;
}

static void callback_free(Callback* cb)
{
    if (!cb) return;
    hl_remove_root(&cb->fn);
    hl_remove_root(&cb->arg);
    free(cb);
}

// Keyed by webview + binding name so several webviews can bind the same JS name
static std::map<std::pair<void*, std::string>, Callback*> g_binds;

// -----------------------------------------------------------------------
// webview.h
// -----------------------------------------------------------------------

HL_PRIM void* HL_NAME(webview_create)(int debug, void* window)
{
    // WebView2 needs an STA thread before embedding into an existing window
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    g_is_destroyed = false;
    return webview_create(debug, window);
}
DEFINE_PRIM(_WEBVIEW, webview_create, _I32 _WEBVIEW);

HL_PRIM void HL_NAME(webview_destroy)(void* w)
{
    if (!w) return;
    for (auto it = g_binds.begin(); it != g_binds.end();)
    {
        if (it->first.first == w) { callback_free(it->second); it = g_binds.erase(it); }
        else ++it;
    }
    webview_destroy((webview_t)w);
}
DEFINE_PRIM(_VOID, webview_destroy, _WEBVIEW);

HL_PRIM void HL_NAME(webview_run)(void* w)
{
    if (w) webview_run((webview_t)w);
}
DEFINE_PRIM(_VOID, webview_run, _WEBVIEW);

HL_PRIM void HL_NAME(webview_terminate)(void* w)
{
    if (w) webview_terminate((webview_t)w);
}
DEFINE_PRIM(_VOID, webview_terminate, _WEBVIEW);

static void dispatch_trampoline(webview_t w, void* arg)
{
    Callback* cb = (Callback*)arg;
    hl_call2(void, cb->fn, void*, w, vdynamic*, cb->arg);
    callback_free(cb);
}

HL_PRIM void HL_NAME(hx_webview_dispatch)(void* w, vclosure* fn, vdynamic* arg)
{
    if (!w || !fn) return;
    webview_dispatch((webview_t)w, dispatch_trampoline, callback_create(fn, arg));
}
DEFINE_PRIM(_VOID, hx_webview_dispatch, _WEBVIEW _FUN(_VOID, _WEBVIEW _DYN) _DYN);

HL_PRIM void* HL_NAME(webview_get_window)(void* w)
{
    return w ? webview_get_window((webview_t)w) : NULL;
}
DEFINE_PRIM(_WEBVIEW, webview_get_window, _WEBVIEW);

HL_PRIM void* HL_NAME(hx_get_native_handle)(void* w, int kind)
{
    if (!w || kind < 0 || kind > 2) return NULL;
    return webview_get_native_handle((webview_t)w, (webview_native_handle_kind_t)kind);
}
DEFINE_PRIM(_WEBVIEW, hx_get_native_handle, _WEBVIEW _I32);

HL_PRIM void HL_NAME(webview_set_title)(void* w, vbyte* title)
{
    if (w && title) webview_set_title((webview_t)w, (const char*)title);
}
DEFINE_PRIM(_VOID, webview_set_title, _WEBVIEW _BYTES);

HL_PRIM void HL_NAME(hx_set_size)(void* w, int width, int height, int hints)
{
    if (w) webview_set_size((webview_t)w, width, height, (webview_hint_t)hints);
}
DEFINE_PRIM(_VOID, hx_set_size, _WEBVIEW _I32 _I32 _I32);

HL_PRIM void HL_NAME(webview_navigate)(void* w, vbyte* url)
{
    if (w && url) webview_navigate((webview_t)w, (const char*)url);
}
DEFINE_PRIM(_VOID, webview_navigate, _WEBVIEW _BYTES);

HL_PRIM void HL_NAME(webview_set_html)(void* w, vbyte* html)
{
    if (w && html) webview_set_html((webview_t)w, (const char*)html);
}
DEFINE_PRIM(_VOID, webview_set_html, _WEBVIEW _BYTES);

HL_PRIM void HL_NAME(webview_init)(void* w, vbyte* js)
{
    if (w && js) webview_init((webview_t)w, (const char*)js);
}
DEFINE_PRIM(_VOID, webview_init, _WEBVIEW _BYTES);

HL_PRIM void HL_NAME(webview_eval)(void* w, vbyte* js)
{
    if (w && js) webview_eval((webview_t)w, (const char*)js);
}
DEFINE_PRIM(_VOID, webview_eval, _WEBVIEW _BYTES);

// BindFunc on the Haxe side is (seq:hl.Bytes, req:hl.Bytes, arg:Dynamic)->Void.
// The closure is type checked by DEFINE_PRIM, so hl_call3 can call it directly.
HL_PRIM void HL_NAME(hx_webview_bind)(void* w, vbyte* name, vclosure* fn, vdynamic* arg)
{
    if (!w || !name || !fn) return;
    auto key = std::make_pair(w, std::string((const char*)name));
    auto it = g_binds.find(key);
    if (it != g_binds.end()) callback_free(it->second);
    Callback* cb = callback_create(fn, arg);
    g_binds[key] = cb;

    static_cast<webview::webview*>(w)->bind(key.second,
        [cb](const std::string& seq, const std::string& req, void*) {
            hl_call3(void, cb->fn, vbyte*, to_hl_bytes(seq), vbyte*, to_hl_bytes(req), vdynamic*, cb->arg);
        },
        nullptr);
}
DEFINE_PRIM(_VOID, hx_webview_bind, _WEBVIEW _BYTES _FUN(_VOID, _BYTES _BYTES _DYN) _DYN);

HL_PRIM void HL_NAME(webview_unbind)(void* w, vbyte* name)
{
    if (!w || !name) return;
    auto key = std::make_pair(w, std::string((const char*)name));
    webview_unbind((webview_t)w, key.second.c_str());
    auto it = g_binds.find(key);
    if (it != g_binds.end())
    {
        callback_free(it->second);
        g_binds.erase(it);
    }
}
DEFINE_PRIM(_VOID, webview_unbind, _WEBVIEW _BYTES);

HL_PRIM void HL_NAME(webview_return)(void* w, vbyte* seq, int status, vbyte* result)
{
    if (!w || !seq) return;
    webview_return((webview_t)w, (const char*)seq, status, result ? (const char*)result : "");
}
DEFINE_PRIM(_VOID, webview_return, _WEBVIEW _BYTES _I32 _BYTES);

// 0 = version_number, 1 = pre_release, 2 = build_metadata
HL_PRIM vbyte* HL_NAME(hx_webview_version_string)(int which)
{
    const webview_version_info_t* info = webview_version();
    const char* s = which == 1 ? info->pre_release : which == 2 ? info->build_metadata : info->version_number;
    return to_hl_bytes(s);
}
DEFINE_PRIM(_BYTES, hx_webview_version_string, _I32);

// -----------------------------------------------------------------------
// WindowUtils (Win32 versions of HxWebView's WindowUtils.cpp)
// -----------------------------------------------------------------------

HL_PRIM void HL_NAME(get_window_position)(void* w, int* x, int* y)
{
    RECT r{};
    if (w) GetWindowRect((HWND)webview_get_window((webview_t)w), &r);
    *x = r.left;
    *y = r.top;
}
DEFINE_PRIM(_VOID, get_window_position, _WEBVIEW _REF(_I32) _REF(_I32));

HL_PRIM void HL_NAME(set_window_position)(void* w, int x, int y)
{
    if (!w) return;
    SetWindowPos((HWND)webview_get_window((webview_t)w), NULL, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}
DEFINE_PRIM(_VOID, set_window_position, _WEBVIEW _I32 _I32);

HL_PRIM void HL_NAME(set_window_decoration)(void* w, bool state)
{
    if (!w) return;
    HWND hwnd = (HWND)webview_get_window((webview_t)w);
    LONG style = GetWindowLong(hwnd, GWL_STYLE);
    const LONG frame = WS_CAPTION | WS_THICKFRAME | WS_SYSMENU;
    SetWindowLong(hwnd, GWL_STYLE, state ? (style | frame) : (style & ~frame));
    SetWindowPos(hwnd, NULL, 0, 0, 0, 0, SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}
DEFINE_PRIM(_VOID, set_window_decoration, _WEBVIEW _BOOL);

HL_PRIM void HL_NAME(set_window_topmost)(void* w, bool state)
{
    if (!w) return;
    SetWindowPos((HWND)webview_get_window((webview_t)w), state ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
}
DEFINE_PRIM(_VOID, set_window_topmost, _WEBVIEW _BOOL);

// Win32 doesn't need a destroy signal; webview posts WM_QUIT when its own window closes
HL_PRIM void HL_NAME(add_destroy_signal)(void*) {}
DEFINE_PRIM(_VOID, add_destroy_signal, _WEBVIEW);

HL_PRIM bool HL_NAME(events_pending)(void*)
{
    MSG msg;
    return PeekMessageW(&msg, NULL, 0, 0, PM_NOREMOVE) != 0;
}
DEFINE_PRIM(_BOOL, events_pending, _WEBVIEW);

// Non-blocking, unlike HxWebView's GetMessage loop. Only needed for a standalone
// webview window; when embedded, Heaps' own message pump already drives WebView2.
HL_PRIM void HL_NAME(run_main_iteration)(bool)
{
    MSG msg;
    while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE))
    {
        if (msg.message == WM_QUIT)
        {
            g_is_destroyed = true;
            return;
        }
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
}
DEFINE_PRIM(_VOID, run_main_iteration, _BOOL);

HL_PRIM bool HL_NAME(is_open)()
{
    return !g_is_destroyed;
}
DEFINE_PRIM(_BOOL, is_open, _NO_ARG);

// -----------------------------------------------------------------------
// NativeHostWindows (HL side of webview/host/NativeHostWindows.hx)
// -----------------------------------------------------------------------

// Heaps doesn't hand out its HWND, so take this process's visible, unowned
// top-level window (skips the hidden IME / message windows every GUI thread has)
HL_PRIM void* HL_NAME(host_find_parent_window)()
{
    DWORD pid = GetCurrentProcessId();
    for (HWND h = GetTopWindow(NULL); h != NULL; h = GetWindow(h, GW_HWNDNEXT))
    {
        if (GetParent(h) != NULL || GetWindow(h, GW_OWNER) != NULL || !IsWindowVisible(h)) continue;
        DWORD p = 0;
        GetWindowThreadProcessId(h, &p);
        if (p == pid) return h;
    }
    return GetForegroundWindow();
}
DEFINE_PRIM(_WEBVIEW, host_find_parent_window, _NO_ARG);

HL_PRIM void HL_NAME(host_set_rect)(void* widget, int x, int y, int w, int h)
{
    HWND hwnd = (HWND)widget;
    if (!hwnd) return;
    SetWindowPos(hwnd, NULL, x, y, w, h, SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
}
DEFINE_PRIM(_VOID, host_set_rect, _WEBVIEW _I32 _I32 _I32 _I32);

HL_PRIM void HL_NAME(host_set_visible)(void* widget, bool visible)
{
    HWND hwnd = (HWND)widget;
    if (!hwnd) return;
    ShowWindow(hwnd, visible ? SW_SHOW : SW_HIDE);
    if (visible) UpdateWindow(hwnd);
}
DEFINE_PRIM(_VOID, host_set_visible, _WEBVIEW _BOOL);

// rects holds `count` x,y,w,h int32 quads in widget-local pixels
HL_PRIM void HL_NAME(host_set_clip_holes)(void* widget, int width, int height, vbyte* rects, int count)
{
    HWND hwnd = (HWND)widget;
    if (!hwnd) return;
    if (count == 0)
    {
        SetWindowRgn(hwnd, NULL, TRUE);
        return;
    }
    // Window regions also clip the WebView2 child HWNDs and hit-testing
    HRGN rgn = CreateRectRgn(0, 0, width, height);
    const int* r = (const int*)rects;
    for (int i = 0; i < count; i++, r += 4)
    {
        HRGN hole = CreateRectRgn(r[0], r[1], r[0] + r[2], r[1] + r[3]);
        CombineRgn(rgn, rgn, hole, RGN_DIFF);
        DeleteObject(hole);
    }
    // The system owns the region after SetWindowRgn
    SetWindowRgn(hwnd, rgn, TRUE);
}
DEFINE_PRIM(_VOID, host_set_clip_holes, _WEBVIEW _I32 _I32 _BYTES _I32);
