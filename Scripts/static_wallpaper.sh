#!/bin/sh

APP_NAME="static_wallpaper"
APP_TITLE="static_wallpaper by Anime0t4ku"

BASE_DIR="/media/fat/Scripts/.config/$APP_NAME"
CONFIG_FILE="$BASE_DIR/selected_wallpaper.txt"
WALLPAPER_DIR="/media/fat/wallpapers"
TARGET_JPG="/media/fat/menu.jpg"
TARGET_PNG="/media/fat/menu.png"

ORIGINAL_SCRIPT_PATH="$0"
mkdir -p "$BASE_DIR"

# -------------------------
# Setup
# -------------------------

setup_dialog() {
    if command -v dialog >/dev/null 2>&1; then
        DIALOG="dialog"
    else
        if [ ! -f /media/fat/linux/dialog/dialog ]; then
            echo "dialog not found."
            echo ""
            echo "Please install/update the MiSTer Scripts package first,"
            echo "or run a standard MiSTer script like ini_settings.sh once."
            sleep 3
            clear
            exit 1
        fi

        DIALOG="/media/fat/linux/dialog/dialog"
        export LD_LIBRARY_PATH="/media/fat/linux/dialog"
    fi

    export DIALOGRC="${BASE_DIR}/.dialogrc"

    if [ ! -f "${DIALOGRC}" ]; then
        ${DIALOG} --create-rc "${DIALOGRC}" >/dev/null 2>&1
        sed -i "s/use_colors = OFF/use_colors = ON/g" "${DIALOGRC}" 2>/dev/null
        sed -i "s/screen_color = (CYAN,BLUE,ON)/screen_color = (CYAN,BLACK,ON)/g" "${DIALOGRC}" 2>/dev/null
        sync
    fi

    export NCURSES_NO_UTF8_ACS=1
}

setup_tempfile() {
    DIALOG_TEMPFILE="/tmp/${APP_NAME}_dialog_$$.tmp"
    rm -f "$DIALOG_TEMPFILE"
    trap 'rm -f "$DIALOG_TEMPFILE" "/tmp/${APP_NAME}_list_$$.tmp" "/tmp/${APP_NAME}_menu_$$.tmp"' 0 1 2 3 15
}

read_tempfile() {
    DIALOG_RETVAL=$?
    DIALOG_OUTPUT=""
    [ -f "$DIALOG_TEMPFILE" ] && DIALOG_OUTPUT="$(cat "$DIALOG_TEMPFILE")"
}

# -------------------------
# Menu reload
# -------------------------

reload_menu_core() {
    sync
    sleep 1
    echo "load_core /media/fat/menu.rbf" > /dev/MiSTer_cmd
    exit 0
}

# -------------------------
# Wallpaper logic
# -------------------------

get_saved_wallpaper() {
    [ -f "$CONFIG_FILE" ] && cat "$CONFIG_FILE"
}

apply_wallpaper() {
    SRC="$1"

    [ -f "$SRC" ] || return 1

    case "${SRC##*.}" in
        jpg|JPG|jpeg|JPEG)
            rm -f "$TARGET_PNG"
            cp "$SRC" "$TARGET_JPG" || return 1
            rm -f "$TARGET_PNG"
            ;;
        png|PNG)
            rm -f "$TARGET_JPG"
            cp "$SRC" "$TARGET_PNG" || return 1
            rm -f "$TARGET_JPG"
            ;;
        *)
            return 1
            ;;
    esac

    printf "%s" "$SRC" > "$CONFIG_FILE"
    sync
    return 0
}

show_msg() {
    setup_tempfile
    ${DIALOG} --clear \
        --title "$APP_TITLE" \
        --msgbox "$1" 10 60
    clear
}

confirm_yesno() {
    setup_tempfile
    ${DIALOG} --clear \
        --title "$APP_TITLE" \
        --yesno "$1" 10 60
    RET=$?
    clear
    return $RET
}

