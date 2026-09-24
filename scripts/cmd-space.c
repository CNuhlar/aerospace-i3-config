// Press cmd+space, and only cmd+space.
//
// mod+d is alt+d, and alt is usually still held when this runs. A keystroke sent
// through System Events picks up that held alt and becomes cmd+alt+space - a
// Finder search window instead of Spotlight - so launcher.sh used to wait 0.3s
// for alt to be released, on top of osascript's own startup. Events from a
// private source carry exactly the flags set on them, so this fires at once.
// The shortcut is only recognised with a real cmd press around it, so press and
// release cmd the way a keyboard does rather than flagging a lone space.
//
// Built by install.sh: clang -O2 -framework ApplicationServices -o cmd-space cmd-space.c
#include <ApplicationServices/ApplicationServices.h>
#include <unistd.h>

static void key(CGEventSourceRef src, CGKeyCode code, bool down, CGEventFlags flags) {
    CGEventRef e = CGEventCreateKeyboardEvent(src, code, down);
    CGEventSetFlags(e, flags);
    CGEventPost(kCGHIDEventTap, e);
    CFRelease(e);
}

int main(void) {
    CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStatePrivate);
    const CGKeyCode cmd = 55, space = 49;
    key(src, cmd, true, kCGEventFlagMaskCommand);
    usleep(10000);
    key(src, space, true, kCGEventFlagMaskCommand);
    key(src, space, false, kCGEventFlagMaskCommand);
    usleep(10000);
    key(src, cmd, false, 0);
    CFRelease(src);
    return 0;
}
