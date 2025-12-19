

import haxe.ui.containers.dialogs.Dialog.DialogEvent;
import haxe.ui.containers.dialogs.Dialog.DialogButton;
import haxe.ui.containers.dialogs.MessageBox;
#if (openfl || nme)     
    import openfl.display.Sprite;
    import openfl.Lib;
    import openfl.events.Event;

    import webview.WebView;
    import webview.WebView.WebViewSizeHint;
    import webview.WebView.WebViewNativeHandleKind;
    import cpp.Pointer;
    import cpp.Void as CVoid;
#end
#if (hl) 
    import hxd.Event;
    import webview.WebView_hashlink;
    import webview.WebView_hashlink.WebViewSizeHint;
    import webview.WebView_hashlink.WebViewNativeHandleKind;
#end
#if js
    import js.html.IFrameElement;
    import js.Browser;
    import haxe.ui.backend.html5.HtmlUtils;
#end
import haxe.ui.events.Events;
import haxe.ui.containers.Box;
import haxe.ui.core.Component;
#if (cpp || hl) 
@:cppInclude("windows.h")
#end

class HaxeWebview extends Box {
    #if (cpp || hl)
        private var webview:WebView;
        private var nmeHwnd:Int = 0;
    #end
    
    @:isVar public var url(get, set):String;

    #if js
        private var _iframe:IFrameElement = null;   
    #end
    public function new() {
        super();
        #if (cpp || hl)
            untyped __cpp__("CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);");
            addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        #else
            _iframe = Browser.document.createIFrameElement();
            _iframe.frameBorder = "none";
            this.element.append(_iframe);
        #end
        
    }
    #if js
        public function getPageObject(exp:String, callback:(value:String)->Void):Void{
            var msg = new MessageBox();
            msg.title = "Alert";
            msg.text = 'Not available in HaxeWebview.  Uncaught DOMException: Permission denied to access property "document"';
            msg.buttons = DialogButton.OK; // Single OK button
            msg.onDialogClosed = function(event:DialogEvent) {
                if (event.button == DialogButton.OK) {
                    trace("User pressed OK");
                }               
            };
            msg.showDialog();
        }
    #elseif cpp
        /**
        * Gets a JavaScript object/property from the page as a string.
        * 
        * Since eval() is asynchronous, this uses bind() to receive the value back.
        * The JS expression should return a JSON-serializable value (string, number, bool, etc.).
        * 
        * Example:
        * 
        * ```haxe
        * haxewebview.getPageObject("document.title", (value:String) -> {
        *     trace("Title: " + value);
        * });
        * 
        * haxewebview.getPageObject("document.body.innerHTML", (html:String) -> {
        *     trace("Body HTML: " + html);
        * });
        * 
        * haxewebview.getPageObject("document.documentElement.outerHTML", (html:String) -> {
        *     trace("Full DOM: " + html);
        * });
        * ```
        * 
        * @param jsExpression A JavaScript expression to evaluate (e.g., "document.title", "document.body.innerHTML")
        * @param callback Called with the stringified result from the JS expression
        */
        public function getPageObject(jsExpression:String, callback:(value:String)->Void):Void
        {
            if (webview.handle == null)
                return;

            var tempName = "__getPageObject_" + Std.random(999999);
            
            webview.bind(tempName, (seq, req, _) -> {
                // req is a JSON array with the value as first element
                var value = haxe.Json.parse(req)[0];
                callback(value);
                webview.resolve(seq, 0, '""');
                webview.unbind(tempName);
            }, null);

            // Call the temporary binding via bracket access to avoid any identifier edge cases
            webview.eval('window["' + tempName + '"](' + jsExpression + ');');
        }

