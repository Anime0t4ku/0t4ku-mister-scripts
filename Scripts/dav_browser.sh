#!/bin/sh

BASE_DIR="/media/fat/Scripts/.config/dav_browser"
CONFIG_FILE="$BASE_DIR/dav_browser.ini"
RCLONE_BIN="$BASE_DIR/rclone"
RCLONE_ZIP="/tmp/dav_browser_rclone.zip"
RCLONE_EXTRACT_DIR="/tmp/dav_browser_rclone_extract"
RCLONE_CONFIG="/tmp/dav_browser_rclone.conf"
DOWNLOAD_LOG="/tmp/dav_browser_rclone_download.log"
UNZIP_LOG="/tmp/dav_browser_rclone_unzip.log"
MENU_MAP="/tmp/dav_browser_menu_map.txt"
RCLONE_URL="https://downloads.rclone.org/rclone-current-linux-arm.zip"
MGL_FILE="$BASE_DIR/dav_browser_launch.mgl"

REMOTE_NAME="dav"
CUR_PATH=""
DEST_ROOT=""
SYSTEM_NAME=""
LAST_DOWNLOADED_PATH=""

SERVER_URL=""
USERNAME=""
PASSWORD=""
REMOTE_PATH=""
SKIP_TLS_VERIFY="false"

redraw_screen() {
    printf '\033[2J\033[H' >&2
}

require_tools() {
    if ! command -v dialog >/dev/null 2>&1; then
        echo "dialog is not installed."
        exit 1
    fi

    if ! command -v sed >/dev/null 2>&1; then
        dialog --title "WebDAV Browser" \
               --msgbox "sed is required but not available." 6 45
        clear
        exit 1
    fi

    if ! command -v find >/dev/null 2>&1; then
        dialog --title "WebDAV Browser" \
               --msgbox "find is required but not available." 6 45
        clear
        exit 1
    fi

    if ! command -v awk >/dev/null 2>&1; then
        dialog --title "WebDAV Browser" \
               --msgbox "awk is required but not available." 6 45
        clear
        exit 1
    fi
}

trim() {
    echo "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi

    SERVER_URL="$(trim "$(sed -n 's/^SERVER_URL=//p' "$CONFIG_FILE" | head -n1)")"
    USERNAME="$(trim "$(sed -n 's/^USERNAME=//p' "$CONFIG_FILE" | head -n1)")"
    PASSWORD="$(trim "$(sed -n 's/^PASSWORD=//p' "$CONFIG_FILE" | head -n1)")"
    REMOTE_PATH="$(trim "$(sed -n 's/^REMOTE_PATH=//p' "$CONFIG_FILE" | head -n1)")"
    SKIP_TLS_VERIFY="$(trim "$(sed -n 's/^SKIP_TLS_VERIFY=//p' "$CONFIG_FILE" | head -n1)")"

    [ -z "$SKIP_TLS_VERIFY" ] && SKIP_TLS_VERIFY="false"

    return 0
}

config_is_valid() {
    load_config >/dev/null 2>&1 || return 1
    [ -n "$SERVER_URL" ] || return 1
    [ -n "$USERNAME" ] || return 1
    [ -n "$PASSWORD" ] || return 1
    return 0
}

save_config() {
    mkdir -p "$BASE_DIR"

    cat > "$CONFIG_FILE" <<EOF
SERVER_URL=$SERVER_URL
USERNAME=$USERNAME
PASSWORD=$PASSWORD
REMOTE_PATH=$REMOTE_PATH
SKIP_TLS_VERIFY=$SKIP_TLS_VERIFY
EOF
}

show_keyboard_notice() {
    dialog --title "INI Setup" \
           --yesno "Creating or editing the INI file requires a keyboard.\n\nIf you do not have a keyboard attached, create the INI file manually or use the MiSTer Companion app.\n\nContinue?" 11 70
}

prompt_input() {
    title="$1"
    message="$2"
    initial="$3"

    result=$(dialog --clear \
        --title "$title" \
        --inputbox "$message" 10 70 "$initial" \
        3>&1 1>&2 2>&3)
    status=$?
    redraw_screen

    [ $status -ne 0 ] && return 1

    printf '%s' "$result"
    return 0
}

