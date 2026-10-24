#!/bin/bash
# Removes SideScroll, its settings and its Accessibility entry.
set -u
pkill -x SideScroll 2>/dev/null && sleep 1
rm -rf "/Applications/SideScroll.app" "$HOME/Applications/SideScroll.app"
rm -rf "$HOME/Library/Application Support/SideScroll"
tccutil reset Accessibility app.sidescroll.SideScroll >/dev/null 2>&1
echo "SideScroll removed."
