import nme.display.Sprite;
import nme.Lib;
import nme.events.Event;
#if cpp 
import webview.WebView;
import webview.WebView.WebViewSizeHint;
import webview.WebView.WebViewNativeHandleKind;
import cpp.Pointer;
import cpp.Void as CVoid;
#end
import haxe.ui.containers.Box;
import haxe.ui.core.Component;
#if cpp 
@:cppInclude("windows.h")
#end

class HaxeWebview extends Box {
    private var webview:WebView;
    private var nmeHwnd:Int = 0;

    public function new() {
        super();
        #if cpp
        untyped __cpp__("CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);");
        #end
        addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
    }

    private inline function getAbsoluteXY():{x:Int, y:Int} {
        var ax:Int = 0;
        var ay:Int = 0;
        var c:Component = cast this;
        while (c != null) {
            ax += Math.floor(c.x);
            ay += Math.floor(c.y);
            c = c.parentComponent;
        }
        return { x: ax, y: ay };
    }

    private override function validateComponentLayout():Bool {
        var b = super.validateComponentLayout();
        trace("HaxeWebview validateComponentLayout: " + this.x + "," + this.y + " " + this.width + "x" + this.height);
        if (width > 0 && height > 0) {
            var abs = getAbsoluteXY();
            setWebViewRect(abs.x, abs.y, Math.floor(this.width), Math.floor(this.height));
        }
        return b;
    }

    private override function onAddedToStage(e:Event):Void {
        removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        nmeHwnd = getNMEWindowHandle();
        if (nmeHwnd == 0) return;
        createEmbeddedWebView(nmeHwnd);
        stage.addEventListener(Event.RESIZE, onResize);
        stage.addEventListener(Event.ENTER_FRAME, onFrame);
    }

    private function createEmbeddedWebView(nmeHwnd:Int):Void {
        #if cpp
        var winPtr = untyped __cpp__("(void*)(intptr_t){0}", nmeHwnd);
        webview = new WebView(true, winPtr);
        if (webview == null) return;
        try webview.navigate("https://haxeui.org") catch (e:Dynamic) {};
        // Initial position (absolute in window coords)
        var abs = getAbsoluteXY();
        setWebViewRect(abs.x, abs.y, Math.floor(this.width), Math.floor(this.height));
        #end
    }

    public function setWebViewRect(x:Int, y:Int, w:Int, h:Int):Void {
        #if cpp
        if (webview == null) return;
        // Cast via void* so C++ can convert to HWND
        untyped __cpp__(
            "HWND hwnd = (HWND)(void*){0}; if (hwnd) {::ShowWindow(hwnd, SW_SHOW); ::UpdateWindow(hwnd); ::SetWindowPos(hwnd, NULL, {1}, {2}, {3}, {4}, SWP_NOZORDER | SWP_SHOWWINDOW);}",
            webview.getNativeHandle(WebViewNativeHandleKind.WEBVIEW_NATIVE_HANDLE_KIND_UI_WIDGET),
            x, y, w, h
        );
        #end
    }

    private function onResize(_):Void {
        if (webview == null) return;
        var abs = getAbsoluteXY();
        setWebViewRect(abs.x, abs.y, Math.floor(this.width), Math.floor(this.height));
    }

    private function onFrame(_):Void {
        if (webview == null) return;
        webview.process(false);
    }

    private function getNMEWindowHandle():Int {
        #if cpp
        return untyped __cpp__(
            "([]()->int {\nDWORD pid = ::GetCurrentProcessId();\nHWND best = NULL;\nfor (HWND h = ::GetTopWindow(NULL); h != NULL; h = ::GetWindow(h, GW_HWNDNEXT)) {\n  if (::GetParent(h) != NULL) continue;\n  DWORD p = 0; ::GetWindowThreadProcessId(h, &p);\n  if (p != pid) continue;\n  best = h; break;\n}\nif (best == NULL) best = ::GetForegroundWindow();\nreturn (int)(intptr_t)best;\n})()"
        );
        #else
        return 0;
        #end
    }
}