        /**
        * Registers a JavaScript notification function that the page can call to send messages to the host.
        * 
        * Example:
        * 
        * ```haxe
        * haxewebview.registerJsNotification("notifyHost", (msg:String) -> {
        *     trace("Received message from JS: " + msg);
        * });
        * Send a message to Haxe; returns a Promise
        *  window.notifyHost("hello from JS").then(() => console.log("delivered"));
        * ```
        * 
        * @param name The name of the JavaScript function to register (default: "notifyHost")
        * @param handler Called when the JS function is invoked, with the message string
        */
        // Call this after webview is created
        public function registerJsNotification(name:String = "notifyHost", handler:(msg:String)->Void):Void {
            if (webview == null || webview.handle == null) return;
            webview.bind(name, (seq, req, _) -> {
                // req is JSON array of args; take first element as message
                var msg = haxe.Json.parse(req)[0];
                handler(Std.string(msg));
                webview.resolve(seq, 0, '""'); // resolve JS promise
            }, null);
        }
    #end
    private function get_url():String {
        #if js
        return _iframe.src;
        #else
        return url;
        #end
    }
    private function set_url(value:String):String {
        #if js
            _iframe.src = value;
        #else
            if (webview != null) {
                try webview.navigate(value) catch (e:Dynamic) {};
            }
        #end
        url=value;
        return url;
    }

    #if (cpp || hl)
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
            #if (cpp || hl)
            var winPtr = untyped __cpp__("(void*)(intptr_t){0}", nmeHwnd);
            webview = new WebView(true, winPtr);
            if (webview == null) return;
            trace(url);
            try webview.navigate(url) catch (e:Dynamic) {};
            // Initial position (absolute in window coords)

            // Register JS notification handler after webview is created
            registerJsNotification("notifyHost", (msg:String) -> {
                trace("Message from JS: " + msg);
                // Handle the notification here or dispatch a HaxeUI event
                // e.g., dispatch(new haxe.ui.events.UIEvent("webviewMessage", msg));
            });

            setWebViewRect(Math.floor(screenLeft), Math.floor(screenTop), Math.floor(this.width), Math.floor(this.height));
            #end
        }

        public function setWebViewRect(x:Int, y:Int, w:Int, h:Int):Void {
            #if (cpp || hl)
            if (webview == null) return;
            // Cast via void* so C++ can convert to HWND
            untyped __cpp__(
                "HWND hwnd = (HWND)(void*){0}; if (hwnd) {::ShowWindow(hwnd, SW_SHOW); ::UpdateWindow(hwnd); ::SetWindowPos(hwnd, NULL, {1}, {2}, {3}, {4}, SWP_NOZORDER | SWP_SHOWWINDOW);}",
                webview.getNativeHandle(WebViewNativeHandleKind.WEBVIEW_NATIVE_HANDLE_KIND_UI_WIDGET),
                x, y, w, h
            );
            #end
        }

        /**
         * Hide the embedded WebView HWND so HaxeUI dialogs render on top.
         */
        public function hideWebView():Void {
            #if (cpp || hl)
            if (webview == null) return;
            untyped __cpp__(
                "HWND hwnd = (HWND)(void*){0}; if (hwnd) {::ShowWindow(hwnd, SW_HIDE);}",
                webview.getNativeHandle(WebViewNativeHandleKind.WEBVIEW_NATIVE_HANDLE_KIND_UI_WIDGET)
            );
            #end
        }

        /**
         * Show the embedded WebView HWND again after dialogs close.
         */
        public function showWebView():Void {
            #if (cpp || hl)
            if (webview == null) return;
            untyped __cpp__(
                "HWND hwnd = (HWND)(void*){0}; if (hwnd) {::ShowWindow(hwnd, SW_SHOW); ::UpdateWindow(hwnd);}",
                webview.getNativeHandle(WebViewNativeHandleKind.WEBVIEW_NATIVE_HANDLE_KIND_UI_WIDGET)
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
            #if (cpp || hl)
            return untyped __cpp__(
                "([]()->int {\nDWORD pid = ::GetCurrentProcessId();\nHWND best = NULL;\nfor (HWND h = ::GetTopWindow(NULL); h != NULL; h = ::GetWindow(h, GW_HWNDNEXT)) {\n  if (::GetParent(h) != NULL) continue;\n  DWORD p = 0; ::GetWindowThreadProcessId(h, &p);\n  if (p != pid) continue;\n  best = h; break;\n}\nif (best == NULL) best = ::GetForegroundWindow();\nreturn (int)(intptr_t)best;\n})()"
            );
            #else
            return 0;
            #end
        }
    #elseif js    
    
        private override function validateComponentLayout():Bool {
            var b = super.validateComponentLayout();
            
            if (width > 0 && height > 0) {
                _iframe.width = HtmlUtils.px(width);
                _iframe.height = HtmlUtils.px(height);
            }
            
            return b;
        }
    #end
}
