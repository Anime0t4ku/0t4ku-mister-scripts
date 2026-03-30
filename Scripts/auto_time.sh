#!/bin/sh

TZ_NAME=""
TITLE="auto_time by Anime0t4ku"

d() {
    dialog --clear --title "$TITLE" "$@"
}

fetch_url() {
    URL="$1"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$URL" 2>/dev/null && return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -qO- "$URL" 2>/dev/null && return 0
    fi

    return 1
}

detect_timezone() {
    TZ_NAME="$(fetch_url "https://ipapi.co/timezone" | tr -d '\r\n')"

    if [ -z "$TZ_NAME" ]; then
        TZ_NAME="$(fetch_url "http://worldtimeapi.org/api/ip.txt" | sed -n 's/^timezone: //p' | tr -d '\r\n')"
    fi
}

apply_timezone() {
    if [ -n "$TZ_NAME" ] && [ -f "/usr/share/zoneinfo/posix/$TZ_NAME" ]; then
        mkdir -p /media/fat/linux
        cp "/usr/share/zoneinfo/posix/$TZ_NAME" "/media/fat/linux/timezone"
        return 0
    fi
    return 1
}

d --yesno "Automatically detect and set timezone?" 8 50

if [ $? -ne 0 ]; then
    clear
    exit 0
fi

d --infobox "Detecting timezone..." 5 40
sleep 1

detect_timezone

if [ -z "$TZ_NAME" ]; then
    d --msgbox "Failed to detect timezone." 6 40
    clear
    exit 1
fi

if apply_timezone; then
    d --msgbox "Timezone set to:\n\n$TZ_NAME\n\nReboot MiSTer to apply it fully." 9 50
else
    d --msgbox "Detected timezone:\n\n$TZ_NAME\n\nBut it could not be saved." 10 50
fi

clear
exit 0