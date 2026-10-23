package webview.host;

#if (cpp || hl)
class NativeHost
{
    public static function create():INativeHost
    {
        #if hl
        // HL has no OS defines, and webview.hdll is only built for Windows so far
        if (Sys.systemName() == "Windows") return new NativeHostWindows();
        trace("HaxeWebview: no HashLink native host for " + Sys.systemName());
        return null;
        #elseif windows
        return new NativeHostWindows();
        #elseif mac
        return new NativeHostMac();
        #elseif linux
        return new NativeHostLinux();
        #else
        trace("HaxeWebview: no native host for this platform");
        return null;
        #end
    }
}
#end
