#!/bin/bash
# Detaches the CarPlay display: closes its Simulator window (or picks External Displays > Disabled).
set -u
osascript <<'EOF' || true
tell application "System Events"
    tell process "Simulator"
        set done to false
        repeat with w in every window
            if name of w contains "CarPlay" then
                try
                    click (first button of w whose subrole is "AXCloseButton")
                    set done to true
                    log "Closed CarPlay window"
                end try
            end if
        end repeat
        if not done then
            repeat with menuName in {"I/O", "Hardware"}
                try
                    click menu item "Disabled" of menu 1 of menu item "External Displays" of menu (menuName as string) of menu bar 1
                    log "Picked External Displays > Disabled"
                    exit repeat
                end try
            end repeat
        end if
    end tell
end tell
EOF
sleep 3
