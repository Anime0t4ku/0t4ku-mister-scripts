#!/bin/sh

TITLE="Syncthing for MiSTer by Anime0t4ku"

BASE="/media/fat/Scripts/.config/syncthing"
BIN_DIR="$BASE/bin"
HOME_DIR="$BASE/home"
TMP_DIR="$BASE/tmp"
LOG_FILE="$BASE/syncthing.log"
INSTALL_LOG="$BASE/install.log"
DOWNLOAD_DEBUG="$TMP_DIR/download_debug.txt"
PID_FILE="$BASE/syncthing.pid"
START_SCRIPT="$BASE/syncthing_service.sh"

USER_STARTUP="/media/fat/linux/user-startup.sh"

VERSION="v2.0.16"
ARCHIVE="syncthing-linux-arm-$VERSION.tar.gz"
EXTRACTED_DIR="$TMP_DIR/syncthing-linux-arm-$VERSION"
DOWNLOAD_URL="https://github.com/syncthing/syncthing/releases/download/$VERSION/$ARCHIVE"

GUI_PORT="8384"
GUI_ADDRESS="0.0.0.0:$GUI_PORT"

mkdir -p "$BASE" "$BIN_DIR" "$HOME_DIR" "$TMP_DIR"

d() {
    clear
    dialog --clear --title "$TITLE" "$@"
    clear
}

info() {
    dialog --title "$TITLE" --infobox "$1" 10 82
}

msg() {
    d --msgbox "$1" 14 90
}

yesno() {
    d --yesno "$1" 14 90
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

log_line() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)] $1" >> "$INSTALL_LOG"
}

log_cmd_info() {
    {
        echo ""
        echo "===== System / command info ====="
        echo "Date: $(date 2>/dev/null)"
        echo "uname: $(uname -a 2>/dev/null)"
        echo "PATH: $PATH"
        echo ""
        echo "Commands:"
        echo "dialog: $(command -v dialog 2>/dev/null)"
        echo "curl:   $(command -v curl 2>/dev/null)"
        echo "wget:   $(command -v wget 2>/dev/null)"
        echo "tar:    $(command -v tar 2>/dev/null)"
        echo "gzip:   $(command -v gzip 2>/dev/null)"
        echo "find:   $(command -v find 2>/dev/null)"
        echo "pgrep:  $(command -v pgrep 2>/dev/null)"
        echo "pkill:  $(command -v pkill 2>/dev/null)"
        echo ""
        echo "Network:"
        echo "hostname -I: $(hostname -I 2>/dev/null)"
        echo "ip route:"
        ip route 2>/dev/null
        echo "================================="
        echo ""
    } >> "$INSTALL_LOG"
}

reset_install_log() {
    mkdir -p "$BASE" "$TMP_DIR"

    {
        echo "Syncthing for MiSTer Installer Log"
        echo "=================================="
        echo "Started: $(date 2>/dev/null)"
        echo "Version: $VERSION"
        echo "Archive: $ARCHIVE"
        echo "URL: $DOWNLOAD_URL"
        echo "Base: $BASE"
        echo ""
    } > "$INSTALL_LOG"

    log_cmd_info
}

append_file_to_install_log() {
    FILE="$1"
    TITLE_TEXT="$2"

    {
        echo ""
        echo "===== $TITLE_TEXT ====="
        if [ -f "$FILE" ]; then
            cat "$FILE"
        else
            echo "File not found: $FILE"
        fi
        echo "===== End $TITLE_TEXT ====="
        echo ""
    } >> "$INSTALL_LOG"
}

