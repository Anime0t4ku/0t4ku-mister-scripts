#!/bin/sh

APP_NAME="ftp_save_sync"
APP_TITLE="ftp_save_sync by Anime0t4ku"
VERSION="0.3.0"

SCRIPT_PATH="/media/fat/Scripts/ftp_save_sync.sh"
BASE_DIR="/media/fat/Scripts/.config/$APP_NAME"
CONFIG_FILE="$BASE_DIR/ftp_save_sync.ini"
DAEMON_SCRIPT="$BASE_DIR/ftp_save_sync_daemon.sh"
LOG_FILE="$BASE_DIR/ftp_save_sync.log"
STATE_FILE="$BASE_DIR/ftp_save_sync_state.db"
PID_FILE="/tmp/ftp_save_sync.pid"
RCLONE_BIN="$BASE_DIR/rclone"
RCLONE_CONFIG_TMP="/tmp/ftp_save_sync_rclone.conf.$$"
DOWNLOAD_LOG="/tmp/ftp_save_sync_download.log.$$"
UNZIP_LOG="/tmp/ftp_save_sync_unzip.log.$$"
RCLONE_ZIP="/tmp/ftp_save_sync_rclone.zip.$$"
RCLONE_EXTRACT_DIR="/tmp/ftp_save_sync_rclone_extract.$$"
RCLONE_URL="https://downloads.rclone.org/rclone-current-linux-arm.zip"
STARTUP_FILE="/media/fat/linux/user-startup.sh"
TEST_ERROR_LOG="/tmp/ftp_save_sync_test_error.log.$$"
SYNC_ERROR_LOG="/tmp/ftp_save_sync_sync_error.log.$$"

DEFAULT_PROTOCOL="sftp"
DEFAULT_HOST=""
DEFAULT_PORT_SFTP="22"
DEFAULT_PORT_FTP="21"
DEFAULT_USERNAME=""
DEFAULT_PASSWORD=""
DEFAULT_REMOTE_BASE="/mister-sync"
DEFAULT_DEVICE_NAME="mister_1"
DEFAULT_SYNC_SAVES="true"
DEFAULT_SYNC_SAVESTATES="false"
DEFAULT_SYNC_INTERVAL="15"
DEFAULT_SKIP_HOST_KEY_CHECK="true"
DEFAULT_SKIP_TLS_VERIFY="false"
DEFAULT_MIN_AGE_SECONDS="5"

PROTOCOL="$DEFAULT_PROTOCOL"
HOST="$DEFAULT_HOST"
PORT="$DEFAULT_PORT_SFTP"
USERNAME="$DEFAULT_USERNAME"
PASSWORD="$DEFAULT_PASSWORD"
REMOTE_BASE="$DEFAULT_REMOTE_BASE"
DEVICE_NAME="$DEFAULT_DEVICE_NAME"
SYNC_SAVES="$DEFAULT_SYNC_SAVES"
SYNC_SAVESTATES="$DEFAULT_SYNC_SAVESTATES"
SYNC_INTERVAL="$DEFAULT_SYNC_INTERVAL"
SKIP_HOST_KEY_CHECK="$DEFAULT_SKIP_HOST_KEY_CHECK"
SKIP_TLS_VERIFY="$DEFAULT_SKIP_TLS_VERIFY"
MIN_AGE_SECONDS="$DEFAULT_MIN_AGE_SECONDS"

redraw_screen() {
    printf '\033[2J\033[H' >&2
}

show_msg() {
    dialog --title "$APP_NAME" --msgbox "$1" "${2:-8}" "${3:-60}"
    clear
}

show_error() {
    dialog --title "$APP_NAME" --msgbox "$1" "${2:-10}" "${3:-70}"
    clear
}

require_tools() {
    if ! command -v dialog >/dev/null 2>&1; then
        echo "dialog is not installed."
        exit 1
    fi

    for tool in sed awk grep find head tail tr mkdir rm cp chmod cat sleep kill mv stat sort date dirname touch; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            show_error "$tool is required but not available." 6 50
            exit 1
        fi
    done
}

ensure_base_dir() {
    mkdir -p "$BASE_DIR"
    [ -f "$LOG_FILE" ] || : > "$LOG_FILE"
    [ -f "$STATE_FILE" ] || : > "$STATE_FILE"
}

cleanup_temp_files() {
    rm -f "$RCLONE_CONFIG_TMP" "$DOWNLOAD_LOG" "$UNZIP_LOG" "$RCLONE_ZIP" "$TEST_ERROR_LOG" "$SYNC_ERROR_LOG"
    rm -rf "$RCLONE_EXTRACT_DIR"
}

trim() {
    echo "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

bool_is_true() {
    case "$1" in
        true|TRUE|1|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

set_default_port_for_protocol() {
    case "$1" in
        ftp) PORT="$DEFAULT_PORT_FTP" ;;
        *) PORT="$DEFAULT_PORT_SFTP" ;;
    esac
}

load_defaults() {
    PROTOCOL="$DEFAULT_PROTOCOL"
    HOST="$DEFAULT_HOST"
    PORT="$DEFAULT_PORT_SFTP"
    USERNAME="$DEFAULT_USERNAME"
    PASSWORD="$DEFAULT_PASSWORD"
    REMOTE_BASE="$DEFAULT_REMOTE_BASE"
    DEVICE_NAME="$DEFAULT_DEVICE_NAME"
    SYNC_SAVES="$DEFAULT_SYNC_SAVES"
    SYNC_SAVESTATES="$DEFAULT_SYNC_SAVESTATES"
    SYNC_INTERVAL="$DEFAULT_SYNC_INTERVAL"
    SKIP_HOST_KEY_CHECK="$DEFAULT_SKIP_HOST_KEY_CHECK"
    SKIP_TLS_VERIFY="$DEFAULT_SKIP_TLS_VERIFY"
    MIN_AGE_SECONDS="$DEFAULT_MIN_AGE_SECONDS"
}