prompt_tls_verify() {
    current="$1"
    default_choice="1"

    case "$current" in
        true|TRUE|1|yes|YES)
            default_choice="2"
            ;;
    esac

    choice=$(dialog --clear \
        --title "INI Setup" \
        --default-item "$default_choice" \
        --menu "Skip TLS certificate verification?\n\n1 No (recommended if using a valid certificate)\n2 Yes (required for most local/NAS setups)" 14 72 4 \
        1 "No" \
        2 "Yes" \
        3>&1 1>&2 2>&3)
    status=$?
    redraw_screen

    [ $status -ne 0 ] && return 1

    case "$choice" in
        1) printf '%s' "false" ;;
        2) printf '%s' "true" ;;
        *) return 1 ;;
    esac
    return 0
}

create_or_edit_ini() {
    mode="$1"

    show_keyboard_notice
    [ $? -ne 0 ] && return 1
    redraw_screen

    if [ "$mode" = "create" ]; then
        current_server=""
        current_user=""
        current_pass=""
        current_remote=""
        current_tls="false"
    else
        load_config >/dev/null 2>&1
        current_server="$SERVER_URL"
        current_user="$USERNAME"
        current_pass="$PASSWORD"
        current_remote="$REMOTE_PATH"
        current_tls="$SKIP_TLS_VERIFY"
    fi

    value="$(prompt_input "INI Setup" "Enter WebDAV Server URL\n\nExample:\nhttps://192.168.1.100:5006/ROMs" "$current_server")" || return 1
    SERVER_URL="$value"

    value="$(prompt_input "INI Setup" "Enter username" "$current_user")" || return 1
    USERNAME="$value"

    value="$(prompt_input "INI Setup" "Enter password" "$current_pass")" || return 1
    PASSWORD="$value"

    value="$(prompt_input "INI Setup" "Enter remote path (optional)\n\nLeave empty for root." "$current_remote")" || return 1
    REMOTE_PATH="$value"

    value="$(prompt_tls_verify "$current_tls")" || return 1
    SKIP_TLS_VERIFY="$value"

    if [ -z "$SERVER_URL" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
        dialog --title "INI Setup" \
               --msgbox "Server URL, username, and password are required." 7 55
        clear
        return 1
    fi

    save_config

    dialog --title "INI Setup" \
           --msgbox "INI file saved successfully." 6 40
    clear
    return 0
}

show_welcome_screen() {
    while true; do
        if config_is_valid; then
            choice=$(dialog --clear \
                --title "dav_browser by Anime0t4ku" \
                --menu "Browse a WebDAV server from MiSTer, download ROMs, and optionally download and run them directly.\n\nUse this script only with files you legally own or are authorized to access.\n\nUse at your own risk." 17 76 6 \
                1 "Continue" \
                2 "Edit INI File" \
                3 "Exit" \
                3>&1 1>&2 2>&3)
            status=$?
            redraw_screen

            [ $status -ne 0 ] && exit 0

            case "$choice" in
                1) return 0 ;;
                2) create_or_edit_ini "edit" ;;
                3) exit 0 ;;
            esac
        else
            choice=$(dialog --clear \
                --title "dav_browser by Anime0t4ku" \
                --menu "Browse a WebDAV server from MiSTer, download ROMs, and optionally download and run them directly.\n\nUse this script only with files you legally own or are authorized to access.\n\nUse at your own risk.\n\nNo valid INI file was found.\n\nCreating or editing the INI file requires a keyboard.\nIf you do not have a keyboard attached, add the INI file manually or use the MiSTer Companion app." 21 76 6 \
                1 "Continue" \
                2 "Create INI File" \
                3 "Exit" \
                3>&1 1>&2 2>&3)
            status=$?
            redraw_screen

            [ $status -ne 0 ] && exit 0

            case "$choice" in
                1)
                    dialog --title "dav_browser" \
                           --msgbox "A valid INI file is required before continuing.\n\nCreate it here, add it manually, or use the MiSTer Companion app." 9 64
                    clear
                    ;;
                2)
                    create_or_edit_ini "create"
                    ;;
                3)
                    exit 0
                    ;;
            esac
        fi
    done
}