download_file() {
    URL="$1"
    OUT="$2"

    rm -f "$OUT" "$DOWNLOAD_DEBUG"

    {
        echo "Download debug"
        echo "=============="
        echo "Date: $(date 2>/dev/null)"
        echo "URL: $URL"
        echo "Output: $OUT"
        echo ""
    } > "$DOWNLOAD_DEBUG"

    log_line "Starting download."
    log_line "URL: $URL"
    log_line "Output: $OUT"

    if has_cmd curl; then
        log_line "Trying curl download."
        echo "Trying curl..." >> "$DOWNLOAD_DEBUG"

        curl -k -L --fail \
            --connect-timeout 20 \
            --max-time 300 \
            -A "MiSTer-Syncthing-Installer" \
            -w "\nHTTP_CODE=%{http_code}\nCONTENT_TYPE=%{content_type}\nSIZE_DOWNLOAD=%{size_download}\nURL_EFFECTIVE=%{url_effective}\n" \
            -o "$OUT" \
            "$URL" >> "$DOWNLOAD_DEBUG" 2>&1

        CURL_RESULT=$?

        echo "" >> "$DOWNLOAD_DEBUG"
        echo "curl exit code: $CURL_RESULT" >> "$DOWNLOAD_DEBUG"

        if [ -f "$OUT" ]; then
            SIZE="$(wc -c < "$OUT" 2>/dev/null)"
            echo "Downloaded size: $SIZE bytes" >> "$DOWNLOAD_DEBUG"
            log_line "curl downloaded size: $SIZE bytes"
        fi

        if [ $CURL_RESULT -eq 0 ] && [ -s "$OUT" ]; then
            if gzip -t "$OUT" >/dev/null 2>&1; then
                log_line "curl download succeeded and gzip validation passed."
                append_file_to_install_log "$DOWNLOAD_DEBUG" "Download debug"
                return 0
            fi

            log_line "curl downloaded a file, but gzip validation failed."

            {
                echo ""
                echo "curl downloaded a file, but it is not a valid gzip archive."
                echo ""
                echo "First 500 bytes of downloaded file:"
                echo "-----------------------------------"
                head -c 500 "$OUT" 2>/dev/null
                echo ""
                echo "-----------------------------------"
            } >> "$DOWNLOAD_DEBUG"
        else
            log_line "curl failed with exit code: $CURL_RESULT"
        fi
    else
        log_line "curl not found."
        echo "curl not found." >> "$DOWNLOAD_DEBUG"
    fi

    if has_cmd wget; then
        log_line "Trying wget download."

        {
            echo ""
            echo "Trying wget..."
        } >> "$DOWNLOAD_DEBUG"

        wget --no-check-certificate \
            --timeout=20 \
            --tries=3 \
            -O "$OUT" \
            "$URL" >> "$DOWNLOAD_DEBUG" 2>&1

        WGET_RESULT=$?

        echo "" >> "$DOWNLOAD_DEBUG"
        echo "wget exit code: $WGET_RESULT" >> "$DOWNLOAD_DEBUG"

        if [ -f "$OUT" ]; then
            SIZE="$(wc -c < "$OUT" 2>/dev/null)"
            echo "Downloaded size: $SIZE bytes" >> "$DOWNLOAD_DEBUG"
            log_line "wget downloaded size: $SIZE bytes"
        fi

        if [ $WGET_RESULT -eq 0 ] && [ -s "$OUT" ]; then
            if gzip -t "$OUT" >/dev/null 2>&1; then
                log_line "wget download succeeded and gzip validation passed."
                append_file_to_install_log "$DOWNLOAD_DEBUG" "Download debug"
                return 0
            fi

            log_line "wget downloaded a file, but gzip validation failed."

            {
                echo ""
                echo "wget downloaded a file, but it is not a valid gzip archive."
                echo ""
                echo "First 500 bytes of downloaded file:"
                echo "-----------------------------------"
                head -c 500 "$OUT" 2>/dev/null
                echo ""
                echo "-----------------------------------"
            } >> "$DOWNLOAD_DEBUG"
        else
            log_line "wget failed with exit code: $WGET_RESULT"
        fi
    else
        log_line "wget not found."
        echo "wget not found." >> "$DOWNLOAD_DEBUG"
    fi

    append_file_to_install_log "$DOWNLOAD_DEBUG" "Download debug"

    rm -f "$OUT"
    return 1
}

get_mister_ip() {
    IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

    if [ -z "$IP" ]; then
        IP="$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p' | head -n 1)"
    fi

    if [ -z "$IP" ]; then
        IP="MiSTer-IP"
    fi

    echo "$IP"
}

is_installed() {
    [ -x "$BIN_DIR/syncthing" ]
}

is_running() {
    if [ -f "$PID_FILE" ]; then
        PID="$(cat "$PID_FILE" 2>/dev/null)"
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            return 0
        fi
    fi

    ps | grep "$BIN_DIR/syncthing" | grep -v grep >/dev/null 2>&1
}

