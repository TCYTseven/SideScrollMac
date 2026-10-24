#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Send Window to Next Display
# @raycast.mode silent
# @raycast.packageName SideScroll

# Optional parameters:
# @raycast.icon 🪟
# @raycast.description SideScroll: send window to next display

open -g "sidescroll://move-to-next-display"