load_config() {
    load_defaults
    [ -f "$CONFIG_FILE" ] || return 1

    PROTOCOL="$(trim "$(sed -n 's/^PROTOCOL=//p' "$CONFIG_FILE" | head -n1)")"
    HOST="$(trim "$(sed -n 's/^HOST=//p' "$CONFIG_FILE" | head -n1)")"
    PORT="$(trim "$(sed -n 's/^PORT=//p' "$CONFIG_FILE" | head -n1)")"
    USERNAME="$(trim "$(sed -n 's/^USERNAME=//p' "$CONFIG_FILE" | head -n1)")"
    PASSWORD="$(trim "$(sed -n 's/^PASSWORD=//p' "$CONFIG_FILE" | head -n1)")"
    REMOTE_BASE="$(trim "$(sed -n 's/^REMOTE_BASE=//p' "$CONFIG_FILE" | head -n1)")"
    DEVICE_NAME="$(trim "$(sed -n 's/^DEVICE_NAME=//p' "$CONFIG_FILE" | head -n1)")"
    SYNC_SAVES="$(trim "$(sed -n 's/^SYNC_SAVES=//p' "$CONFIG_FILE" | head -n1)")"
    SYNC_SAVESTATES="$(trim "$(sed -n 's/^SYNC_SAVESTATES=//p' "$CONFIG_FILE" | head -n1)")"
    SYNC_INTERVAL="$(trim "$(sed -n 's/^SYNC_INTERVAL=//p' "$CONFIG_FILE" | head -n1)")"
    SKIP_HOST_KEY_CHECK="$(trim "$(sed -n 's/^SKIP_HOST_KEY_CHECK=//p' "$CONFIG_FILE" | head -n1)")"
    SKIP_TLS_VERIFY="$(trim "$(sed -n 's/^SKIP_TLS_VERIFY=//p' "$CONFIG_FILE" | head -n1)")"
    MIN_AGE_SECONDS="$(trim "$(sed -n 's/^MIN_AGE_SECONDS=//p' "$CONFIG_FILE" | head -n1)")"

    [ -z "$PROTOCOL" ] && PROTOCOL="$DEFAULT_PROTOCOL"
    [ -z "$PORT" ] && set_default_port_for_protocol "$PROTOCOL"
    [ -z "$REMOTE_BASE" ] && REMOTE_BASE="$DEFAULT_REMOTE_BASE"
    [ -z "$DEVICE_NAME" ] && DEVICE_NAME="$DEFAULT_DEVICE_NAME"
    [ -z "$SYNC_SAVES" ] && SYNC_SAVES="$DEFAULT_SYNC_SAVES"
    [ -z "$SYNC_SAVESTATES" ] && SYNC_SAVESTATES="$DEFAULT_SYNC_SAVESTATES"
    [ -z "$SYNC_INTERVAL" ] && SYNC_INTERVAL="$DEFAULT_SYNC_INTERVAL"
    [ -z "$SKIP_HOST_KEY_CHECK" ] && SKIP_HOST_KEY_CHECK="$DEFAULT_SKIP_HOST_KEY_CHECK"
    [ -z "$SKIP_TLS_VERIFY" ] && SKIP_TLS_VERIFY="$DEFAULT_SKIP_TLS_VERIFY"
    [ -z "$MIN_AGE_SECONDS" ] && MIN_AGE_SECONDS="$DEFAULT_MIN_AGE_SECONDS"

    return 0
}

save_config() {
    ensure_base_dir
    cat > "$CONFIG_FILE" <<EOF
PROTOCOL=$PROTOCOL
HOST=$HOST
PORT=$PORT
USERNAME=$USERNAME
PASSWORD=$PASSWORD
REMOTE_BASE=$REMOTE_BASE
DEVICE_NAME=$DEVICE_NAME
SYNC_SAVES=$SYNC_SAVES
SYNC_SAVESTATES=$SYNC_SAVESTATES
SYNC_INTERVAL=$SYNC_INTERVAL
SKIP_HOST_KEY_CHECK=$SKIP_HOST_KEY_CHECK
SKIP_TLS_VERIFY=$SKIP_TLS_VERIFY
PAUSE_WHILE_CORE_RUNNING=true
MIN_AGE_SECONDS=$MIN_AGE_SECONDS
EOF
}

config_is_valid() {
    load_config >/dev/null 2>&1 || return 1
    [ -n "$PROTOCOL" ] || return 1
    [ -n "$HOST" ] || return 1
    [ -n "$PORT" ] || return 1
    [ -n "$USERNAME" ] || return 1
    [ -n "$PASSWORD" ] || return 1
    [ -n "$REMOTE_BASE" ] || return 1
    return 0
}

prompt_input() {
    title="$1"
    message="$2"
    initial="$3"

    result=$(dialog --clear \
        --title "$title" \
        --inputbox "$message" 11 70 "$initial" \
        3>&1 1>&2 2>&3)
    status=$?
    redraw_screen

    [ $status -ne 0 ] && return 1
    printf '%s' "$result"
    return 0
}

prompt_yes_no_value() {
    title="$1"
    message="$2"
    current="$3"
    default_choice="2"

    if bool_is_true "$current"; then
        default_choice="1"
    fi

    choice=$(dialog --clear \
        --title "$title" \
        --default-item "$default_choice" \
        --menu "$message" 13 70 4 \
        1 "Yes" \
        2 "No" \
        3>&1 1>&2 2>&3)
    status=$?
    redraw_screen

    [ $status -ne 0 ] && return 1

    case "$choice" in
        1) printf '%s' "true" ;;
        2) printf '%s' "false" ;;
        *) return 1 ;;
    esac
}

prompt_protocol() {
    current="$1"
    default_choice="1"

    case "$current" in
        ftp) default_choice="2" ;;
        *) default_choice="1" ;;
    esac

    choice=$(dialog --clear \
        --title "$APP_NAME" \
        --default-item "$default_choice" \
        --menu "Choose connection type" 12 60 4 \
        1 "SFTP (recommended)" \
        2 "FTP" \
        3>&1 1>&2 2>&3)
    status=$?
    redraw_screen

    [ $status -ne 0 ] && return 1

    case "$choice" in
        1) printf '%s' "sftp" ;;
        2) printf '%s' "ftp" ;;
        *) return 1 ;;
    esac
}

