#!/bin/bash
# Attaches a CarPlay display in Simulator.app via its menu (there's no simctl command for it).
# With CarPlayExtraOptions on, Simulator asks for the display's width and height first (the scale stays at
# its default @2: typing into that combo box breaks the display). Simulator's CarPlay UI uses an 800x480 px
# area whatever the display size, so other car sizes are covered by the app's preview mode instead.
# Usage: open-carplay.sh <width px> <height px> <scale, ignored> <label>
set -u
OUT="${OUT:-carplay-results}"
W="${1:-800}"; H="${2:-480}"; S="${3:-2}"; LABEL="${4:-default}"

defaults write com.apple.iphonesimulator CarPlay -bool YES
defaults write com.apple.iphonesimulator CarPlayExtraOptions -bool YES

osascript - "$W" "$H" "$S" <<'EOF' || true
on run argv
    set wantW to item 1 of argv
    set wantH to item 2 of argv
    set wantS to item 3 of argv
    tell application "Simulator" to activate
    delay 2
    tell application "System Events"
        tell process "Simulator"
            set frontmost to true
            set clicked to false
            repeat with menuName in {"I/O", "Hardware"}
                try
                    set extMenu to menu 1 of menu item "External Displays" of menu (menuName as string) of menu bar 1
                    log "External Displays items: " & (name of every menu item of extMenu as string)
                    repeat with itemName in {"CarPlay…", "CarPlay...", "CarPlay"}
                        try
                            click menu item (itemName as string) of extMenu
                            set clicked to true
                            log "Clicked " & itemName & " under " & menuName
                            exit repeat
                        end try
                    end repeat
                end try
                if clicked then exit repeat
            end repeat
            if not clicked then log "Could not find External Displays > CarPlay"
            delay 3
            -- Describe whatever dialog appeared, then fill it in.
            repeat with w in every window
                try
                    log "Window '" & (name of w) & "'"
                    repeat with e in (entire contents of w)
                        try
                            log "  " & (class of e as string) & " | " & (name of e as string) & " | " & (value of e as string) & " | " & (description of e as string)
                        end try
                    end repeat
                end try
            end repeat
            repeat with w in every window
                set targets to {w}
                try
                    set targets to targets & (every sheet of w)
                end try
                repeat with t in targets
                    try
                        set fields to every text field of t
                        if (count of fields) >= 2 then
                            -- Type into each field and Tab out so the dialog commits the value.
                            repeat with pair in {{1, wantW}, {2, wantH}}
                                set f to item (item 1 of pair) of fields
                                set focused of f to true
                                delay 0.3
                                keystroke "a" using command down
                                keystroke (item 2 of pair)
                                keystroke tab
                                delay 0.3
                            end repeat
                            log "Fields now: " & (value of item 1 of fields as string) & " x " & (value of item 2 of fields as string)
                        end if
                    end try
                end repeat
            end repeat
        end tell
    end tell
end run
EOF

screencapture -x "$OUT/$LABEL-0-dialog.png" || true

# Confirm the dialog (whatever its default button is called).
osascript <<'EOF' || true
tell application "System Events"
    tell process "Simulator"
        set pressed to false
        repeat with w in every window
            repeat with candidate in {"Connect", "OK", "Done", "Start", "Create", "Continue", "Add"}
                try
                    click button (candidate as string) of w
                    log "Pressed " & candidate & " in window " & (name of w)
                    set pressed to true
                    exit repeat
                end try
                try
                    click button (candidate as string) of sheet 1 of w
                    log "Pressed " & candidate & " in sheet of " & (name of w)
                    set pressed to true
                    exit repeat
                end try
            end repeat
            if pressed then exit repeat
        end repeat
        if not pressed then
            keystroke return
            log "Pressed Return"
        end if
    end tell
end tell
EOF

sleep 8
# Keep the CarPlay window clear of the iPhone window so clicks land on the car screen.
osascript <<'EOF' || true
tell application "System Events"
    tell process "Simulator"
        repeat with w in every window
            if name of w contains "CarPlay" then
                set position of w to {0, 30}
            else if name of w contains "iPhone" then
                set position of w to {700, 30}
            end if
        end repeat
    end tell
end tell
EOF
sleep 2
xcrun simctl io "$UDID" screenshot --display=external "$OUT/$LABEL-1-carplay-home.png" || echo "No external display screenshot"
screencapture -x "$OUT/$LABEL-1-desktop.png" || true
osascript -e 'tell application "System Events" to tell process "Simulator" to get {name, position, size} of every window' || true
