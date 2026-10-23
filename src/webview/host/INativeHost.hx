package webview.host;

#if cpp
import webview.WebView;
import webview.WebView.WindowPtr;

// A rectangle in stage pixels, relative to the webview's top-left corner
typedef ClipRect = {x:Int, y:Int, w:Int, h:Int}

// The per-OS glue that puts a webview/webview instance *inside* the NME window.
// webview/webview already picks the right engine (WebView2 / WKWebView / WebKitGTK),
// this only deals with parenting, positioning and visibility of the native view.
interface INativeHost
{
    /**
     * Native parent handed to `new WebView(debug, parent)`.
     * HWND on Windows, NSWindow on macOS, null on Linux (webview owns a GtkWindow there).
     */
    function findParentWindow():WindowPtr;

    /**
     * Called once, right after the WebView has been created.
     * Returns false if the webview could not be embedded.
     */
    function attach(webview:WebView):Bool;

    /**
     * Positions the webview in NME window coordinates (stage pixels, top-left origin).
     */
    function setRect(x:Int, y:Int, w:Int, h:Int):Void;

    function setVisible(visible:Bool):Void;

    /**
     * Native views always draw above NME's GL surface, so HaxeUI popups can't be
     * z-ordered over them. Instead we cut these holes out of the webview so the GL
     * content (and its mouse input) shows through. An empty array removes all holes.
     */
    function setClipHoles(holes:Array<ClipRect>):Void;
}
#end
