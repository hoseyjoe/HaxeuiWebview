package webview.host;

#if (cpp && mac)
import webview.WebView;
import webview.WebView.WindowPtr;
import webview.WebView.WebViewNativeHandleKind;
import webview.host.INativeHost.ClipRect;

// Cocoa / WKWebView.
// webview/webview replaces the parent's contentView with the WKWebView, which would
// remove NME's GL view, so we put the original contentView back and add the
// WKWebView to it as a subview instead.
// hxcpp compiles .cpp (not .mm), so everything goes through the ObjC runtime.
@:cppFileCode('
#include <objc/objc-runtime.h>
#include <CoreGraphics/CoreGraphics.h>

static inline id hx_msg(id obj, const char *sel) {
    return ((id(*)(id, SEL))objc_msgSend)(obj, sel_registerName(sel));
}

static inline id hx_cls_msg(const char *cls, const char *sel) {
    return hx_msg((id)objc_getClass(cls), sel);
}

static inline CGRect hx_bounds(id view) {
#if defined(__x86_64__)
    return ((CGRect(*)(id, SEL))objc_msgSend_stret)(view, sel_registerName("bounds"));
#else
    return ((CGRect(*)(id, SEL))objc_msgSend)(view, sel_registerName("bounds"));
#endif
}

static id hx_find_app_window() {
    id app = hx_cls_msg("NSApplication", "sharedApplication");
    id win = hx_msg(app, "mainWindow");
    if (!win) win = hx_msg(app, "keyWindow");
    if (!win) {
        id windows = hx_msg(app, "windows");
        if (((unsigned long(*)(id, SEL))objc_msgSend)(windows, sel_registerName("count")) > 0)
            win = hx_msg(windows, "firstObject");
    }
    return win;
}
')
@:buildXml('
<target id="haxe">
    <vflag name="-framework" value="AppKit" />
</target>
')
class NativeHostMac implements INativeHost
{
    private var window:WindowPtr = null;
    private var nmeView:WindowPtr = null;
    private var widget:WindowPtr = null;
    private var width:Int = 0;
    private var height:Int = 0;

    public function new() {}

    public function findParentWindow():WindowPtr
    {
        window = untyped __cpp__("::cpp::Pointer<void>((void*)hx_find_app_window())");
        if (window != null)
            nmeView = untyped __cpp__("::cpp::Pointer<void>((void*)hx_msg((id)(void*){0}, \"contentView\"))", window);
        return window;
    }

    public function attach(webview:WebView):Bool
    {
        widget = webview.getNativeHandle(WebViewNativeHandleKind.WEBVIEW_NATIVE_HANDLE_KIND_UI_WIDGET);
        if (widget == null || nmeView == null) return false;

        untyped __cpp__(
            "id win = (id)(void*){0}; id nme = (id)(void*){1}; id wk = (id)(void*){2};
            ((void(*)(id, SEL, id))objc_msgSend)(win, sel_registerName(\"setContentView:\"), nme);
            ((void(*)(id, SEL, id))objc_msgSend)(nme, sel_registerName(\"addSubview:\"), wk);",
            window, nmeView, widget
        );
        return true;
    }

    public function setRect(x:Int, y:Int, w:Int, h:Int):Void
    {
        if (widget == null) return;
        width = w;
        height = h;
        // Stage coords are backing pixels with a top-left origin; NSView frames are
        // points with a bottom-left origin (NME's view is not flipped).
        untyped __cpp__(
            "id win = (id)(void*){0}; id nme = (id)(void*){1}; id wk = (id)(void*){2};
            double scale = ((double(*)(id, SEL))objc_msgSend)(win, sel_registerName(\"backingScaleFactor\"));
            if (scale <= 0) scale = 1;
            CGRect bounds = hx_bounds(nme);
            CGRect frame = CGRectMake({3} / scale, bounds.size.height - ({4} + {6}) / scale, {5} / scale, {6} / scale);
            ((void(*)(id, SEL, CGRect))objc_msgSend)(wk, sel_registerName(\"setFrame:\"), frame);",
            window, nmeView, widget, x, y, w, h
        );
    }

    public function setVisible(visible:Bool):Void
    {
        if (widget == null) return;
        untyped __cpp__(
            "((void(*)(id, SEL, BOOL))objc_msgSend)((id)(void*){0}, sel_registerName(\"setHidden:\"), {1} ? NO : YES)",
            widget, visible
        );
    }

    public function setClipHoles(holes:Array<ClipRect>):Void
    {
        if (widget == null) return;
        untyped __cpp__(
            "id wk = (id)(void*){0};
            ((void(*)(id, SEL, BOOL))objc_msgSend)(wk, sel_registerName(\"setWantsLayer:\"), YES);",
            widget
        );
        if (holes.length == 0)
        {
            untyped __cpp__(
                "((void(*)(id, SEL, id))objc_msgSend)(hx_msg((id)(void*){0}, \"layer\"), sel_registerName(\"setMask:\"), nil)",
                widget
            );
            return;
        }
        // Even-odd mask: the full rect plus one rect per hole leaves the holes transparent.
        // NOTE: a layer mask is visual only, AppKit still hit-tests the WKWebView inside the holes.
        var path:WindowPtr = untyped __cpp__(
            "::cpp::Pointer<void>((void*)([](id win, id wk, int w, int h)->CGMutablePathRef {
                double scale = ((double(*)(id, SEL))objc_msgSend)(win, sel_registerName(\"backingScaleFactor\"));
                if (scale <= 0) scale = 1;
                CGMutablePathRef p = CGPathCreateMutable();
                CGPathAddRect(p, NULL, CGRectMake(0, 0, w / scale, h / scale));
                return p;
            })((id)(void*){0}, (id)(void*){1}, {2}, {3}))",
            window, widget, width, height
        );
        for (hole in holes)
        {
            var x:Int = hole.x, y:Int = hole.y, w:Int = hole.w, h:Int = hole.h;
            untyped __cpp__(
                "{
                    id win = (id)(void*){1}; id wk = (id)(void*){2};
                    double scale = ((double(*)(id, SEL))objc_msgSend)(win, sel_registerName(\"backingScaleFactor\"));
                    if (scale <= 0) scale = 1;
                    BOOL flipped = ((BOOL(*)(id, SEL))objc_msgSend)(wk, sel_registerName(\"isFlipped\"));
                    double hy = flipped ? {4} / scale : ({3} - {4} - {6}) / scale;
                    CGPathAddRect((CGMutablePathRef)(void*){0}, NULL, CGRectMake({5} / scale, hy, {7} / scale, {6} / scale));
                }",
                path, window, widget, height, y, x, h, w
            );
        }
        untyped __cpp__(
            "{
                CGMutablePathRef p = (CGMutablePathRef)(void*){1};
                id mask = hx_cls_msg(\"CAShapeLayer\", \"layer\");
                ((void(*)(id, SEL, CGPathRef))objc_msgSend)(mask, sel_registerName(\"setPath:\"), p);
                id rule = ((id(*)(id, SEL, const char *))objc_msgSend)((id)objc_getClass(\"NSString\"), sel_registerName(\"stringWithUTF8String:\"), \"even-odd\");
                ((void(*)(id, SEL, id))objc_msgSend)(mask, sel_registerName(\"setFillRule:\"), rule);
                ((void(*)(id, SEL, id))objc_msgSend)(hx_msg((id)(void*){0}, \"layer\"), sel_registerName(\"setMask:\"), mask);
                CGPathRelease(p);
            }",
            widget, path
        );
    }
}
#end