install_rclone() {
    dialog --title "WebDAV Browser Setup" \
           --yesno "rclone is required but not installed.\n\nDownload and install it now?" 8 60
    [ $? -ne 0 ] && exit 0
    redraw_screen

    mkdir -p "$BASE_DIR"
    rm -f "$RCLONE_ZIP"
    rm -rf "$RCLONE_EXTRACT_DIR"
    rm -f "$DOWNLOAD_LOG" "$UNZIP_LOG"
    mkdir -p "$RCLONE_EXTRACT_DIR"

    dialog --title "WebDAV Browser Setup" \
           --infobox "Downloading rclone..." 5 40
    sleep 1

    DOWNLOAD_OK=0

    if command -v curl >/dev/null 2>&1; then
        curl -L --fail "$RCLONE_URL" -o "$RCLONE_ZIP" >"$DOWNLOAD_LOG" 2>&1 && DOWNLOAD_OK=1
        if [ $DOWNLOAD_OK -ne 1 ]; then
            curl -k -L --fail "$RCLONE_URL" -o "$RCLONE_ZIP" >"$DOWNLOAD_LOG" 2>&1 && DOWNLOAD_OK=1
        fi
    fi

    if [ $DOWNLOAD_OK -ne 1 ] && command -v wget >/dev/null 2>&1; then
        wget -O "$RCLONE_ZIP" "$RCLONE_URL" >"$DOWNLOAD_LOG" 2>&1 && DOWNLOAD_OK=1
        if [ $DOWNLOAD_OK -ne 1 ]; then
            wget --no-check-certificate -O "$RCLONE_ZIP" "$RCLONE_URL" >"$DOWNLOAD_LOG" 2>&1 && DOWNLOAD_OK=1
        fi
    fi

    if [ $DOWNLOAD_OK -ne 1 ] || [ ! -s "$RCLONE_ZIP" ]; then
        ERR_MSG="$(tail -n 8 "$DOWNLOAD_LOG" 2>/dev/null)"
        [ -z "$ERR_MSG" ] && ERR_MSG="Unknown download error."
        dialog --title "WebDAV Browser Setup" \
               --msgbox "Failed to download rclone.\n\n$ERR_MSG" 14 72
        clear
        exit 1
    fi

    dialog --title "WebDAV Browser Setup" \
           --infobox "Extracting rclone..." 5 40
    sleep 1

    if command -v unzip >/dev/null 2>&1; then
        unzip -o "$RCLONE_ZIP" -d "$RCLONE_EXTRACT_DIR" >"$UNZIP_LOG" 2>&1
    elif command -v busybox >/dev/null 2>&1; then
        busybox unzip -o "$RCLONE_ZIP" -d "$RCLONE_EXTRACT_DIR" >"$UNZIP_LOG" 2>&1
    else
        dialog --title "WebDAV Browser Setup" \
               --msgbox "No unzip tool found on this MiSTer." 6 45
        clear
        exit 1
    fi

    BIN_PATH="$(find "$RCLONE_EXTRACT_DIR" -type f -name rclone 2>/dev/null | head -n1)"

    if [ -z "$BIN_PATH" ] || [ ! -f "$BIN_PATH" ]; then
        ERR_MSG="$(tail -n 8 "$UNZIP_LOG" 2>/dev/null)"
        [ -z "$ERR_MSG" ] && ERR_MSG="Unknown extraction error."
        dialog --title "WebDAV Browser Setup" \
               --msgbox "Failed to extract rclone.\n\n$ERR_MSG" 14 72
        clear
        exit 1
    fi

    cp "$BIN_PATH" "$RCLONE_BIN" 2>/dev/null
    chmod +x "$RCLONE_BIN" 2>/dev/null

    if [ ! -x "$RCLONE_BIN" ]; then
        dialog --title "WebDAV Browser Setup" \
               --msgbox "rclone was extracted but could not be installed." 7 55
        clear
        exit 1
    fi

    dialog --title "WebDAV Browser Setup" \
           --msgbox "rclone installed successfully." 6 45
    clear
}

require_rclone() {
    if [ ! -x "$RCLONE_BIN" ]; then
        install_rclone
    fi
}

build_rclone_config() {
    OBSCURED_PASS="$("$RCLONE_BIN" obscure "$PASSWORD" 2>/dev/null)"

    if [ -z "$OBSCURED_PASS" ]; then
        dialog --title "WebDAV Browser" \
               --msgbox "Failed to prepare rclone configuration." 6 50
        clear
        exit 1
    fi

    cat > "$RCLONE_CONFIG" <<EOF
[$REMOTE_NAME]
type = webdav
url = $SERVER_URL
vendor = other
user = $USERNAME
pass = $OBSCURED_PASS
EOF

    case "$SKIP_TLS_VERIFY" in
        true|TRUE|1|yes|YES)
            echo "no_check_certificate = true" >> "$RCLONE_CONFIG"
            ;;
    esac
}