show_keyboard_notice() {
    dialog --title "$APP_NAME" \
        --yesno "Creating or editing the INI file requires a keyboard.

If you do not have a keyboard attached, create the INI file manually or use the MiSTer Companion app.

Continue?" 11 72
}

validate_number() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

normalize_remote_base() {
    case "$REMOTE_BASE" in
        "") REMOTE_BASE="$DEFAULT_REMOTE_BASE" ;;
        /*) ;;
        *) REMOTE_BASE="/$REMOTE_BASE" ;;
    esac
    REMOTE_BASE="$(echo "$REMOTE_BASE" | sed 's#//*#/#g; s#/$##')"
    [ -z "$REMOTE_BASE" ] && REMOTE_BASE="$DEFAULT_REMOTE_BASE"
}

edit_config() {
    ensure_base_dir
    load_config >/dev/null 2>&1

    show_keyboard_notice
    [ $? -ne 0 ] && return 1
    redraw_screen

    old_protocol="$PROTOCOL"
    value="$(prompt_protocol "$PROTOCOL")" || return 1
    PROTOCOL="$value"

    if [ "$PROTOCOL" != "$old_protocol" ] || [ -z "$PORT" ]; then
        set_default_port_for_protocol "$PROTOCOL"
    fi

    value="$(prompt_input "$APP_NAME" "Enter server host or IP" "$HOST")" || return 1
    HOST="$(trim "$value")"

    value="$(prompt_input "$APP_NAME" "Enter port" "$PORT")" || return 1
    PORT="$(trim "$value")"

    value="$(prompt_input "$APP_NAME" "Enter username" "$USERNAME")" || return 1
    USERNAME="$(trim "$value")"

    value="$(prompt_input "$APP_NAME" "Enter password" "$PASSWORD")" || return 1
    PASSWORD="$value"

    value="$(prompt_input "$APP_NAME" "Enter remote base path

Example:
/mister-sync" "$REMOTE_BASE")" || return 1
    REMOTE_BASE="$(trim "$value")"
    normalize_remote_base

    value="$(prompt_input "$APP_NAME" "Enter device name

Example:
livingroom_mister" "$DEVICE_NAME")" || return 1
    DEVICE_NAME="$(trim "$value")"

    value="$(prompt_yes_no_value "$APP_NAME" "Sync normal save files?" "$SYNC_SAVES")" || return 1
    SYNC_SAVES="$value"

    value="$(prompt_yes_no_value "$APP_NAME" "Sync savestates too?

Warning: savestates can be less portable than save files." "$SYNC_SAVESTATES")" || return 1
    SYNC_SAVESTATES="$value"

    value="$(prompt_input "$APP_NAME" "Enter sync interval in seconds

Recommended: 15" "$SYNC_INTERVAL")" || return 1
    SYNC_INTERVAL="$(trim "$value")"

    value="$(prompt_input "$APP_NAME" "Enter minimum file age before sync in seconds

Recommended: 5" "$MIN_AGE_SECONDS")" || return 1
    MIN_AGE_SECONDS="$(trim "$value")"

    case "$PROTOCOL" in
        sftp)
            value="$(prompt_yes_no_value "$APP_NAME" "Skip SFTP host key verification?

Recommended only for simple/local setups." "$SKIP_HOST_KEY_CHECK")" || return 1
            SKIP_HOST_KEY_CHECK="$value"
            ;;
        ftp)
            value="$(prompt_yes_no_value "$APP_NAME" "Skip FTP TLS/certificate verification if needed?" "$SKIP_TLS_VERIFY")" || return 1
            SKIP_TLS_VERIFY="$value"
            ;;
    esac

    if [ -z "$HOST" ] || [ -z "$PORT" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$REMOTE_BASE" ]; then
        show_error "Host, port, username, password, and remote base are required." 8 65
        return 1
    fi

    if ! validate_number "$PORT"; then
        show_error "Port must be a number." 6 40
        return 1
    fi

    if ! validate_number "$SYNC_INTERVAL"; then
        show_error "Sync interval must be a number." 6 46
        return 1
    fi

    if ! validate_number "$MIN_AGE_SECONDS"; then
        show_error "Minimum file age must be a number." 6 52
        return 1
    fi

    if [ "$SYNC_SAVES" != "true" ] && [ "$SYNC_SAVESTATES" != "true" ]; then
        show_error "Enable at least one sync target, saves or savestates." 7 58
        return 1
    fi

    save_config
    install_daemon_script
    show_msg "Configuration saved successfully." 6 45
    return 0
}

install_daemon_script() {
    ensure_base_dir

    cat > "$DAEMON_SCRIPT" <<'EOF'
#!/bin/sh

APP_NAME="ftp_save_sync"
BASE_DIR="/media/fat/Scripts/.config/$APP_NAME"
CONFIG_FILE="$BASE_DIR/ftp_save_sync.ini"
LOG_FILE="$BASE_DIR/ftp_save_sync.log"
STATE_FILE="$BASE_DIR/ftp_save_sync_state.db"
PID_FILE="/tmp/ftp_save_sync.pid"
RCLONE_BIN="$BASE_DIR/rclone"
RCLONE_CONFIG_TMP="/tmp/ftp_save_sync_rclone.conf.$$"
CORENAME_FILE="/tmp/CORENAME"
SYNC_ERROR_LOG="/tmp/ftp_save_sync_sync_error.log.$$"

PROTOCOL="sftp"
HOST=""
PORT="22"
USERNAME=""
PASSWORD=""
REMOTE_BASE="/mister-sync"
DEVICE_NAME="mister_1"
SYNC_SAVES="true"
SYNC_SAVESTATES="false"
SYNC_INTERVAL="15"
SKIP_HOST_KEY_CHECK="true"
SKIP_TLS_VERIFY="false"
MIN_AGE_SECONDS="5"
CURRENT_CORE_NAME=""
LAST_RUN_STATE=""

trim() {
    echo "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

bool_is_true() {
    case "$1" in
        true|TRUE|1|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

log() {
    mkdir -p "$BASE_DIR"
    [ -f "$LOG_FILE" ] || : > "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

file_mtime() {
    stat -c %Y "$1" 2>/dev/null
}

file_age_is_old_enough() {
    f="$1"
    mtime="$(file_mtime "$f")"
    [ -n "$mtime" ] || return 1
    now="$(date +%s)"
    age=$((now - mtime))
    [ "$age" -ge "$MIN_AGE_SECONDS" ]
}

load_config() {
    [ -f "$CONFIG_FILE" ] || return 1

    PROTOCOL="$(trim "$(sed -n 's/^PROTOCOL=//p' "$CONFIG_FILE" | head -n1)")"
    HOST="$(trim "$(sed -n 's/^HOST=//p' "$CONFIG_FILE" | head -n1)")"
    PORT="$(trim "$(sed -n 's/^PORT=//p' "$CONFIG_FILE" | head -n1)")"
    USERNAME="$(trim "$(sed -n 's/^USERNAME=//p' "$CONFIG_FILE" | head -n1)")"
    PASSWORD="$(trim "$(sed -n 's/^PASSWORD=//p' "$CONFIG_FILE" | head -n1)")"
    REMOTE_BASE="$(trim "$(sed -n 's/^REMOTE_BASE=//p' "$CONFIG_FILE" | head -n1)")"
    DEVICE_NAME="$(trim "$(sed -n 's/^DEVICE_NAME=//p' "$CONFIG_FILE" | head -n1)")"
    SYNC_SAVES="$(trim "$(sed -n 's/^SYNC_SAVES=//p' "$CONFIG_FILE" | head -n1)")"
    SYNC_SAVESTATES="$(trim "$(sed -n 's/^SYNC_SAVESTATES=//p' "$CONFIG_FILE" | head -n1)")"
    SYNC_INTERVAL="$(trim "$(sed -n 's/^SYNC_INTERVAL=//p' "$CONFIG_FILE" | head -n1)")"
    SKIP_HOST_KEY_CHECK="$(trim "$(sed -n 's/^SKIP_HOST_KEY_CHECK=//p' "$CONFIG_FILE" | head -n1)")"
    SKIP_TLS_VERIFY="$(trim "$(sed -n 's/^SKIP_TLS_VERIFY=//p' "$CONFIG_FILE" | head -n1)")"
    MIN_AGE_SECONDS="$(trim "$(sed -n 's/^MIN_AGE_SECONDS=//p' "$CONFIG_FILE" | head -n1)")"

    [ -z "$PROTOCOL" ] && PROTOCOL="sftp"
    [ -z "$PORT" ] && PORT="22"
    [ -z "$REMOTE_BASE" ] && REMOTE_BASE="/mister-sync"
    [ -z "$DEVICE_NAME" ] && DEVICE_NAME="mister_1"
    [ -z "$SYNC_SAVES" ] && SYNC_SAVES="true"
    [ -z "$SYNC_SAVESTATES" ] && SYNC_SAVESTATES="false"
    [ -z "$SYNC_INTERVAL" ] && SYNC_INTERVAL="15"
    [ -z "$SKIP_HOST_KEY_CHECK" ] && SKIP_HOST_KEY_CHECK="true"
    [ -z "$SKIP_TLS_VERIFY" ] && SKIP_TLS_VERIFY="false"
    [ -z "$MIN_AGE_SECONDS" ] && MIN_AGE_SECONDS="5"

    return 0
}

cleanup() {
    if [ -f "$PID_FILE" ]; then
        run_pid="$(cat "$PID_FILE" 2>/dev/null)"
        if [ "$run_pid" = "$$" ]; then
            rm -f "$PID_FILE"
        fi
    fi
    rm -f "$SYNC_ERROR_LOG" "$RCLONE_CONFIG_TMP"
}

cleanup_and_exit() {
    cleanup
    exit 0
}

build_rclone_config() {
    obscured_pass="$($RCLONE_BIN obscure "$PASSWORD" 2>/dev/null)"
    [ -n "$obscured_pass" ] || return 1

    {
        echo "[remote]"
        echo "type = $PROTOCOL"
        echo "host = $HOST"
        echo "user = $USERNAME"
        echo "pass = $obscured_pass"
        echo "port = $PORT"

        case "$PROTOCOL" in
            sftp)
                echo "shell_type = unix"
                if bool_is_true "$SKIP_HOST_KEY_CHECK"; then
                    echo "skip_host_key_check = true"
                fi
                ;;
            ftp)
                echo "disable_mlsd = true"
                if bool_is_true "$SKIP_TLS_VERIFY"; then
                    echo "no_check_certificate = true"
                fi
                ;;
        esac
    } > "$RCLONE_CONFIG_TMP"

    return 0
}

test_connection() {
    "$RCLONE_BIN" --config "$RCLONE_CONFIG_TMP" lsf "remote:$REMOTE_BASE" >/dev/null 2>&1
}

is_sync_allowed() {
    CURRENT_CORE_NAME=""

    if [ ! -f "$CORENAME_FILE" ]; then
        return 0
    fi

    CURRENT_CORE_NAME="$(tr -d '\r\n' < "$CORENAME_FILE" 2>/dev/null)"

    case "$CURRENT_CORE_NAME" in
        ""|MENU)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

manifest_get_mtime() {
    manifest_file="$1"
    rel_path="$2"
    awk -F'|' -v p="$rel_path" '$1==p {print $2; exit}' "$manifest_file" 2>/dev/null
}

manifest_upsert() {
    manifest_file="$1"
    rel_path="$2"
    mtime="$3"
    device="$4"
    tmp_file="${manifest_file}.tmp.$$"

    [ -f "$manifest_file" ] || : > "$manifest_file"

    awk -F'|' -v p="$rel_path" -v m="$mtime" -v d="$device" '
        BEGIN { found=0 }
        $1==p { print p "|" m "|" d; found=1; next }
        { print }
        END { if (!found) print p "|" m "|" d }
    ' "$manifest_file" > "$tmp_file" && mv "$tmp_file" "$manifest_file"
}

build_local_manifest() {
    local_dir="$1"
    out_file="$2"

    : > "$out_file"

    [ -d "$local_dir" ] || return 0

    find "$local_dir" -type f | while IFS= read -r file_path; do
        rel_path="${file_path#$local_dir/}"
        mtime="$(file_mtime "$file_path")"
        [ -n "$mtime" ] || continue
        printf '%s|%s|%s\n' "$rel_path" "$mtime" "$DEVICE_NAME"
    done | sort > "$out_file"
}

download_remote_manifest() {
    remote_manifest_path="$1"
    local_manifest_path="$2"

    : > "$local_manifest_path"

    "$RCLONE_BIN" --config "$RCLONE_CONFIG_TMP" copyto \
        "remote:$remote_manifest_path" "$local_manifest_path" >/dev/null 2>"$SYNC_ERROR_LOG"

    if [ $? -ne 0 ]; then
        : > "$local_manifest_path"
    fi
}

upload_manifest() {
    local_manifest_path="$1"
    remote_manifest_path="$2"

    "$RCLONE_BIN" --config "$RCLONE_CONFIG_TMP" copyto \
        "$local_manifest_path" "remote:$remote_manifest_path" >/dev/null 2>"$SYNC_ERROR_LOG"
}

sync_folder_sftp() {
    local_dir="$1"
    remote_sub="$2"
    remote_path="remote:${REMOTE_BASE}/${remote_sub}"

    [ -d "$local_dir" ] || return 0

    : > "$SYNC_ERROR_LOG"

    "$RCLONE_BIN" --config "$RCLONE_CONFIG_TMP" copy \
        "$local_dir" "$remote_path" \
        --update \
        --create-empty-src-dirs \
        --min-age "${MIN_AGE_SECONDS}s" \
        --log-file "$LOG_FILE" \
        --log-level NOTICE >/dev/null 2>"$SYNC_ERROR_LOG"

    if [ $? -ne 0 ]; then
        err_msg="$(tail -n 5 "$SYNC_ERROR_LOG" 2>/dev/null)"
        [ -z "$err_msg" ] && err_msg="Unknown upload error"
        log "Upload sync warning for $remote_sub: $err_msg"
    fi

    : > "$SYNC_ERROR_LOG"

    "$RCLONE_BIN" --config "$RCLONE_CONFIG_TMP" copy \
        "$remote_path" "$local_dir" \
        --update \
        --create-empty-src-dirs \
        --min-age "${MIN_AGE_SECONDS}s" \
        --log-file "$LOG_FILE" \
        --log-level NOTICE >/dev/null 2>"$SYNC_ERROR_LOG"

    if [ $? -ne 0 ]; then
        err_msg="$(tail -n 5 "$SYNC_ERROR_LOG" 2>/dev/null)"
        [ -z "$err_msg" ] && err_msg="Unknown download error"
        log "Download sync warning for $remote_sub: $err_msg"
    fi
}

sync_folder_ftp_manifest() {
    local_dir="$1"
    remote_sub="$2"
    remote_base_path="${REMOTE_BASE}/${remote_sub}"
    remote_manifest_path="${remote_base_path}/.ftp_save_sync_manifest.tsv"
    safe_name="$(echo "$remote_sub" | tr '/ ' '__')"
    remote_manifest_tmp="/tmp/ftp_save_sync_${safe_name}_remote_manifest.tsv.$$"
    local_manifest_tmp="/tmp/ftp_save_sync_${safe_name}_local_manifest.tsv.$$"
    final_manifest_tmp="/tmp/ftp_save_sync_${safe_name}_final_manifest.tsv.$$"

    [ -d "$local_dir" ] || return 0

    download_remote_manifest "$remote_manifest_path" "$remote_manifest_tmp"
    build_local_manifest "$local_dir" "$local_manifest_tmp"

    while IFS='|' read -r rel_path local_mtime local_device; do
        [ -n "$rel_path" ] || continue

        local_file="${local_dir}/${rel_path}"
        [ -f "$local_file" ] || continue
        file_age_is_old_enough "$local_file" || continue

        remote_mtime="$(manifest_get_mtime "$remote_manifest_tmp" "$rel_path")"

        if [ -z "$remote_mtime" ] || [ "$local_mtime" -gt "$remote_mtime" ]; then
            : > "$SYNC_ERROR_LOG"
            "$RCLONE_BIN" --config "$RCLONE_CONFIG_TMP" copyto \
                "$local_file" "remote:${remote_base_path}/${rel_path}" >/dev/null 2>"$SYNC_ERROR_LOG"

            if [ $? -eq 0 ]; then
                manifest_upsert "$remote_manifest_tmp" "$rel_path" "$local_mtime" "$DEVICE_NAME"
            else
                err_msg="$(tail -n 5 "$SYNC_ERROR_LOG" 2>/dev/null)"
                [ -z "$err_msg" ] && err_msg="Unknown upload error"
                log "Upload sync warning for $remote_sub/$rel_path: $err_msg"
            fi
        fi
    done < "$local_manifest_tmp"

    while IFS='|' read -r rel_path remote_mtime remote_device; do
        [ -n "$rel_path" ] || continue

        local_file="${local_dir}/${rel_path}"
        local_mtime=""
        if [ -f "$local_file" ]; then
            local_mtime="$(file_mtime "$local_file")"
        fi

        if [ ! -f "$local_file" ] || [ "$remote_mtime" -gt "$local_mtime" ]; then
            mkdir -p "$(dirname "$local_file")"
            : > "$SYNC_ERROR_LOG"

            "$RCLONE_BIN" --config "$RCLONE_CONFIG_TMP" copyto \
                "remote:${remote_base_path}/${rel_path}" "$local_file" >/dev/null 2>"$SYNC_ERROR_LOG"

            if [ $? -ne 0 ]; then
                err_msg="$(tail -n 5 "$SYNC_ERROR_LOG" 2>/dev/null)"
                [ -z "$err_msg" ] && err_msg="Unknown download error"
                log "Download sync warning for $remote_sub/$rel_path: $err_msg"
            fi
        fi
    done < "$remote_manifest_tmp"

    build_local_manifest "$local_dir" "$final_manifest_tmp"
    : > "$SYNC_ERROR_LOG"
    upload_manifest "$final_manifest_tmp" "$remote_manifest_path"

    if [ $? -ne 0 ]; then
        err_msg="$(tail -n 5 "$SYNC_ERROR_LOG" 2>/dev/null)"
        [ -z "$err_msg" ] && err_msg="Unknown manifest upload error"
        log "Manifest sync warning for $remote_sub: $err_msg"
    fi

    rm -f "$remote_manifest_tmp" "$local_manifest_tmp" "$final_manifest_tmp"
}

sync_folder() {
    local_dir="$1"
    remote_sub="$2"

    if [ "$PROTOCOL" = "ftp" ]; then
        sync_folder_ftp_manifest "$local_dir" "$remote_sub"
    else
        sync_folder_sftp "$local_dir" "$remote_sub"
    fi
}

run_sync_pass() {
    if ! load_config; then
        log "Config missing during sync pass."
        return 1
    fi

    if ! build_rclone_config; then
        log "Failed to rebuild rclone config for sync pass."
        return 1
    fi

    if bool_is_true "$SYNC_SAVES"; then
        sync_folder "/media/fat/saves" "saves"
    fi

    if bool_is_true "$SYNC_SAVESTATES"; then
        sync_folder "/media/fat/savestates" "savestates"
    fi
}

main() {
    one_shot="false"
    if [ "$1" = "--sync-once" ]; then
        one_shot="true"
    fi

    mkdir -p "$BASE_DIR"
    [ -f "$LOG_FILE" ] || : > "$LOG_FILE"
    [ -f "$STATE_FILE" ] || : > "$STATE_FILE"

    if [ "$one_shot" != "true" ]; then
        if [ -f "$PID_FILE" ]; then
            old_pid="$(cat "$PID_FILE" 2>/dev/null)"
            if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
                exit 0
            fi
            rm -f "$PID_FILE"
        fi

        echo $$ > "$PID_FILE"
    fi

    trap 'cleanup_and_exit' INT TERM EXIT

    if ! load_config; then
        log "Config missing, daemon exiting."
        exit 1
    fi

    if [ ! -x "$RCLONE_BIN" ]; then
        log "rclone missing, daemon exiting."
        exit 1
    fi

    if ! "$RCLONE_BIN" version >/dev/null 2>&1; then
        log "rclone exists but is not executable on this MiSTer, daemon exiting."
        exit 1
    fi

    if ! build_rclone_config; then
        log "Failed to build rclone config, daemon exiting."
        exit 1
    fi

    if ! test_connection; then
        log "Initial connection test failed, daemon will keep retrying."
    fi

    if [ "$one_shot" = "true" ]; then
        if test_connection && is_sync_allowed; then
            run_sync_pass
        else
            log "Manual sync skipped, connection unavailable or sync not allowed."
        fi
        rm -f "$RCLONE_CONFIG_TMP" "$SYNC_ERROR_LOG"
        exit 0
    fi

    log "Service started for device: $DEVICE_NAME"

    while true; do
        if is_sync_allowed; then
            if test_connection; then
                if [ "$LAST_RUN_STATE" != "allowed" ]; then
                    log "Sync resumed."
                    LAST_RUN_STATE="allowed"
                fi
                run_sync_pass
            else
                if [ "$LAST_RUN_STATE" != "waiting_for_connection" ]; then
                    log "Connection unavailable, waiting to retry."
                    LAST_RUN_STATE="waiting_for_connection"
                fi
            fi
        else
            if [ "$LAST_RUN_STATE" != "paused:$CURRENT_CORE_NAME" ]; then
                log "Sync paused, active core detected: $CURRENT_CORE_NAME"
                LAST_RUN_STATE="paused:$CURRENT_CORE_NAME"
            fi
        fi

        sleep "$SYNC_INTERVAL"
    done
}

main "$@"
EOF

    chmod +x "$DAEMON_SCRIPT"
}

install_rclone() {
    ensure_base_dir
    cleanup_temp_files

    dialog --title "$APP_NAME" --yesno "rclone is required.

Download and install it now?" 8 55
    [ $? -ne 0 ] && return 1
    redraw_screen

    mkdir -p "$RCLONE_EXTRACT_DIR"

    dialog --title "$APP_NAME" --infobox "Downloading rclone..." 5 40
    sleep 1

    download_ok=0

    if command -v curl >/dev/null 2>&1; then
        curl -L --fail "$RCLONE_URL" -o "$RCLONE_ZIP" >"$DOWNLOAD_LOG" 2>&1 && download_ok=1
        if [ $download_ok -ne 1 ]; then
            curl -k -L --fail "$RCLONE_URL" -o "$RCLONE_ZIP" >"$DOWNLOAD_LOG" 2>&1 && download_ok=1
        fi
    fi

    if [ $download_ok -ne 1 ] && command -v wget >/dev/null 2>&1; then
        wget -O "$RCLONE_ZIP" "$RCLONE_URL" >"$DOWNLOAD_LOG" 2>&1 && download_ok=1
        if [ $download_ok -ne 1 ]; then
            wget --no-check-certificate -O "$RCLONE_ZIP" "$RCLONE_URL" >"$DOWNLOAD_LOG" 2>&1 && download_ok=1
        fi
    fi

    if [ $download_ok -ne 1 ] || [ ! -s "$RCLONE_ZIP" ]; then
        err_msg="$(tail -n 8 "$DOWNLOAD_LOG" 2>/dev/null)"
        [ -z "$err_msg" ] && err_msg="Unknown download error."
        cleanup_temp_files
        show_error "Failed to download rclone.

$err_msg" 14 72
        return 1
    fi

    dialog --title "$APP_NAME" --infobox "Extracting rclone..." 5 40
    sleep 1

    if command -v unzip >/dev/null 2>&1; then
        unzip -o "$RCLONE_ZIP" -d "$RCLONE_EXTRACT_DIR" >"$UNZIP_LOG" 2>&1
    elif command -v busybox >/dev/null 2>&1; then
        busybox unzip -o "$RCLONE_ZIP" -d "$RCLONE_EXTRACT_DIR" >"$UNZIP_LOG" 2>&1
    else
        cleanup_temp_files
        show_error "No unzip tool found on this MiSTer." 6 45
        return 1
    fi

    bin_path="$(find "$RCLONE_EXTRACT_DIR" -type f -name rclone 2>/dev/null | head -n1)"

    if [ -z "$bin_path" ] || [ ! -f "$bin_path" ]; then
        err_msg="$(tail -n 8 "$UNZIP_LOG" 2>/dev/null)"
        [ -z "$err_msg" ] && err_msg="Unknown extraction error."
        cleanup_temp_files
        show_error "Failed to extract rclone.

$err_msg" 14 72
        return 1
    fi

    cp "$bin_path" "$RCLONE_BIN" 2>/dev/null
    chmod +x "$RCLONE_BIN" 2>/dev/null

    if [ ! -x "$RCLONE_BIN" ]; then
        cleanup_temp_files
        show_error "rclone was extracted but could not be installed." 7 55
        return 1
    fi

    if ! "$RCLONE_BIN" version >/dev/null 2>&1; then
        rm -f "$RCLONE_BIN"
        cleanup_temp_files
        show_error "rclone was installed, but MiSTer could not execute it.

The downloaded rclone build may be incompatible or corrupted." 9 68
        return 1
    fi

    cleanup_temp_files
    install_daemon_script
    show_msg "rclone installed successfully." 6 45
    return 0
}

build_temp_rclone_config() {
    load_config >/dev/null 2>&1 || return 1
    [ -x "$RCLONE_BIN" ] || return 1

    obscured_pass="$($RCLONE_BIN obscure "$PASSWORD" 2>/dev/null)"
    [ -n "$obscured_pass" ] || return 1

    {
        echo "[remote]"
        echo "type = $PROTOCOL"
        echo "host = $HOST"
        echo "user = $USERNAME"
        echo "pass = $obscured_pass"
        echo "port = $PORT"

        case "$PROTOCOL" in
            sftp)
                echo "shell_type = unix"
                if bool_is_true "$SKIP_HOST_KEY_CHECK"; then
                    echo "skip_host_key_check = true"
                fi
                ;;
            ftp)
                echo "disable_mlsd = true"
                if bool_is_true "$SKIP_TLS_VERIFY"; then
                    echo "no_check_certificate = true"
                fi
                ;;
        esac
    } > "$RCLONE_CONFIG_TMP"

    return 0
}

test_connection() {
    if ! config_is_valid; then
        show_error "Please configure ftp_save_sync first." 6 45
        return 1
    fi

    if [ ! -x "$RCLONE_BIN" ]; then
        show_error "rclone is not installed yet." 6 40
        return 1
    fi

    rm -f "$RCLONE_CONFIG_TMP" "$TEST_ERROR_LOG"

    if ! build_temp_rclone_config; then
        show_error "Failed to build rclone configuration." 6 50
        return 1
    fi

    dialog --title "$APP_NAME" --infobox "Testing connection..." 5 40
    sleep 1

    if "$RCLONE_BIN" --config "$RCLONE_CONFIG_TMP" lsf "remote:$REMOTE_BASE" >/dev/null 2>"$TEST_ERROR_LOG"; then
        rm -f "$RCLONE_CONFIG_TMP" "$TEST_ERROR_LOG"
        show_msg "Connection successful." 6 35
        return 0
    fi

    err_msg="$(tail -n 8 "$TEST_ERROR_LOG" 2>/dev/null)"
    [ -z "$err_msg" ] && err_msg="Unknown connection error."
    rm -f "$RCLONE_CONFIG_TMP" "$TEST_ERROR_LOG"
    show_error "Connection failed.

$err_msg" 14 72
    return 1
}

service_running() {
    [ -f "$PID_FILE" ] || return 1
    run_pid="$(cat "$PID_FILE" 2>/dev/null)"
    [ -n "$run_pid" ] || return 1
    kill -0 "$run_pid" 2>/dev/null
}

start_service() {
    install_daemon_script

    if ! config_is_valid; then
        show_error "Please configure ftp_save_sync first." 6 45
        return 1
    fi

    if [ ! -x "$RCLONE_BIN" ]; then
        show_error "Please install rclone first." 6 40
        return 1
    fi

    if service_running; then
        show_msg "Service is already running." 6 40
        return 0
    fi

    "$DAEMON_SCRIPT" >/dev/null 2>&1 &
    sleep 1

    if service_running; then
        show_msg "Service started successfully." 6 42
    else
        show_error "Service failed to start. Check the log for details." 7 58
    fi
}

stop_service() {
    if ! service_running; then
        rm -f "$PID_FILE"
        show_msg "Service is not running." 6 40
        return 0
    fi

    run_pid="$(cat "$PID_FILE" 2>/dev/null)"
    kill "$run_pid" 2>/dev/null
    sleep 1

    if kill -0 "$run_pid" 2>/dev/null; then
        kill -TERM "$run_pid" 2>/dev/null
        sleep 2
    fi

    if kill -0 "$run_pid" 2>/dev/null; then
        kill -KILL "$run_pid" 2>/dev/null
        sleep 1
    fi

    rm -f "$PID_FILE"

    if kill -0 "$run_pid" 2>/dev/null; then
        show_error "Service could not be stopped completely." 6 48
        return 1
    fi

    show_msg "Service stopped." 6 35
}

sync_now() {
    if ! config_is_valid; then
        show_error "Please configure ftp_save_sync first." 6 45
        return 1
    fi

    if [ ! -x "$RCLONE_BIN" ]; then
        show_error "Please install rclone first." 6 40
        return 1
    fi

    install_daemon_script
    "$DAEMON_SCRIPT" --sync-once >/dev/null 2>&1
    show_msg "Manual sync finished. Check the log for details." 7 52
}

enable_autostart() {
    mkdir -p "/media/fat/linux"

    if [ ! -f "$STARTUP_FILE" ]; then
        echo "#!/bin/sh" > "$STARTUP_FILE"
        chmod +x "$STARTUP_FILE"
    fi

    if grep -Fq "# ftp_save_sync START" "$STARTUP_FILE"; then
        show_msg "Autostart is already enabled." 6 40
        return 0
    fi

    install_daemon_script

    {
        echo ""
        echo "# ftp_save_sync START"
        echo "("
        echo "    sleep 15"
        echo "    $DAEMON_SCRIPT >/dev/null 2>&1"
        echo ") &"
        echo "# ftp_save_sync END"
    } >> "$STARTUP_FILE"

    show_msg "Autostart enabled successfully." 6 45
}

disable_autostart() {
    if [ ! -f "$STARTUP_FILE" ]; then
        show_msg "No startup file found." 6 40
        return 0
    fi

    tmpfile="${STARTUP_FILE}.tmp.$$"
    awk '
        BEGIN { skip=0 }
        /^# ftp_save_sync START$/ { skip=1; next }
        /^# ftp_save_sync END$/ { skip=0; next }
        skip==0 { print }
    ' "$STARTUP_FILE" > "$tmpfile" && mv "$tmpfile" "$STARTUP_FILE"

    chmod +x "$STARTUP_FILE" 2>/dev/null
    show_msg "Autostart disabled." 6 38
}

view_log() {
    ensure_base_dir
    [ -f "$LOG_FILE" ] || : > "$LOG_FILE"
    dialog --title "$APP_NAME Log" --textbox "$LOG_FILE" 22 76
    redraw_screen
}

uninstall_script() {
    dialog --clear \
        --title "$APP_NAME" \
        --yesno "Uninstall ftp_save_sync?

This will stop the service, disable autostart, and remove the config folder.

The main script in /media/fat/Scripts will be left in place." 11 72
    status=$?
    redraw_screen

    [ $status -ne 0 ] && return 1

    if service_running; then
        run_pid="$(cat "$PID_FILE" 2>/dev/null)"
        kill "$run_pid" 2>/dev/null
        sleep 1
    fi

    rm -f "$PID_FILE"
    disable_autostart >/dev/null 2>&1
    rm -rf "$BASE_DIR"
    cleanup_temp_files

    show_msg "ftp_save_sync data removed.

You can delete /media/fat/Scripts/ftp_save_sync.sh manually if you no longer need it." 9 68
}

show_ini_help() {
    if [ -f "$CONFIG_FILE" ]; then
        show_msg "A configuration file was found.

Editing it from this script requires a keyboard.
If you do not have a keyboard attached, you can edit it manually or use the MiSTer Companion app." 10 72
    else
        show_msg "No configuration file was found yet.

Creating it from this script requires a keyboard.
If you do not have a keyboard attached, you can create it manually or use the MiSTer Companion app." 10 72
    fi
}

show_main_menu() {
    while true; do
        if service_running; then
            service_label="Stop Service"
            service_status="Running"
        else
            service_label="Start Service"
            service_status="Not running"
        fi

        if [ -f "$CONFIG_FILE" ]; then
            config_label="Edit Configuration"
            config_status="Present"
        else
            config_label="Create Configuration"
            config_status="Missing"
        fi

        if [ -f "$STARTUP_FILE" ] && grep -Fq "# ftp_save_sync START" "$STARTUP_FILE"; then
            autostart_label="Disable Autostart"
            autostart_status="Enabled"
        else
            autostart_label="Enable Autostart"
            autostart_status="Disabled"
        fi

        choice=$(dialog --clear \
            --title "$APP_TITLE" \
            --menu "Service: $service_status
Configuration: $config_status
Autostart: $autostart_status" 18 72 10 \
            1 "$service_label" \
            2 "$config_label" \
            3 "Test Connection" \
            4 "Sync Now" \
            5 "$autostart_label" \
            6 "View Log" \
            7 "Uninstall" \
            8 "Exit" \
            3>&1 1>&2 2>&3)
        status=$?
        redraw_screen

        [ $status -ne 0 ] && exit 0

        case "$choice" in
            1)
                if service_running; then
                    stop_service
                else
                    start_service
                fi
                ;;
            2)
                show_ini_help
                edit_config
                ;;
            3)
                test_connection
                ;;
            4)
                sync_now
                ;;
            5)
                if [ -f "$STARTUP_FILE" ] && grep -Fq "# ftp_save_sync START" "$STARTUP_FILE"; then
                    disable_autostart
                else
                    enable_autostart
                fi
                ;;
            6)
                view_log
                ;;
            7)
                uninstall_script
                ;;
            8)
                exit 0
                ;;
        esac
    done
}

ensure_rclone_installed() {
    if [ -x "$RCLONE_BIN" ]; then
        if "$RCLONE_BIN" version >/dev/null 2>&1; then
            return 0
        fi
        rm -f "$RCLONE_BIN"
    fi

    install_rclone || return 1
    [ -x "$RCLONE_BIN" ] && "$RCLONE_BIN" version >/dev/null 2>&1
}

main() {
    require_tools
    ensure_base_dir

    if ! ensure_rclone_installed; then
        show_error "rclone is required for ftp_save_sync and could not be installed." 7 64
        exit 1
    fi

    install_daemon_script
    show_main_menu
}

main "$@"