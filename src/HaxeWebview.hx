

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
    import webview.host.INativeHost;
    import webview.host.INativeHost.ClipRect;
    import webview.host.NativeHost;
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
import haxe.ui.core.Screen;

class HaxeWebview extends Box {
    #if (cpp || hl)
        /**
         * Components inside the normal view tree that should also draw over webviews
         * (e.g. a floating panel). Popups (menus, dropdowns, dialogs, tooltips) are
         * picked up automatically since HaxeUI puts them on their own Screen root.
         */
        public static var overlays:Array<Component> = [];

        private var webview:WebView;
        // Per-OS glue (Win32 / Cocoa / GTK) for parenting and positioning the native view
        private var host:INativeHost;
        private var lastClipKey:String = "";
    #end
    
    @:isVar public var url(get, set):String;

    #if js
        private var _iframe:IFrameElement = null;   
    #end
    public function new() {
        super();
        #if (cpp || hl)
            host = NativeHost.create();
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
            if (host == null) return;
            createEmbeddedWebView();
            stage.addEventListener(Event.RESIZE, onResize);
            stage.addEventListener(Event.ENTER_FRAME, onFrame);
        }

        private function createEmbeddedWebView():Void {
            #if (cpp || hl)
            webview = new WebView(true, host.findParentWindow());
            if (webview.handle == null) {
                webview = null;
                return;
            }
            if (!host.attach(webview)) trace("HaxeWebview: failed to embed webview into the host window");
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
            host.setRect(x, y, w, h);
            #end
        }

        /**
         * Hide the embedded native webview so HaxeUI dialogs render on top.
         */
        public function hideWebView():Void {
            #if (cpp || hl)
            if (webview == null) return;
            host.setVisible(false);
            #end
        }

        /**
         * Show the embedded native webview again after dialogs close.
         */
        public function showWebView():Void {
            #if (cpp || hl)
            if (webview == null) return;
            host.setVisible(true);
            #end
        }

        private function onResize(_):Void {
            if (webview == null) return;

            setWebViewRect(Math.floor(screenLeft), Math.floor(screenTop), Math.floor(this.width), Math.floor(this.height));
        }

        private function onFrame(_):Void {
            if (webview == null) return;
            // Win32: SDL's message pump already dispatches WebView2's messages, and HxWebView's
            // process() uses a blocking GetMessage that would stall NME's frame loop until input.
            #if !windows
            webview.process(false);
            #end
            updateClipHoles();
        }

        /**
         * Native webviews always draw above NME's GL surface, so rather than z-ordering we
         * cut holes in the webview wherever a HaxeUI popup/overlay covers it.
         */
        private function updateClipHoles():Void {
            var left = Math.floor(screenLeft);
            var top = Math.floor(screenTop);
            var w = Math.floor(this.width);
            var h = Math.floor(this.height);
            var holes:Array<ClipRect> = [];

            var ownRoot = rootComponent;
            for (c in Screen.instance.rootComponents) {
                if (c == ownRoot) continue;
                // Keep the webview visible (undimmed) behind modal overlays
                if (c.id == "modal-background" || c.id == "sidebar-modal-background") continue;
                addClipHole(holes, c, left, top, w, h);
            }
            for (c in overlays) {
                if (Screen.instance.rootComponents.indexOf(c.rootComponent) == -1) continue;
                addClipHole(holes, c, left, top, w, h);
            }

            // Only touch the native region when something actually changed
            var key = '$w,$h';
            for (r in holes) key += '|${r.x},${r.y},${r.w},${r.h}';
            if (key == lastClipKey) return;
            lastClipKey = key;
            host.setClipHoles(holes);
        }

        private function addClipHole(holes:Array<ClipRect>, c:Component, left:Int, top:Int, w:Int, h:Int):Void {
            var p = c;
            while (p != null) {
                if (p.hidden) return;
                p = p.parentComponent;
            }
            if (c.width <= 0 || c.height <= 0) return;

            // Intersect with this webview, in webview-local coordinates
            var x1 = Std.int(Math.max(Math.floor(c.screenLeft) - left, 0));
            var y1 = Std.int(Math.max(Math.floor(c.screenTop) - top, 0));
            var x2 = Std.int(Math.min(Math.ceil(c.screenLeft + c.width) - left, w));
            var y2 = Std.int(Math.min(Math.ceil(c.screenTop + c.height) - top, h));
            if (x2 <= x1 || y2 <= y1) return;
            holes.push({x: x1, y: y1, w: x2 - x1, h: y2 - y1});
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
