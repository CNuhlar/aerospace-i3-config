// Print "id x y w h" for every normal on-screen window.
//
// AeroSpace has no way to show its container tree, so where a window sits in
// its row or column is worked out from where the windows are on screen. The ids
// are the same CGWindowIDs AeroSpace uses for %{window-id}. Bounds need no
// permission, unlike titles.
//
// Built by install.sh.
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>

int main(void) {
    CFArrayRef list = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    if (!list) return 1;
    for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
        CFDictionaryRef w = CFArrayGetValueAtIndex(list, i);
        int layer = -1;
        CFNumberRef layerRef = CFDictionaryGetValue(w, kCGWindowLayer);
        if (layerRef) CFNumberGetValue(layerRef, kCFNumberIntType, &layer);
        if (layer != 0) continue;
        unsigned int id = 0;
        CFNumberGetValue(CFDictionaryGetValue(w, kCGWindowNumber), kCFNumberIntType, &id);
        CGRect r;
        if (!CGRectMakeWithDictionaryRepresentation(CFDictionaryGetValue(w, kCGWindowBounds), &r)) continue;
        printf("%u %d %d %d %d\n", id, (int)r.origin.x, (int)r.origin.y, (int)r.size.width, (int)r.size.height);
    }
    CFRelease(list);
    return 0;
}
