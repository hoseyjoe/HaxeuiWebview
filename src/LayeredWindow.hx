package;

#if (cpp || hl)
@:cppInclude("windows.h")
@:cppFileCode('#pragma comment(lib, "dwmapi.lib")')
@:cppInclude("dwmapi.h")
#end

/**
 * Creates a transparent layered overlay window that can display HaxeUI content
 * on top of native HWND controls like WebView2.
 * 
 * Uses a separate top-level window with WS_EX_LAYERED for true transparency.
 */
class LayeredWindow {
    private static var overlayHwnd:Int = 0;
    private static var parentHwnd:Int = 0;
    
    /**
     * Initialize the layered window system.
     * This creates a transparent overlay window on top of the main window.
     */
    public static function init():Void {
        #if (cpp || hl)
        parentHwnd = getMainWindowHandle();
        if (parentHwnd == 0) {
            trace("Failed to get main window handle");
            return;
        }
        
        // Make main window click-through where transparent, and create overlay
        setupTransparentOverlay(parentHwnd);
        trace("Layered overlay window created");
        #end
    }
    
    /**
     * Setup the main window as a transparent container with color key.
     * Magenta pixels will be transparent, showing webviews behind.
     */
    private static function setupTransparentOverlay(hwnd:Int):Void {
        #if (cpp || hl)
        untyped __cpp__('
            HWND hWnd = (HWND)(intptr_t){0};
            if (hWnd == NULL) return;
            
            // Get current extended window style
            LONG exStyle = ::GetWindowLongW(hWnd, GWL_EXSTYLE);
            
            // Add layered style and make TOPMOST
            ::SetWindowLongW(hWnd, GWL_EXSTYLE, (exStyle | WS_EX_LAYERED | WS_EX_TOPMOST) & ~WS_EX_TRANSPARENT);
            
            // Make window topmost
            ::SetWindowPos(hWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
            
            // Use color key - magenta (255,0,255) becomes transparent
            COLORREF transparentColor = RGB(255, 0, 255);
            ::SetLayeredWindowAttributes(hWnd, transparentColor, 255, LWA_COLORKEY);
            
            // Force redraw
            ::InvalidateRect(hWnd, NULL, TRUE);
            ::UpdateWindow(hWnd);
        ', hwnd);
        #end
    }
    
    /**
     * Use color key transparency - pixels matching this color become transparent.
     * Call this with a color that your "transparent" areas use (e.g. magenta).
     */
    public static function enableColorKey(r:Int = 255, g:Int = 0, b:Int = 255):Void {
        #if (cpp || hl)
        if (parentHwnd == 0) {
            parentHwnd = getMainWindowHandle();
        }
        
        untyped __cpp__('
            HWND hWnd = (HWND)(intptr_t){0};
            if (hWnd == NULL) return;
            
            // Get current extended window style
            LONG exStyle = ::GetWindowLongW(hWnd, GWL_EXSTYLE);
            
            // Add layered window style
            ::SetWindowLongW(hWnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED);
            
            // Set the transparency color key
            COLORREF transparentColor = RGB({1}, {2}, {3});
            ::SetLayeredWindowAttributes(hWnd, transparentColor, 255, LWA_COLORKEY);
            
            // Force window to redraw
            ::RedrawWindow(hWnd, NULL, NULL, RDW_ERASE | RDW_INVALIDATE | RDW_FRAME | RDW_ALLCHILDREN);
        ', parentHwnd, r, g, b);
        #end
    }
    
    /**
     * Make webview HWNDs use WS_EX_TRANSPARENT so mouse events pass through
     * transparent areas to the HaxeUI layer.
     */
    public static function makeWebviewTransparent(webviewHwnd:Int):Void {
        #if (cpp || hl)
        untyped __cpp__('
            HWND hwnd = (HWND)(intptr_t){0};
            if (hwnd == NULL) return;
            
            LONG exStyle = ::GetWindowLongW(hwnd, GWL_EXSTYLE);
            ::SetWindowLongW(hwnd, GWL_EXSTYLE, exStyle | WS_EX_TRANSPARENT);
        ', webviewHwnd);
        #end
    }
    
    /**
     * Disable transparency and restore normal window behavior.
     */
    public static function disable():Void {
        #if (cpp || hl)
        if (parentHwnd == 0) return;
        
        untyped __cpp__('
            HWND hWnd = (HWND)(intptr_t){0};
            if (hWnd == NULL) return;
            
            // Remove layered window style
            LONG exStyle = ::GetWindowLongW(hWnd, GWL_EXSTYLE);
            ::SetWindowLongW(hWnd, GWL_EXSTYLE, exStyle & ~(WS_EX_LAYERED | WS_EX_COMPOSITED));
            
            // Disable DWM blur
            DWM_BLURBEHIND bb;
            ZeroMemory(&bb, sizeof(bb));
            bb.dwFlags = DWM_BB_ENABLE;
            bb.fEnable = FALSE;
            ::DwmEnableBlurBehindWindow(hWnd, &bb);
            
            // Force redraw
            ::RedrawWindow(hWnd, NULL, NULL, RDW_ERASE | RDW_INVALIDATE | RDW_FRAME | RDW_ALLCHILDREN);
        ', parentHwnd);
        #end
    }
    
    private static function getMainWindowHandle():Int {
        #if (cpp || hl)
        return untyped __cpp__('
            ([]() -> int {
                DWORD pid = ::GetCurrentProcessId();
                HWND best = NULL;
                for (HWND h = ::GetTopWindow(NULL); h != NULL; h = ::GetWindow(h, GW_HWNDNEXT)) {
                    if (::GetParent(h) != NULL) continue;
                    DWORD p = 0;
                    ::GetWindowThreadProcessId(h, &p);
                    if (p != pid) continue;
                    best = h;
                    break;
                }
                if (best == NULL) best = ::GetForegroundWindow();
                return (int)(intptr_t)best;
            })()
        ');
        #else
        return 0;
        #end
    }
}