stop_existing_syncthing() {
    if [ -f "$PID_FILE" ]; then
        PID="$(cat "$PID_FILE" 2>/dev/null)"
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            kill "$PID" 2>/dev/null
            rm -f "$PID_FILE"
            sleep 1
        fi
    fi

    PIDS="$(ps | grep "$BIN_DIR/syncthing" | grep -v grep | awk '{print $1}')"

    for PID in $PIDS; do
        if [ "$PID" != "$$" ]; then
            kill "$PID" 2>/dev/null
        fi
    done
}

is_boot_enabled() {
    grep -q "$START_SCRIPT start" "$USER_STARTUP" 2>/dev/null
}

create_service_script() {
    log_line "Creating service script: $START_SCRIPT"

    cat > "$START_SCRIPT" <<EOF
#!/bin/sh

BASE="$BASE"
BIN="\$BASE/bin/syncthing"
HOME_DIR="\$BASE/home"
LOG_FILE="\$BASE/syncthing.log"
PID_FILE="\$BASE/syncthing.pid"
GUI_ADDRESS="$GUI_ADDRESS"

mkdir -p "\$HOME_DIR"

is_running() {
    if [ -f "\$PID_FILE" ]; then
        PID="\$(cat "\$PID_FILE" 2>/dev/null)"
        if [ -n "\$PID" ] && kill -0 "\$PID" 2>/dev/null; then
            return 0
        fi
    fi

    ps | grep "\$BIN" | grep -v grep >/dev/null 2>&1
}

stop_existing() {
    if [ -f "\$PID_FILE" ]; then
        PID="\$(cat "\$PID_FILE" 2>/dev/null)"
        if [ -n "\$PID" ] && kill -0 "\$PID" 2>/dev/null; then
            kill "\$PID" 2>/dev/null
            rm -f "\$PID_FILE"
            sleep 1
        fi
    fi

    PIDS="\$(ps | grep "\$BIN" | grep -v grep | awk '{print \$1}')"

    for PID in \$PIDS; do
        if [ "\$PID" != "\$\$" ]; then
            kill "\$PID" 2>/dev/null
        fi
    done
}

case "\$1" in
    start)
        if is_running; then
            echo "Syncthing is already running."
            exit 0
        fi

        nohup "\$BIN" serve \\
            --home "\$HOME_DIR" \\
            --no-browser \\
            --gui-address "\$GUI_ADDRESS" \\
            > "\$LOG_FILE" 2>&1 &

        echo \$! > "\$PID_FILE"
        echo "Syncthing started."
        ;;

    stop)
        stop_existing
        echo "Syncthing stopped."
        ;;

    status)
        if is_running; then
            echo "Syncthing is running."
            exit 0
        fi

        echo "Syncthing is not running."
        exit 1
        ;;

    *)
        echo "Usage: \$0 {start|stop|status}"
        exit 1
        ;;
esac
EOF

    chmod +x "$START_SCRIPT"
}

extract_archive() {
    ARCHIVE_PATH="$1"
    DEST_DIR="$2"

    log_line "Extract command with owner fix:"
    log_line "tar --no-same-owner --no-same-permissions -xzf $ARCHIVE_PATH -C $DEST_DIR"

    tar --no-same-owner --no-same-permissions -xzf "$ARCHIVE_PATH" -C "$DEST_DIR" >> "$INSTALL_LOG" 2>&1
    RESULT=$?

    if [ $RESULT -eq 0 ]; then
        return 0
    fi

    log_line "tar with --no-same-owner failed with exit code $RESULT."
    log_line "Trying fallback extraction using gzip pipe."

    gzip -dc "$ARCHIVE_PATH" | tar --no-same-owner --no-same-permissions -xf - -C "$DEST_DIR" >> "$INSTALL_LOG" 2>&1
    return $?
}

find_real_binary() {
    REAL_BIN="$EXTRACTED_DIR/syncthing"

    if [ -x "$REAL_BIN" ]; then
        echo "$REAL_BIN"
        return 0
    fi

    if [ -f "$REAL_BIN" ]; then
        chmod +x "$REAL_BIN"
        echo "$REAL_BIN"
        return 0
    fi

    return 1
}

