package webview;

import cpp.Pointer;
import cpp.RawPointer;
import cpp.ConstCharStar;

/**
 * WebView2 Native Wrapper
 * 
 * Provides a simple interface to embed WebView2 controls with full rendering support.
 * Based on working C++ implementation using Microsoft WebView2 SDK.
 */

// Opaque handle to WebView2 instance
typedef WebView2Handle = RawPointer<cpp.Void>;

@:keep
@:headerCode('
#include <windows.h>
#include <wrl.h>
#include <WebView2.h>

using namespace Microsoft::WRL;

struct WebView2Instance
{
    HWND parentHwnd;
    ComPtr<ICoreWebView2Controller> controller;
    ComPtr<ICoreWebView2> webview;
    bool isReady;
    
    WebView2Instance() : parentHwnd(nullptr), isReady(false) {}
};

// Forward declarations for global state
extern ComPtr<ICoreWebView2Environment> g_webView2Environment;
extern CRITICAL_SECTION g_webView2Lock;
extern HANDLE g_webView2EnvironmentReady;
extern bool g_webView2LockInitialized;
extern bool g_webView2EnvironmentCreating;

extern "C" void* webview2_create(void* parentHandle);
extern "C" void webview2_navigate(void* handle, const char* url);
extern "C" void webview2_set_html(void* handle, const char* html);
extern "C" void webview2_resize(void* handle, int width, int height);
extern "C" bool webview2_is_ready(void* handle);
extern "C" HWND webview2_get_controller_hwnd(void* handle);
extern "C" void webview2_destroy(void* handle);
')
@:cppFileCode('
#include <windows.h>
#include <wrl.h>
#include <WebView2.h>
#include <queue>

using namespace Microsoft::WRL;

// Global environment and synchronization
static ComPtr<ICoreWebView2Environment> g_webView2Environment;
static CRITICAL_SECTION g_webView2Lock;
static HANDLE g_webView2EnvironmentReady = NULL;
static bool g_webView2LockInitialized = false;
static bool g_webView2EnvironmentCreating = false;

void InitializeWebView2Lock()
{
    if (!g_webView2LockInitialized)
    {
        InitializeCriticalSection(&g_webView2Lock);
        g_webView2EnvironmentReady = CreateEventA(NULL, TRUE, FALSE, NULL);
        g_webView2LockInitialized = true;
    }
}

extern "C" void* webview2_create(void* parentHandle)
{
    HWND hWnd = (HWND)parentHandle;
    if (!hWnd) return nullptr;
    
    InitializeWebView2Lock();
    
    WebView2Instance* instance = new WebView2Instance();
    instance->parentHwnd = hWnd;
    
    EnterCriticalSection(&g_webView2Lock);
    
    // Check if environment already exists or is being created
    if (g_webView2Environment)
    {
        LeaveCriticalSection(&g_webView2Lock);
        
        // Environment ready, create controller immediately
        g_webView2Environment->CreateCoreWebView2Controller(
            instance->parentHwnd,
            Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                [instance](HRESULT result, ICoreWebView2Controller* controller) -> HRESULT
                {
                    if (FAILED(result)) return result;
                    
                    if (controller)
                    {
                        instance->controller = controller;
                        instance->controller->get_CoreWebView2(&instance->webview);
                        
                        RECT bounds;
                        GetClientRect(instance->parentHwnd, &bounds);
                        instance->controller->put_Bounds(bounds);
                        instance->controller->put_IsVisible(TRUE);
                        
                        instance->isReady = true;
                    }
                    return S_OK;
                }
            ).Get()
        );
    }
    else if (g_webView2EnvironmentCreating)
    {
        LeaveCriticalSection(&g_webView2Lock);
        
        // Environment is being created, wait for it
        WaitForSingleObject(g_webView2EnvironmentReady, INFINITE);
        
        if (g_webView2Environment)
        {
            g_webView2Environment->CreateCoreWebView2Controller(
                instance->parentHwnd,
                Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                    [instance](HRESULT result, ICoreWebView2Controller* controller) -> HRESULT
                    {
                        if (FAILED(result)) return result;
                        
                        if (controller)
                        {
                            instance->controller = controller;
                            instance->controller->get_CoreWebView2(&instance->webview);
                            
                            RECT bounds;
                            GetClientRect(instance->parentHwnd, &bounds);
                            instance->controller->put_Bounds(bounds);
                            instance->controller->put_IsVisible(TRUE);
                            
                            instance->isReady = true;
                        }
                        return S_OK;
                    }
                ).Get()
            );
        }
    }
    else
    {
        // First instance - create the environment
        g_webView2EnvironmentCreating = true;
        LeaveCriticalSection(&g_webView2Lock);
        
        CreateCoreWebView2EnvironmentWithOptions(
            nullptr, nullptr, nullptr,
            Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
                [instance](HRESULT result, ICoreWebView2Environment* env) -> HRESULT
                {
                    if (FAILED(result)) 
                    {
                        EnterCriticalSection(&g_webView2Lock);
                        g_webView2EnvironmentCreating = false;
                        SetEvent(g_webView2EnvironmentReady);
                        LeaveCriticalSection(&g_webView2Lock);
                        return result;
                    }
                    
                    EnterCriticalSection(&g_webView2Lock);
                    g_webView2Environment = env;
                    g_webView2EnvironmentCreating = false;
                    SetEvent(g_webView2EnvironmentReady);
                    LeaveCriticalSection(&g_webView2Lock);
                    
                    env->CreateCoreWebView2Controller(
                        instance->parentHwnd,
                        Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                            [instance](HRESULT result, ICoreWebView2Controller* controller) -> HRESULT
                            {
                                if (FAILED(result)) return result;
                                
                                if (controller)
                                {
                                    instance->controller = controller;
                                    instance->controller->get_CoreWebView2(&instance->webview);
                                    
                                    RECT bounds;
                                    GetClientRect(instance->parentHwnd, &bounds);
                                    instance->controller->put_Bounds(bounds);
                                    instance->controller->put_IsVisible(TRUE);
                                    
                                    instance->isReady = true;
                                }
                                return S_OK;
                            }
                        ).Get()
                    );
                    return S_OK;
                }
            ).Get()
        );
    }
    
    return instance;
}

