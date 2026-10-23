package webview.host;

#if cpp
class NativeHost
{
    public static function create():INativeHost
    {
        #if windows
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