install_syncthing() {
    reset_install_log

    log_line "Install / Update selected."

    if ! has_cmd tar; then
        log_line "ERROR: tar was not found."
        msg "tar was not found on this MiSTer installation.\n\nInstaller log:\n$INSTALL_LOG"
        return
    fi

    if ! has_cmd gzip; then
        log_line "ERROR: gzip was not found."
        msg "gzip was not found on this MiSTer installation.\n\nInstaller log:\n$INSTALL_LOG"
        return
    fi

    if ! has_cmd curl && ! has_cmd wget; then
        log_line "ERROR: neither curl nor wget was found."
        msg "Neither curl nor wget was found.\n\nCannot download Syncthing.\n\nInstaller log:\n$INSTALL_LOG"
        return
    fi

    yesno "This will download and install Syncthing $VERSION for Linux ARM.\n\nInstall location:\n$BASE\n\nContinue?"
    [ $? -ne 0 ] && {
        log_line "Install cancelled by user."
        return
    }

    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR" "$BIN_DIR" "$HOME_DIR"

    log_line "Temporary folder reset: $TMP_DIR"

    info "Step 1/4: Downloading Syncthing $VERSION...\n\nPlease wait."

    if ! download_file "$DOWNLOAD_URL" "$TMP_DIR/$ARCHIVE"; then
        log_line "ERROR: download failed or archive validation failed."
        msg "Download failed or invalid archive.\n\nInstaller log:\n$INSTALL_LOG\n\nDownload debug:\n$DOWNLOAD_DEBUG"
        return
    fi

    log_line "Download completed and archive passed gzip validation."

    info "Step 2/4: Validating archive...\n\nPlease wait."

    if ! gzip -t "$TMP_DIR/$ARCHIVE" >/dev/null 2>&1; then
        log_line "ERROR: gzip validation failed before extraction."
        msg "Downloaded file is not a valid gzip archive.\n\nInstaller log:\n$INSTALL_LOG\n\nDownload debug:\n$DOWNLOAD_DEBUG"
        return
    fi

    info "Step 3/4: Extracting Syncthing...\n\nPlease wait."

    if ! extract_archive "$TMP_DIR/$ARCHIVE" "$TMP_DIR"; then
        log_line "ERROR: tar extraction failed."
        msg "Extraction failed.\n\nInstaller log:\n$INSTALL_LOG"
        return
    fi

    log_line "Extraction completed."
    log_line "Listing extracted files."

    {
        echo ""
        echo "===== Extracted file list ====="
        find "$TMP_DIR" -maxdepth 4 -type f 2>/dev/null
        echo "===== End extracted file list ====="
        echo ""
    } >> "$INSTALL_LOG"

    FOUND_BIN="$(find_real_binary)"

    if [ -z "$FOUND_BIN" ]; then
        log_line "ERROR: Real Syncthing binary not found at expected path: $EXTRACTED_DIR/syncthing"
        msg "Could not find the real Syncthing binary after extraction.\n\nExpected:\n$EXTRACTED_DIR/syncthing\n\nInstaller log:\n$INSTALL_LOG"
        return
    fi

    log_line "Found real binary: $FOUND_BIN"

    info "Step 4/4: Installing Syncthing binary...\n\nPlease wait."

    if is_running; then
        log_line "Existing Syncthing binary process is running. Stopping before install."
        stop_existing_syncthing >> "$INSTALL_LOG" 2>&1
        sleep 1
    else
        log_line "No existing Syncthing binary process detected."
    fi

    log_line "Copying binary to: $BIN_DIR/syncthing"

    if ! cp "$FOUND_BIN" "$BIN_DIR/syncthing" >> "$INSTALL_LOG" 2>&1; then
        log_line "ERROR: failed to copy binary."
        msg "Failed to copy Syncthing binary.\n\nInstaller log:\n$INSTALL_LOG"
        return
    fi

    chmod +x "$BIN_DIR/syncthing"

    create_service_script

    VERSION_TEXT="$("$BIN_DIR/syncthing" --version 2>>"$INSTALL_LOG" | head -n 1)"

    log_line "Installed binary version: $VERSION_TEXT"
    log_line "Install completed successfully."

    msg "Syncthing installed successfully.\n\n$VERSION_TEXT"
}