extern "C" void webview2_navigate(void* handle, const char* url)
{
    WebView2Instance* instance = (WebView2Instance*)handle;
    if (!instance || !instance->webview) return;
    
    int len = MultiByteToWideChar(CP_UTF8, 0, url, -1, nullptr, 0);
    wchar_t* wurl = new wchar_t[len];
    MultiByteToWideChar(CP_UTF8, 0, url, -1, wurl, len);
    
    instance->webview->Navigate(wurl);
    delete[] wurl;
}

extern "C" void webview2_set_html(void* handle, const char* html)
{
    WebView2Instance* instance = (WebView2Instance*)handle;
    if (!instance || !instance->webview) return;
    
    int len = MultiByteToWideChar(CP_UTF8, 0, html, -1, nullptr, 0);
    wchar_t* whtml = new wchar_t[len];
    MultiByteToWideChar(CP_UTF8, 0, html, -1, whtml, len);
    
    instance->webview->NavigateToString(whtml);
    delete[] whtml;
}

extern "C" void webview2_resize(void* handle, int width, int height)
{
    WebView2Instance* instance = (WebView2Instance*)handle;
    if (!instance || !instance->controller) return;
    
    RECT bounds;
    bounds.left = 0;
    bounds.top = 0;
    bounds.right = width;
    bounds.bottom = height;
    
    instance->controller->put_Bounds(bounds);
}

extern "C" bool webview2_is_ready(void* handle)
extern "C" HWND webview2_get_controller_hwnd(void* handle)
{
    WebView2Instance* instance = (WebView2Instance*)handle;
    if (!instance) return NULL;
    
    HWND hwnd = NULL;
    if (instance->controller)
    {
        instance->controller->get_ParentWindow(&hwnd);
    }
    return hwnd;
}

extern "C" bool webview2_is_ready(void* handle)
{
    WebView2Instance* instance = (WebView2Instance*)handle;
    return instance && instance->isReady;
}

extern "C" void webview2_destroy(void* handle)
{
    WebView2Instance* instance = (WebView2Instance*)handle;
    if (!instance) return;
    
    if (instance->controller)
    {
        instance->controller->Close();
        instance->controller = nullptr;
    }
    instance->webview = nullptr;
    
    delete instance;
}
')
extern class WebView2Native
{
    @:native("webview2_create")
    public static function create(parentHandle:RawPointer<cpp.Void>):WebView2Handle;

    @:native("webview2_navigate")
    public static function navigate(handle:WebView2Handle, url:ConstCharStar):Void;

    @:native("webview2_set_html")
    public static function setHtml(handle:WebView2Handle, html:ConstCharStar):Void;

    @:native("webview2_resize")
    public static function resize(handle:WebView2Handle, width:Int, height:Int):Void;

    @:native("webview2_is_ready")
    public static function isReady(handle:WebView2Handle):Bool;

    @:native("webview2_destroy")
    public static function destroy(handle:WebView2Handle):Void;
}

/**
 * High-level WebView2 wrapper class
 */
class WebView2
{
    private var handle:WebView2Handle;
    private var ready:Bool = false;
    
    /**
     * Creates a new WebView2 embedded in the parent window.
     * 
     * @param parentHwnd Parent window HWND as Int
     */
    public function new(parentHwnd:Int)
    {
        var parentPtr:RawPointer<cpp.Void> = untyped __cpp__("(void*)(intptr_t){0}", parentHwnd);
        handle = WebView2Native.create(parentPtr);
    }
    
    /**
     * Check if WebView2 is ready to use.
     */
    public function isReady():Bool
    {
        if (handle == null) return false;
        return WebView2Native.isReady(handle);
    
        /**
         * Get the internal WebView2 handle.
         */
        public function getHandle():WebView2Handle
        {
            return handle;
        }
    }
    
    /**
     * Navigate to URL.
     */
    public function navigate(url:String):Void
    {
        if (handle != null)
            WebView2Native.navigate(handle, url);
    }
    
    /**
     * Set HTML content.
     */
    public function setHtml(html:String):Void
    {
        if (handle != null)
            WebView2Native.setHtml(handle, html);
    }
    
    /**
     * Resize to new dimensions.
     */
    public function resize(width:Int, height:Int):Void
    {
        if (handle != null)
            WebView2Native.resize(handle, width, height);
    
        /**
         * Set bounds (position and size).
         */
        public function setBounds(x:Int, y:Int, width:Int, height:Int):Void
        {
            if (handle != null)
                untyped __cpp__("webview2_set_bounds({0}, {1}, {2}, {3}, {4})", handle, x, y, width, height);
        }
    }
    
    /**
     * Clean up resources.
     */
    public function destroy():Void
    {
        if (handle != null)
        {
            WebView2Native.destroy(handle);
            handle = null;
        }
    }
}

extern "C" void webview2_set_bounds(void* handle, int x, int y, int width, int height)
{
    WebView2Instance* instance = (WebView2Instance*)handle;
    if (!instance || !instance->controller) return;
    
    RECT bounds;
    bounds.left = x;
    bounds.top = y;
    bounds.right = x + width;
    bounds.bottom = y + height;
    
    instance->controller->put_Bounds(bounds);
}

extern "C" void webview2_set_bounds(void* handle, int x, int y, int width, int height);
