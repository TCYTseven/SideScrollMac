#include "CMultitouch.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stddef.h>

// Layout of a touch as reported by MultitouchSupport.framework. This is a
// private framework; the struct below matches what it has shipped with since
// macOS 10.6 and is what every open-source gesture tool relies on.
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int fingerID;
    int handID;
    MTVector normalized;
    float size;
    int zero1;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;
    int zero2;
    int zero3;
    float density;
} MTTouch;

typedef void *MTDeviceRef;
typedef int (*MTContactCallback)(MTDeviceRef, MTTouch *, int, double, int);

typedef CFMutableArrayRef (*MTDeviceCreateListFn)(void);
typedef void (*MTRegisterContactFrameCallbackFn)(MTDeviceRef, MTContactCallback);
typedef void (*MTUnregisterContactFrameCallbackFn)(MTDeviceRef, MTContactCallback);
typedef void (*MTDeviceStartFn)(MTDeviceRef, int);
typedef void (*MTDeviceStopFn)(MTDeviceRef);

static cmt_frame_handler g_handler = NULL;
static CFMutableArrayRef g_devices = NULL;
static MTUnregisterContactFrameCallbackFn g_unregister = NULL;
static MTDeviceStopFn g_stop = NULL;

// States: 1-2 hovering, 3 touch began, 4 touching, 5 lifting, 6-7 gone.
static int touch_is_down(int state) { return state == 3 || state == 4; }

static int contact_callback(MTDeviceRef device, MTTouch *touches, int count, double timestamp, int frame) {
    (void)device;
    (void)frame;
    if (!g_handler) return 0;
    int down = 0;
    float sx = 0, sy = 0;
    for (int i = 0; i < count; i++) {
        if (!touch_is_down(touches[i].state)) continue;
        down++;
        sx += touches[i].normalized.position.x;
        sy += touches[i].normalized.position.y;
    }
    if (down > 0) {
        sx /= (float)down;
        sy /= (float)down;
    }
    g_handler(down, sx, sy, timestamp);
    return 0;
}

bool cmt_start(cmt_frame_handler handler) {
    if (g_devices) return true;
    void *lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    if (!lib) return false;

    MTDeviceCreateListFn createList = (MTDeviceCreateListFn)dlsym(lib, "MTDeviceCreateList");
    MTRegisterContactFrameCallbackFn reg = (MTRegisterContactFrameCallbackFn)dlsym(lib, "MTRegisterContactFrameCallback");
    MTDeviceStartFn start = (MTDeviceStartFn)dlsym(lib, "MTDeviceStart");
    g_unregister = (MTUnregisterContactFrameCallbackFn)dlsym(lib, "MTUnregisterContactFrameCallback");
    g_stop = (MTDeviceStopFn)dlsym(lib, "MTDeviceStop");
    if (!createList || !reg || !start) return false;

    g_handler = handler;
    g_devices = createList();
    if (!g_devices) return false;
    CFIndex n = CFArrayGetCount(g_devices);
    for (CFIndex i = 0; i < n; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(g_devices, i);
        reg(dev, contact_callback);
        start(dev, 0);
    }
    return n > 0;
}

void cmt_stop(void) {
    if (!g_devices) return;
    CFIndex n = CFArrayGetCount(g_devices);
    for (CFIndex i = 0; i < n; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(g_devices, i);
        if (g_unregister) g_unregister(dev, contact_callback);
        if (g_stop) g_stop(dev);
    }
    CFRelease(g_devices);
    g_devices = NULL;
    g_handler = NULL;
}