start_syncthing() {
    if ! is_installed; then
        msg "Syncthing is not installed yet.\n\nChoose Install / Update first."
        return
    fi

    create_service_script

    info "Starting Syncthing...\n\nPlease wait."

    "$START_SCRIPT" start >/dev/null 2>&1

    sleep 2

    if ! is_running; then
        msg "Syncthing did not appear to start.\n\nRuntime log:\n$LOG_FILE\n\nInstaller log:\n$INSTALL_LOG"
    fi
}

stop_syncthing() {
    if ! is_installed; then
        msg "Syncthing is not installed yet."
        return
    fi

    info "Stopping Syncthing...\n\nPlease wait."

    "$START_SCRIPT" stop >/dev/null 2>&1

    sleep 1
}

enable_boot() {
    if ! is_installed; then
        msg "Syncthing is not installed yet.\n\nChoose Install / Update first."
        return
    fi

    create_service_script
    mkdir -p "$(dirname "$USER_STARTUP")"

    if [ ! -f "$USER_STARTUP" ]; then
        echo "#!/bin/sh" > "$USER_STARTUP"
        chmod +x "$USER_STARTUP"
    fi

    if is_boot_enabled; then
        return
    fi

    {
        echo ""
        echo "# Start Syncthing"
        echo "$START_SCRIPT start &"
    } >> "$USER_STARTUP"

    chmod +x "$USER_STARTUP"
}

disable_boot() {
    if [ ! -f "$USER_STARTUP" ]; then
        return
    fi

    TMP_FILE="$TMP_DIR/user-startup.tmp"
    mkdir -p "$TMP_DIR"

    grep -v "$START_SCRIPT start" "$USER_STARTUP" | grep -v "# Start Syncthing" > "$TMP_FILE"
    cp "$TMP_FILE" "$USER_STARTUP"
    chmod +x "$USER_STARTUP"
}

toggle_boot() {
    if ! is_installed; then
        msg "Syncthing is not installed yet.\n\nChoose Install / Update first."
        return
    fi

    if is_boot_enabled; then
        yesno "Syncthing currently starts automatically on boot.\n\nDisable start on boot?"
        [ $? -ne 0 ] && return

        disable_boot
    else
        yesno "Syncthing does not currently start automatically on boot.\n\nEnable start on boot?"
        [ $? -ne 0 ] && return

        enable_boot
    fi
}

first_warning() {
    FLAG="$BASE/.warning_shown"

    if [ -f "$FLAG" ]; then
        return
    fi

    msg "Warning:\n\nThis script exposes Syncthing's web UI on your local network at port $GUI_PORT.\n\nUse this only on a trusted home network.\n\nAfter first setup, open the Syncthing web UI and configure folders/devices carefully.\n\nDo not sync the entire SD card."

    touch "$FLAG"
}

main_menu() {
    first_warning

    while true; do
        IP="$(get_mister_ip)"

        if is_running; then
            MAIN_STATUS="Running"
            WEB_STATUS="Web UI: http://$IP:$GUI_PORT"
        elif is_installed; then
            MAIN_STATUS="Installed"
            WEB_STATUS="Web UI: not available"
        else
            MAIN_STATUS="Not installed"
            WEB_STATUS="Web UI: not available"
        fi

        if is_boot_enabled; then
            BOOT_STATUS="Enabled"
        else
            BOOT_STATUS="Disabled"
        fi

        MENU_TEXT="Status: $MAIN_STATUS
Start on boot: $BOOT_STATUS
$WEB_STATUS

Choose an option:"

        CHOICE="$(dialog --clear --title "$TITLE" \
            --menu "$MENU_TEXT" 18 90 6 \
            1 "Install / Update" \
            2 "Start" \
            3 "Stop" \
            4 "Toggle Start on Boot" \
            0 "Exit" \
            3>&1 1>&2 2>&3)"

        [ $? -ne 0 ] && break

        case "$CHOICE" in
            1) install_syncthing ;;
            2) start_syncthing ;;
            3) stop_syncthing ;;
            4) toggle_boot ;;
            0) break ;;
        esac
    done

    clear
}

if ! has_cmd dialog; then
    echo "dialog was not found. This script requires dialog."
    exit 1
fi

main_menu