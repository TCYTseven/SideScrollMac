#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

#include <stdbool.h>

/// Called on a background thread for every trackpad frame.
/// `count` is the number of fingers touching; `x`/`y` are the average
/// normalized position (0...1) of those fingers; `timestamp` is in seconds.
typedef void (*cmt_frame_handler)(int count, float x, float y, double timestamp);

/// Loads the private MultitouchSupport framework and starts listening on
/// every trackpad. Returns false if the framework is unavailable.
bool cmt_start(cmt_frame_handler handler);

/// Stops all devices started by cmt_start.
void cmt_stop(void);

#endif