build_remote_path() {
    subpath="$1"

    if [ -n "$REMOTE_PATH" ] && [ -n "$subpath" ]; then
        printf "%s:%s/%s" "$REMOTE_NAME" "$REMOTE_PATH" "$subpath"
    elif [ -n "$REMOTE_PATH" ]; then
        printf "%s:%s" "$REMOTE_NAME" "$REMOTE_PATH"
    elif [ -n "$subpath" ]; then
        printf "%s:%s" "$REMOTE_NAME" "$subpath"
    else
        printf "%s:" "$REMOTE_NAME"
    fi
}

test_connection() {
    ROOT_REMOTE="$(build_remote_path "")"

    if "$RCLONE_BIN" --config "$RCLONE_CONFIG" lsf "$ROOT_REMOTE" >/dev/null 2>&1; then
        return 0
    fi

    dialog --title "WebDAV Browser" \
           --msgbox "Could not connect to the WebDAV server.\n\nCheck the settings in:\n$CONFIG_FILE" 9 60
    clear
    exit 1
}

join_path() {
    base="$1"
    name="$2"

    if [ -z "$base" ]; then
        printf "%s" "$name"
    else
        printf "%s/%s" "$base" "$name"
    fi
}

parent_path() {
    p="$1"
    p="${p%/}"
    case "$p" in
        */*) printf "%s" "${p%/*}" ;;
        *) printf "" ;;
    esac
}

list_entries() {
    remote_dir="$(build_remote_path "$CUR_PATH")"
    "$RCLONE_BIN" --config "$RCLONE_CONFIG" lsf "$remote_dir" 2>/tmp/dav_browser_lsf_error.log
}

xml_escape() {
    printf '%s' "$1" | sed 's/&/\&amp;/g; s/"/\&quot;/g; s/'"'"'/\&apos;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

get_mgl_launch_info() {
    system="$1"

    BASE_CORE="$system"
    SETNAME=""
    MGL_DELAY="1"
    MGL_TYPE="f"
    MGL_INDEX="0"

    case "$system" in
        GameGear)
            BASE_CORE="SMS"
            SETNAME="GameGear"
            MGL_INDEX="2"
            ;;
        GBC)
            BASE_CORE="Gameboy"
            SETNAME="GBC"
            ;;
        Atari2600)
            BASE_CORE="Atari7800"
            SETNAME="Atari2600"
            MGL_INDEX="1"
            ;;
        MegaDuck)
            BASE_CORE="Gameboy"
            SETNAME="MegaDuck"
            ;;
        PocketChallengeV2)
            BASE_CORE="WonderSwan"
            SETNAME="PocketChallengeV2"
            ;;
        WonderSwanColor)
            BASE_CORE="WonderSwan"
            SETNAME="WonderSwanColor"
            ;;
        SNES)
            BASE_CORE="SNES"
            MGL_DELAY="2"
            ;;
        TGFX16)
            BASE_CORE="TurboGrafx16"
            ;;
    esac
}

find_core_rbf() {
    system="$1"

    result="$(find /media/fat/_Console /media/fat/_Computer /media/fat/_Utility /media/fat/_Other /media/fat/_Arcade \
        -type f \( -iname "${system}.rbf" -o -iname "${system}_*.rbf" -o -iname "${system}-*.rbf" \) \
        -print 2>/dev/null | sort | tail -n1)"

    if [ -n "$result" ]; then
        result="${result#/media/fat/}"
        result="${result%.rbf}"
        printf '%s' "$result"
        return 0
    fi

    return 1
}

create_launch_mgl() {
    rom_rel_path="$1"
    core_rbf="$2"
    setname="$3"
    delay="$4"
    ftype="$5"
    findex="$6"

    mkdir -p "$BASE_DIR"
    rm -f "$MGL_FILE"

    esc_core="$(xml_escape "$core_rbf")"
    esc_rom="$(xml_escape "$rom_rel_path")"
    esc_setname="$(xml_escape "$setname")"

    {
        echo "<mistergamedescription>"
        echo "    <rbf>$esc_core</rbf>"

        if [ -n "$setname" ]; then
            echo "    <setname>$esc_setname</setname>"
        fi

        echo "    <file delay=\"$delay\" type=\"$ftype\" index=\"$findex\" path=\"$esc_rom\"/>"
        echo "</mistergamedescription>"
    } > "$MGL_FILE"

    [ -f "$MGL_FILE" ]
}

launch_mgl() {
    [ -f "$MGL_FILE" ] || return 1
    echo "load_core $MGL_FILE" > /dev/MiSTer_cmd 2>/dev/null
}

download_file_internal() {
    file_name="$1"
    src_path="$(join_path "$CUR_PATH" "$file_name")"
    remote_file="$(build_remote_path "$src_path")"

    mkdir -p "$DEST_ROOT"

    if "$RCLONE_BIN" --config "$RCLONE_CONFIG" copyto "$remote_file" "${DEST_ROOT}/${file_name}" >/tmp/dav_browser_copy_error.log 2>&1; then
        LAST_DOWNLOADED_PATH="${DEST_ROOT}/${file_name}"
        return 0
    fi

    return 1
}

download_file() {
    file_name="$1"

    dialog --title "Download" \
           --infobox "Downloading to $SYSTEM_NAME...\n\n$file_name" 7 55

    if download_file_internal "$file_name"; then
        dialog --title "Download Complete" \
               --msgbox "Downloaded to:\n\n${LAST_DOWNLOADED_PATH}" 8 60
    else
        ERR_MSG="$(tail -n 8 /tmp/dav_browser_copy_error.log 2>/dev/null)"
        [ -z "$ERR_MSG" ] && ERR_MSG="Unknown download error."
        dialog --title "Download Failed" \
               --msgbox "Could not download:\n\n$file_name\n\n$ERR_MSG" 14 70
    fi
}

download_and_run() {
    file_name="$1"

    dialog --title "Download & Run" \
           --infobox "Downloading to $SYSTEM_NAME...\n\n$file_name" 7 55

    if ! download_file_internal "$file_name"; then
        ERR_MSG="$(tail -n 8 /tmp/dav_browser_copy_error.log 2>/dev/null)"
        [ -z "$ERR_MSG" ] && ERR_MSG="Unknown download error."
        dialog --title "Download Failed" \
               --msgbox "Could not download:\n\n$file_name\n\n$ERR_MSG" 14 70
        return
    fi

    get_mgl_launch_info "$SYSTEM_NAME"
    CORE_RBF="$(find_core_rbf "$BASE_CORE")"

    if [ -z "$CORE_RBF" ]; then
        dialog --title "Download Complete" \
               --msgbox "Downloaded, but no matching core found.\n\nSystem: $SYSTEM_NAME\nBase core: $BASE_CORE\n\nFile:\n${LAST_DOWNLOADED_PATH}" 14 72
        return
    fi

    ROM_REL_PATH="$file_name"

    if ! create_launch_mgl "$ROM_REL_PATH" "$CORE_RBF" "$SETNAME" "$MGL_DELAY" "$MGL_TYPE" "$MGL_INDEX"; then
        dialog --title "Download Complete" \
               --msgbox "Downloaded, but failed to create launcher.\n\n${LAST_DOWNLOADED_PATH}" 12 72
        return
    fi

    dialog --title "Launching" \
           --infobox "Launching:\n\n$file_name" 6 45
    sleep 1

    if launch_mgl; then
        clear
        exit 0
    else
        dialog --title "Launch Failed" \
               --msgbox "Launch failed, but ROM is saved.\n\n${LAST_DOWNLOADED_PATH}" 12 72
    fi
}

select_system() {
    GAME_DIR="/media/fat/games"

    if [ ! -d "$GAME_DIR" ]; then
        dialog --title "WebDAV Browser" \
               --msgbox "Games folder not found:\n\n$GAME_DIR" 7 50
        clear
        exit 1
    fi

    rm -f "$MENU_MAP"
    : > "$MENU_MAP"

    set --
    IDX=1

    for dir in "$GAME_DIR"/*; do
        [ -d "$dir" ] || continue
        name="$(basename "$dir")"
        printf '%s\t%s\n' "$IDX" "$name" >> "$MENU_MAP"
        set -- "$@" "$IDX" "$name"
        IDX=$((IDX + 1))
    done

    if [ $# -eq 0 ]; then
        dialog --title "WebDAV Browser" \
               --msgbox "No system folders found in:\n\n$GAME_DIR" 7 50
        clear
        exit 1
    fi

    CHOICE=$(dialog --clear \
        --title "Select System" \
        --menu "Choose destination folder" 20 60 12 \
        "$@" \
        3>&1 1>&2 2>&3)

    status=$?
    redraw_screen

    [ $status -ne 0 ] && exit 0

    SYSTEM_NAME="$(awk -F '\t' -v c="$CHOICE" '$1==c {print $2}' "$MENU_MAP")"

    if [ -z "$SYSTEM_NAME" ]; then
        dialog --title "WebDAV Browser" \
               --msgbox "Failed to select system." 6 40
        clear
        exit 1
    fi

    DEST_ROOT="$GAME_DIR/$SYSTEM_NAME"
    CUR_PATH=""
}

browse() {
    while true; do
        ENTRIES="$(list_entries)"
        rc=$?

        if [ $rc -ne 0 ]; then
            ERR_MSG="$(tail -n 8 /tmp/dav_browser_lsf_error.log 2>/dev/null)"
            [ -z "$ERR_MSG" ] && ERR_MSG="Unknown folder read error."
            dialog --title "WebDAV Browser" \
                   --msgbox "Could not open this folder.\n\nPath: /${CUR_PATH}\n\n$ERR_MSG" 14 72
            CUR_PATH="$(parent_path "$CUR_PATH")"
            continue
        fi

        rm -f "$MENU_MAP"
        : > "$MENU_MAP"

        set --
        IDX=1

        printf '%s\t%s\t%s\n' "$IDX" "action" "change_system" >> "$MENU_MAP"
        set -- "$@" "$IDX" "[Change System]"
        IDX=$((IDX + 1))

        if [ -n "$CUR_PATH" ]; then
            printf '%s\t%s\t%s\n' "$IDX" "action" "back" >> "$MENU_MAP"
            set -- "$@" "$IDX" "[..]"
            IDX=$((IDX + 1))
        fi

        OLDIFS="$IFS"
        IFS='
'
        for entry in $ENTRIES; do
            [ -z "$entry" ] && continue

            case "$entry" in
                */)
                    display="[DIR] ${entry%/}"
                    etype="dir"
                    evalue="${entry%/}"
                    ;;
                *)
                    display="$entry"
                    etype="file"
                    evalue="$entry"
                    ;;
            esac

            printf '%s\t%s\t%s\n' "$IDX" "$etype" "$evalue" >> "$MENU_MAP"
            set -- "$@" "$IDX" "$display"
            IDX=$((IDX + 1))
        done
        IFS="$OLDIFS"

        printf '%s\t%s\t%s\n' "$IDX" "action" "exit" >> "$MENU_MAP"
        set -- "$@" "$IDX" "[Exit]"

        CHOICE=$(dialog --clear \
            --title "WebDAV Browser" \
            --menu "System: ${SYSTEM_NAME}\nPath: /${CUR_PATH}" \
            22 75 14 \
            "$@" \
            3>&1 1>&2 2>&3)

        status=$?
        redraw_screen

        if [ $status -ne 0 ]; then
            if [ -n "$CUR_PATH" ]; then
                CUR_PATH="$(parent_path "$CUR_PATH")"
            else
                select_system
            fi
            continue
        fi

        SELECTED_TYPE="$(awk -F '\t' -v c="$CHOICE" '$1==c {print $2}' "$MENU_MAP")"
        SELECTED_VALUE="$(awk -F '\t' -v c="$CHOICE" '$1==c {print $3}' "$MENU_MAP")"

        case "$SELECTED_TYPE:$SELECTED_VALUE" in
            action:change_system)
                select_system
                ;;
            action:back)
                CUR_PATH="$(parent_path "$CUR_PATH")"
                ;;
            action:exit)
                exit 0
                ;;
            dir:*)
                CUR_PATH="$(join_path "$CUR_PATH" "$SELECTED_VALUE")"
                ;;
            file:*)
                FILE_ACTION=$(dialog --clear \
                    --title "File Options" \
                    --menu "File: $SELECTED_VALUE" 13 60 5 \
                    1 "Download" \
                    2 "Download & Run" \
                    3 "Cancel" \
                    3>&1 1>&2 2>&3)

                action_status=$?
                redraw_screen

                [ $action_status -ne 0 ] && continue

                case "$FILE_ACTION" in
                    1) download_file "$SELECTED_VALUE" ;;
                    2) download_and_run "$SELECTED_VALUE" ;;
                    *) ;;
                esac
                ;;
            *)
                dialog --title "WebDAV Browser" \
                       --msgbox "Invalid selection." 6 40
                ;;
        esac
    done
}

cleanup() {
    rm -f "$RCLONE_CONFIG"
    rm -f "$RCLONE_ZIP"
    rm -rf "$RCLONE_EXTRACT_DIR"
    rm -f "$MENU_MAP"
}

trap cleanup EXIT

require_tools
show_welcome_screen
load_config
require_rclone
build_rclone_config
test_connection
select_system
browse