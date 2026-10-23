package webview.host;

#if (cpp && linux)
import webview.WebView;
import webview.WebView.WindowPtr;
import webview.host.INativeHost.ClipRect;

// GTK / WebKitGTK.
// webview/webview can only embed into a GtkWindow, but NME draws into a plain
// SDL/X11 window. So we let webview create its own GtkWindow and then reparent
// that window's X11 window into the NME window (X11 only, GDK_BACKEND is forced
// to x11 so this also works under XWayland).
@:cppFileCode('
#include <stdlib.h>
#include <unistd.h>
#include <gtk/gtk.h>
#include <gdk/gdkx.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>

static bool hx_window_pid_matches(Display *dpy, Window w, Atom pidAtom, unsigned long pid) {
    Atom type; int format; unsigned long count, after; unsigned char *data = NULL;
    bool match = false;
    if (XGetWindowProperty(dpy, w, pidAtom, 0, 1, False, XA_CARDINAL, &type, &format, &count, &after, &data) == Success && data) {
        if (count > 0) match = (*(unsigned long *)data == pid);
        XFree(data);
    }
    return match;
}

// Depth-first search under the root (window managers reparent clients into frames)
static Window hx_find_pid_window(Display *dpy, Window w, Atom pidAtom, unsigned long pid, Window exclude, int depth) {
    if (w != exclude && hx_window_pid_matches(dpy, w, pidAtom, pid)) {
        XWindowAttributes attrs;
        if (XGetWindowAttributes(dpy, w, &attrs) && attrs.map_state == IsViewable) return w;
    }
    if (depth > 3) return 0;
    Window root, parent, *children = NULL; unsigned int n = 0;
    Window found = 0;
    if (XQueryTree(dpy, w, &root, &parent, &children, &n)) {
        for (unsigned int i = 0; i < n && !found; i++)
            found = hx_find_pid_window(dpy, children[i], pidAtom, pid, exclude, depth + 1);
        if (children) XFree(children);
    }
    return found;
}
')
@:buildXml('
<target id="haxe">
    <lib name="-lX11" />
</target>
')
class NativeHostLinux implements INativeHost
{
    private var gtkWindow:WindowPtr = null;
    private var attached:Bool = false;
    private var width:Int = 0;
    private var height:Int = 0;

    public function new()
    {
        // Reparenting needs X11 window ids; must be set before webview calls gtk_init
        untyped __cpp__("setenv(\"GDK_BACKEND\", \"x11\", 0);");
    }

    public function findParentWindow():WindowPtr
    {
        // Let webview create (and own) a GtkWindow; we reparent it in attach()
        return null;
    }

    public function attach(webview:WebView):Bool
    {
        gtkWindow = webview.getWindow();
        if (gtkWindow == null) return false;

        attached = untyped __cpp__(
            "([](void *gw)->bool {
                GtkWidget *win = GTK_WIDGET(gw);
                GdkDisplay *gdkDisplay = gdk_display_get_default();
                if (!GDK_IS_X11_DISPLAY(gdkDisplay)) return false;
                Display *dpy = gdk_x11_display_get_xdisplay(gdkDisplay);

                gtk_widget_hide(win);
                gtk_window_set_decorated(GTK_WINDOW(win), FALSE);
                gtk_window_set_skip_taskbar_hint(GTK_WINDOW(win), TRUE);
                gtk_widget_realize(win);
                Window child = gdk_x11_window_get_xid(gtk_widget_get_window(win));

                Atom pidAtom = XInternAtom(dpy, \"_NET_WM_PID\", True);
                if (pidAtom == None) return false;
                Window parent = hx_find_pid_window(dpy, DefaultRootWindow(dpy), pidAtom, (unsigned long)getpid(), child, 0);
                if (!parent) return false;

                XReparentWindow(dpy, child, parent, 0, 0);
                gtk_widget_show_all(win);
                XFlush(dpy);
                return true;
            })((void*){0})",
            gtkWindow
        );

        if (!attached)
            trace("HaxeWebview: could not embed into the NME X11 window, the webview will float");
        return attached;
    }

    public function setRect(x:Int, y:Int, w:Int, h:Int):Void
    {
        if (gtkWindow == null) return;
        width = w;
        height = h;
        if (!attached)
        {
            untyped __cpp__("gtk_window_resize(GTK_WINDOW((void*){0}), {1}, {2})", gtkWindow, w, h);
            return;
        }
        // GTK still thinks this is a top-level, so size through GTK (for allocation)
        // and position through X11 (relative to the new parent)
        untyped __cpp__(
            "GtkWidget *win = GTK_WIDGET((void*){0});
            gtk_window_resize(GTK_WINDOW(win), {3}, {4});
            Display *dpy = gdk_x11_display_get_xdisplay(gdk_display_get_default());
            XMoveResizeWindow(dpy, gdk_x11_window_get_xid(gtk_widget_get_window(win)), {1}, {2}, {3}, {4});
            XFlush(dpy);",
            gtkWindow, x, y, w, h
        );
    }

    public function setVisible(visible:Bool):Void
    {
        if (gtkWindow == null) return;
        untyped __cpp__(
            "if ({1}) gtk_widget_show_all(GTK_WIDGET((void*){0})); else gtk_widget_hide(GTK_WIDGET((void*){0}));",
            gtkWindow, visible
        );
    }

    public function setClipHoles(holes:Array<ClipRect>):Void
    {
        // Holes only make sense once the window sits inside the NME window
        if (gtkWindow == null || !attached) return;
        if (holes.length == 0)
        {
            untyped __cpp__(
                "gtk_widget_shape_combine_region(GTK_WIDGET((void*){0}), NULL); gtk_widget_input_shape_combine_region(GTK_WIDGET((void*){0}), NULL);",
                gtkWindow
            );
            return;
        }
        var region:WindowPtr = untyped __cpp__(
            "::cpp::Pointer<void>((void*)([](int w, int h)->cairo_region_t* { cairo_rectangle_int_t r = {0, 0, w, h}; return cairo_region_create_rectangle(&r); })({0}, {1}))",
            width, height
        );
        for (hole in holes)
        {
            var x:Int = hole.x, y:Int = hole.y, w:Int = hole.w, h:Int = hole.h;
            untyped __cpp__(
                "{ cairo_rectangle_int_t r = {{1}, {2}, {3}, {4}}; cairo_region_subtract_rectangle((cairo_region_t*)(void*){0}, &r); }",
                region, x, y, w, h
            );
        }
        // XShape under the hood: clips both drawing and input
        untyped __cpp__(
            "{ GtkWidget *win = GTK_WIDGET((void*){0}); cairo_region_t *rg = (cairo_region_t*)(void*){1};
            gtk_widget_shape_combine_region(win, rg);
            gtk_widget_input_shape_combine_region(win, rg);
            cairo_region_destroy(rg); }",
            gtkWindow, region
        );
    }
}
#end
