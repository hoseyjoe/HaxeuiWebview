package webview.host;

#if (cpp && windows)
import webview.WebView;
import webview.WebView.WindowPtr;
import webview.WebView.WebViewNativeHandleKind;

// Win32 / WebView2: the webview widget is a child HWND of the NME window,
// so positioning is a plain SetWindowPos in client coordinates.
@:cppInclude("windows.h")
class NativeHostWindows implements INativeHost
{
    private var widget:WindowPtr = null;

    public function new()
    {
        // WebView2 needs an STA thread before embedding into an existing window
        untyped __cpp__("CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);");
    }

    public function findParentWindow():WindowPtr
    {
        // NME doesn't expose its HWND, so take the first top-level window owned by this process
        return untyped __cpp__(
            "::cpp::Pointer<void>((void*)([]()->HWND {\nDWORD pid = ::GetCurrentProcessId();\nHWND best = NULL;\nfor (HWND h = ::GetTopWindow(NULL); h != NULL; h = ::GetWindow(h, GW_HWNDNEXT)) {\n  if (::GetParent(h) != NULL) continue;\n  DWORD p = 0; ::GetWindowThreadProcessId(h, &p);\n  if (p != pid) continue;\n  best = h; break;\n}\nif (best == NULL) best = ::GetForegroundWindow();\nreturn best;\n})())"
        );
    }

    public function attach(webview:WebView):Bool
    {
        widget = webview.getNativeHandle(WebViewNativeHandleKind.WEBVIEW_NATIVE_HANDLE_KIND_UI_WIDGET);
        return widget != null;
    }

    public function setRect(x:Int, y:Int, w:Int, h:Int):Void
    {
        if (widget == null) return;
        // Cast via void* so C++ can convert to HWND
        untyped __cpp__(
            "HWND hwnd = (HWND)(void*){0}; if (hwnd) {::ShowWindow(hwnd, SW_SHOW); ::UpdateWindow(hwnd); ::SetWindowPos(hwnd, NULL, {1}, {2}, {3}, {4}, SWP_NOZORDER | SWP_SHOWWINDOW);}",
            widget, x, y, w, h
        );
    }

    public function setVisible(visible:Bool):Void
    {
        if (widget == null) return;
        untyped __cpp__(
            "HWND hwnd = (HWND)(void*){0}; if (hwnd) {::ShowWindow(hwnd, {1} ? SW_SHOW : SW_HIDE); if ({1}) ::UpdateWindow(hwnd);}",
            widget, visible
        );
    }
}
#end