pick_wallpaper() {
    LIST_FILE="/tmp/${APP_NAME}_list_$$.tmp"
    MENU_FILE="/tmp/${APP_NAME}_menu_$$.tmp"

    if [ ! -d "$WALLPAPER_DIR" ]; then
        show_msg "Wallpaper folder not found:\n$WALLPAPER_DIR"
        return
    fi

    find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) | sort > "$LIST_FILE"

    COUNT="$(wc -l < "$LIST_FILE" | tr -d ' ')"
    if [ "$COUNT" = "0" ]; then
        show_msg "No wallpapers found in:\n$WALLPAPER_DIR"
        return
    fi

    rm -f "$MENU_FILE"

    i=1
    while IFS= read -r FILE; do
        NAME="$(basename "$FILE")"
        printf '"%s" "%s"\n' "$i" "$NAME" >> "$MENU_FILE"
        i=$((i + 1))
    done < "$LIST_FILE"

    setup_tempfile
    eval ${DIALOG} --clear \
        --title '"$APP_TITLE"' \
        --ok-label '"Select"' \
        --cancel-label '"Back"' \
        --menu '"Choose a wallpaper"' 20 72 12 \
        $(cat "$MENU_FILE") \
        2> "$DIALOG_TEMPFILE"

    read_tempfile
    clear

    [ "$DIALOG_RETVAL" -ne 0 ] && return

    SELECTED="$(sed -n "${DIALOG_OUTPUT}p" "$LIST_FILE")"

    if [ -z "$SELECTED" ]; then
        show_msg "Invalid selection."
        return
    fi

    if apply_wallpaper "$SELECTED"; then
        show_msg "Static wallpaper set to:\n$(basename "$SELECTED")\n\nClose the script to reload the Menu core."
    else
        show_msg "Failed to apply wallpaper."
    fi
}

reapply_saved() {
    SAVED="$(get_saved_wallpaper)"

    if [ -z "$SAVED" ]; then
        show_msg "No saved wallpaper found."
        return
    fi

    if apply_wallpaper "$SAVED"; then
        show_msg "Reapplied:\n$(basename "$SAVED")\n\nClose the script to reload the Menu core."
    else
        show_msg "Saved wallpaper could not be reapplied.\n\nIt may have been moved or deleted."
    fi
}

disable_static() {
    if confirm_yesno "Disable static wallpaper and return to random wallpaper mode?"; then
        rm -f "$TARGET_JPG" "$TARGET_PNG"
        sync
        show_msg "Static wallpaper disabled.\n\nClose the script to reload the Menu core."
    fi
}

show_status() {
    if [ -f "$TARGET_JPG" ]; then
        ACTIVE="menu.jpg"
    elif [ -f "$TARGET_PNG" ]; then
        ACTIVE="menu.png"
    else
        ACTIVE="None, random mode"
    fi

    SAVED="$(get_saved_wallpaper)"
    if [ -n "$SAVED" ]; then
        SAVED_NAME="$(basename "$SAVED")"
    else
        SAVED_NAME="None"
    fi

    show_msg "Active: $ACTIVE\n\nSaved selection: $SAVED_NAME"
}

main_menu() {
    while true; do
        setup_tempfile
        ${DIALOG} --clear \
            --title "$APP_TITLE" \
            --cancel-label "Exit" \
            --menu "Choose an option" 18 64 10 \
            "1" "Pick Static Wallpaper" \
            "2" "Reapply Saved Wallpaper" \
            "3" "Disable Static Wallpaper" \
            "4" "Status" \
            2> "$DIALOG_TEMPFILE"

        read_tempfile
        clear

        case "$DIALOG_RETVAL" in
            1|255) reload_menu_core ;;
        esac

        case "$DIALOG_OUTPUT" in
            1) pick_wallpaper ;;
            2) reapply_saved ;;
            3) disable_static ;;
            4) show_status ;;
        esac
    done
}

setup_dialog
main_menu