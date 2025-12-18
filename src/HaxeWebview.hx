import openfl.display.Sprite;
import openfl.Lib;
import openfl.events.Event;
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
    public var url:String;
    public function new() {
        super();
        #if cpp
        untyped __cpp__("CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);");
        #end
        addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
    }

    private override function validateComponentLayout():Bool {
        var b = super.validateComponentLayout();
        if (width > 0 && height > 0) {    
            setWebViewRect(Math.floor(screenLeft), Math.floor(screenTop), Math.floor(this.width), Math.floor(this.height));
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

        setWebViewRect(Math.floor(screenLeft), Math.floor(screenTop), Math.floor(this.width), Math.floor(this.height));
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

        setWebViewRect(Math.floor(screenLeft), Math.floor(screenTop), Math.floor(this.width), Math.floor(this.height));
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
