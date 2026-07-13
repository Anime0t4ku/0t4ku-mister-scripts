#!/bin/sh

APP_NAME="cd_game_organizer"
APP_TITLE="MiSTer CD Game Organizer by Anime0t4ku"
VERSION="v1.2.0"
CONFIG_DIR="/media/fat/Scripts/.config/cd_game_organizer"
LOG_FILE="$CONFIG_DIR/organizer.log"

ROOTS="/media/fat/games /media/fat/cifs/games /media/usb0/games"
SUPPORTED_SYSTEMS="3DO CD-i MegaCD NeoGeo-CD PSX Saturn TGFX16-CD"
ALL_SYSTEMS_CSV="3DO,CD-i,MegaCD,NeoGeo-CD,PSX,Saturn,TGFX16-CD"

MODE="interactive"
ACTION=""
SYSTEM_FILTER=""
ROOT_CHOICE=""

MOVED_COUNT=0
CREATED_COUNT=0
SKIPPED_COUNT=0
ERROR_COUNT=0

RESTORE_FILE=""
TMP_MOVES=""
TMP_FOLDERS=""
RUN_WORK_DIR=""

mkdir -p "$CONFIG_DIR"

redraw_screen() {
    printf '\033[2J\033[H' >&2
}

log_line() {
    MSG="$1"
    echo "$MSG"
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$MSG" >> "$LOG_FILE"
}

trim_spaces() {
    printf '%s' "$1" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
}

safe_name() {
    printf '%s' "$1" | sed 's/[\/:*?"<>|]/_/g' | sed 's/[[:space:]]*$//'
}

strip_ext() {
    printf '%s' "${1%.*}"
}

lower_text() {
    printf '%s' "$1" | tr 'A-Z' 'a-z'
}

sanitize_id() {
    printf '%s' "$1" | sed 's/[^A-Za-z0-9._-]/_/g'
}

escape_json() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

reverse_file() {
    awk '{ lines[NR]=$0 } END { for (i=NR; i>=1; i--) print lines[i] }' "$1"
}

normalize_game_name() {
    NAME="$1"

    NAME=$(printf '%s' "$NAME" | sed -r '
        s/[[:space:]]*\((Disc|Disk|CD)[^)]*\).*$//g;
        s/[[:space:]]*\[(Disc|Disk|CD)[^]]*\].*$//g;
        s/[[:space:]]*-[[:space:]]*(Disc|Disk|CD)[[:space:]]*[0-9A-Za-z]+.*$//g;
        s/[[:space:]]*\((Track)[[:space:]]*[0-9]+[[:space:]]*\)//g;
        s/[[:space:]]*\[(Track)[[:space:]]*[0-9]+[[:space:]]*\]//g;
        s/[[:space:]]+/ /g;
    ')

    trim_spaces "$NAME"
}

relative_file_path() {
    SYSTEM_ROOT="$1"
    DIR="$2"
    FILE="$3"

    if [ "$DIR" = "$SYSTEM_ROOT" ]; then
        printf '%s' "$FILE"
    else
        REL_DIR="${DIR#$SYSTEM_ROOT/}"
        printf '%s/%s' "$REL_DIR" "$FILE"
    fi
}

is_known_mister_bios_file() {
    SYSTEM="$1"
    REL_PATH="$2"
    KEY=$(lower_text "$SYSTEM/$REL_PATH")

    case "$KEY" in
        "3do/boot.rom"|\
        "3do/kanji.rom"|\
        "cd-i/boot0.rom"|\
        "cd-i/boot1.rom"|\
        "cd-i/boot2.rom"|\
        "megacd/boot.rom"|\
        "megacd/europe/cd_bios.rom"|\
        "megacd/japan/cd_bios.rom"|\
        "megacd/usa/cd_bios.rom"|\
        "neogeo-cd/neocd.bin"|\
        "neogeo-cd/top-sp1.bin"|\
        "psx/boot.rom"|\
        "psx/boot1.rom"|\
        "psx/boot2.rom"|\
        "psx/sbi.zip"|\
        "saturn/boot.rom"|\
        "tgfx16-cd/cd_bios.rom")
            return 0
            ;;
    esac

    return 1
}

is_internal_path() {
    VALUE="$1"

    case "$VALUE" in
        "$CONFIG_DIR"*|/tmp/cd_game_organizer_*|*.tmp|*.missing|processed.txt|index.txt|group_*|tmp_*|*.main)
            return 0
            ;;
    esac

    return 1
}

is_internal_file_name() {
    FILE="$1"

    case "$FILE" in
        ""|/*|*/*|*\\*|*.tmp|*.missing|processed.txt|index.txt|group_*|tmp_*|*.main)
            return 0
            ;;
    esac

    return 1
}

system_selected() {
    SYS="$1"

    [ -z "$SYSTEM_FILTER" ] && return 0

    OLD_IFS="$IFS"
    IFS=","

    for ITEM in $SYSTEM_FILTER; do
        ITEM=$(trim_spaces "$ITEM")
        if [ "$ITEM" = "$SYS" ]; then
            IFS="$OLD_IFS"
            return 0
        fi
    done

    IFS="$OLD_IFS"
    return 1
}

is_supported_disc_file() {
    EXT=$(lower_text "${1##*.}")

    case "$EXT" in
        cue|chd|iso|img|ccd|m3u)
            return 0
            ;;
    esac

    return 1
}

is_track_or_audio_file() {
    EXT=$(lower_text "${1##*.}")

    case "$EXT" in
        bin|wav|flac|ogg|mp3|aiff|aif|raw|sub)
            return 0
            ;;
    esac

    return 1
}

already_listed() {
    grep -Fxq "$1" "$2" 2>/dev/null
}

add_unique_line() {
    LINE="$1"
    FILE="$2"

    [ -z "$LINE" ] && return

    if ! grep -Fxq "$LINE" "$FILE" 2>/dev/null; then
        printf '%s\n' "$LINE" >> "$FILE"
    fi
}

record_move() {
    FROM_ESC=$(escape_json "$1")
    TO_ESC=$(escape_json "$2")

    if [ ! -s "$TMP_MOVES" ]; then
        printf '    {"from": "%s", "to": "%s"}' "$FROM_ESC" "$TO_ESC" >> "$TMP_MOVES"
    else
        printf ',\n    {"from": "%s", "to": "%s"}' "$FROM_ESC" "$TO_ESC" >> "$TMP_MOVES"
    fi
}

record_folder() {
    FOLDER_ESC=$(escape_json "$1")

    if [ ! -s "$TMP_FOLDERS" ]; then
        printf '    "%s"' "$FOLDER_ESC" >> "$TMP_FOLDERS"
    else
        printf ',\n    "%s"' "$FOLDER_ESC" >> "$TMP_FOLDERS"
    fi
}

parse_cue_references() {
    CUE_FILE="$1"

    grep -i '^[[:space:]]*FILE[[:space:]]' "$CUE_FILE" 2>/dev/null | while IFS= read -r LINE; do
        REF=$(printf '%s\n' "$LINE" | sed -n 's/^[[:space:]]*FILE[[:space:]]*"\(.*\)"[[:space:]].*$/\1/p')

        if [ -z "$REF" ]; then
            REF=$(printf '%s\n' "$LINE" | sed -n "s/^[[:space:]]*FILE[[:space:]]*'\(.*\)'[[:space:]].*$/\1/p")
        fi

        if [ -z "$REF" ]; then
            REF=$(printf '%s\n' "$LINE" | awk '{print $2}')
        fi

        [ -n "$REF" ] && printf '%s\n' "$REF"
    done
}

parse_m3u_references() {
    M3U_FILE="$1"

    while IFS= read -r LINE || [ -n "$LINE" ]; do
        LINE=$(printf '%s' "$LINE" | tr -d '\r')
        LINE=$(trim_spaces "$LINE")

        case "$LINE" in
            ""|\#*)
                continue
                ;;
        esac

        printf '%s\n' "$LINE"
    done < "$M3U_FILE"
}

move_file_safe() {
    FROM="$1"
    TO="$2"

    if is_internal_path "$FROM" || is_internal_path "$TO"; then
        log_line "ERROR: Refusing to move internal path: $FROM"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        return 1
    fi

    if [ ! -e "$FROM" ]; then
        log_line "ERROR: Source missing: $FROM"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        return 1
    fi

    if [ -e "$TO" ]; then
        log_line "SKIP: Target already exists: $TO"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 1
    fi

    log_line "MOVE: $FROM"
    log_line "   -> $TO"

    if mv "$FROM" "$TO"; then
        record_move "$FROM" "$TO"
        MOVED_COUNT=$((MOVED_COUNT + 1))
        return 0
    fi

    log_line "ERROR: Failed to move: $FROM"
    ERROR_COUNT=$((ERROR_COUNT + 1))
    return 1
}

create_folder_safe() {
    FOLDER="$1"

    if is_internal_path "$FOLDER"; then
        log_line "ERROR: Refusing to create internal path: $FOLDER"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        return 1
    fi

    [ -d "$FOLDER" ] && return 0

    log_line "CREATE FOLDER: $FOLDER"

    if mkdir -p "$FOLDER"; then
        record_folder "$FOLDER"
        CREATED_COUNT=$((CREATED_COUNT + 1))
        return 0
    fi

    log_line "ERROR: Failed to create folder: $FOLDER"
    ERROR_COUNT=$((ERROR_COUNT + 1))
    return 1
}

collect_cue_group_files() {
    SYSTEM="$1"
    SYSTEM_ROOT="$2"
    DIR="$3"
    CUE="$4"
    OUT="$5"

    : > "$OUT"
    rm -f "$OUT.missing"

    printf '%s\n' "$CUE" >> "$OUT"

    REFS="$RUN_WORK_DIR/cue_refs_$(sanitize_id "$CUE").tmp"
    parse_cue_references "$DIR/$CUE" > "$REFS"

    while IFS= read -r REF || [ -n "$REF" ]; do
        [ -z "$REF" ] && continue

        if is_internal_file_name "$REF"; then
            printf 'MISSING:%s\n' "$REF" >> "$OUT.missing"
            continue
        fi

        REL_REF=$(relative_file_path "$SYSTEM_ROOT" "$DIR" "$REF")

        if is_known_mister_bios_file "$SYSTEM" "$REL_REF"; then
            log_line "SKIP BIOS REFERENCE: $DIR/$REF"
            continue
        fi

        if [ -e "$DIR/$REF" ]; then
            add_unique_line "$REF" "$OUT"
        else
            printf 'MISSING:%s\n' "$REF" >> "$OUT.missing"
        fi
    done < "$REFS"

    rm -f "$REFS"

    if [ -s "$OUT.missing" ]; then
        while IFS= read -r MISSING_LINE || [ -n "$MISSING_LINE" ]; do
            MISSING_REF=${MISSING_LINE#MISSING:}
            log_line "SKIP: $DIR/$CUE"
            log_line "Reason: referenced file missing or not loose in same folder: $MISSING_REF"
        done < "$OUT.missing"

        rm -f "$OUT.missing"
        return 1
    fi

    rm -f "$OUT.missing"
    return 0
}

collect_m3u_group_files() {
    SYSTEM="$1"
    SYSTEM_ROOT="$2"
    DIR="$3"
    M3U="$4"
    OUT="$5"

    : > "$OUT"
    rm -f "$OUT.missing"

    printf '%s\n' "$M3U" >> "$OUT"

    REFS="$RUN_WORK_DIR/m3u_refs_$(sanitize_id "$M3U").tmp"
    parse_m3u_references "$DIR/$M3U" > "$REFS"

    while IFS= read -r REF || [ -n "$REF" ]; do
        [ -z "$REF" ] && continue

        if is_internal_file_name "$REF"; then
            printf 'MISSING:%s\n' "$REF" >> "$OUT.missing"
            continue
        fi

        REL_REF=$(relative_file_path "$SYSTEM_ROOT" "$DIR" "$REF")

        if is_known_mister_bios_file "$SYSTEM" "$REL_REF"; then
            log_line "SKIP BIOS REFERENCE: $DIR/$REF"
            continue
        fi

        if [ -e "$DIR/$REF" ]; then
            add_unique_line "$REF" "$OUT"
        else
            printf 'MISSING:%s\n' "$REF" >> "$OUT.missing"
        fi
    done < "$REFS"

    rm -f "$REFS"

    if [ -s "$OUT.missing" ]; then
        while IFS= read -r MISSING_LINE || [ -n "$MISSING_LINE" ]; do
            MISSING_REF=${MISSING_LINE#MISSING:}
            log_line "SKIP: $DIR/$M3U"
            log_line "Reason: referenced file missing or not loose in same folder: $MISSING_REF"
        done < "$OUT.missing"

        rm -f "$OUT.missing"
        return 1
    fi

    rm -f "$OUT.missing"
    return 0
}

add_ccd_sidecars() {
    DIR="$1"
    FILE="$2"
    OUT="$3"
    BASE=$(strip_ext "$FILE")

    for EXT in img IMG sub SUB; do
        SIDE="$BASE.$EXT"
        [ -f "$DIR/$SIDE" ] && add_unique_line "$SIDE" "$OUT"
    done
}

set_group_main_file() {
    GROUP="$1"
    MAIN="$2"
    MAIN_MARKER="$GROUP.main"

    if [ ! -f "$MAIN_MARKER" ]; then
        printf '%s' "$MAIN" > "$MAIN_MARKER"
    fi
}

count_group_files() {
    DIR_TO_COUNT="$1"
    COUNT=0

    for GROUP in "$DIR_TO_COUNT"/group_*.txt; do
        [ -f "$GROUP" ] || continue
        COUNT=$((COUNT + 1))
    done

    printf '%s' "$COUNT"
}

organize_group() {
    SYSTEM="$1"
    SYSTEM_ROOT="$2"
    DIR="$3"
    MAIN_FILE="$4"
    GROUP_FILE_LIST="$5"

    if is_internal_file_name "$MAIN_FILE"; then
        log_line "SKIP INTERNAL OR INVALID FILE: $MAIN_FILE"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return
    fi

    REL_MAIN=$(relative_file_path "$SYSTEM_ROOT" "$DIR" "$MAIN_FILE")

    if is_known_mister_bios_file "$SYSTEM" "$REL_MAIN"; then
        log_line "SKIP BIOS FILE: $DIR/$MAIN_FILE"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return
    fi

    BASE=$(strip_ext "$MAIN_FILE")
    GAME_NAME=$(normalize_game_name "$BASE")
    GAME_NAME=$(safe_name "$GAME_NAME")

    if [ -z "$GAME_NAME" ]; then
        log_line "SKIP: $DIR/$MAIN_FILE"
        log_line "Reason: could not determine folder name"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return
    fi

    if is_internal_path "$GAME_NAME"; then
        log_line "SKIP INTERNAL GAME NAME: $GAME_NAME"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return
    fi

    CURRENT_FOLDER=$(basename "$DIR")

    if [ "$CURRENT_FOLDER" = "$GAME_NAME" ]; then
        log_line "SKIP: $DIR"
        log_line "Reason: files are already inside a matching game folder"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return
    fi

    TARGET_DIR="$DIR/$GAME_NAME"

    if [ -d "$TARGET_DIR" ]; then
        log_line "SKIP: $DIR/$MAIN_FILE"
        log_line "Reason: target folder already exists: $TARGET_DIR"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return
    fi

    create_folder_safe "$TARGET_DIR" || return

    while IFS= read -r ITEM || [ -n "$ITEM" ]; do
        [ -z "$ITEM" ] && continue

        if is_internal_file_name "$ITEM"; then
            log_line "SKIP INVALID GROUP ITEM: $ITEM"
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            continue
        fi

        REL_ITEM=$(relative_file_path "$SYSTEM_ROOT" "$DIR" "$ITEM")

        if is_known_mister_bios_file "$SYSTEM" "$REL_ITEM"; then
            log_line "SKIP BIOS FILE: $DIR/$ITEM"
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            continue
        fi

        move_file_safe "$DIR/$ITEM" "$TARGET_DIR/$ITEM"
    done < "$GROUP_FILE_LIST"
}

process_group_files() {
    SYSTEM="$1"
    SYSTEM_ROOT="$2"
    DIR="$3"
    PREFIX="$4"

    for GROUP in "$WORK_DIR"/"$PREFIX"_*.txt; do
        [ -f "$GROUP" ] || continue

        MAIN_FILE=""

        if [ -f "$GROUP.main" ]; then
            MAIN_FILE=$(cat "$GROUP.main" 2>/dev/null)
        fi

        [ -z "$MAIN_FILE" ] && continue

        if is_internal_file_name "$MAIN_FILE"; then
            log_line "SKIP INTERNAL OR INVALID GROUP MAIN: $MAIN_FILE"
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            continue
        fi

        case "$PREFIX" in
            group_m3u)
                log_line "FOUND M3U GAME: $DIR/$MAIN_FILE"
                ;;
            group_cue)
                log_line "FOUND CUE GAME: $DIR/$MAIN_FILE"
                ;;
            group_single)
                log_line "FOUND DISC IMAGE: $DIR/$MAIN_FILE"
                ;;
        esac

        organize_group "$SYSTEM" "$SYSTEM_ROOT" "$DIR" "$MAIN_FILE" "$GROUP"
    done
}

folder_has_child_dirs() {
    CHECK_DIR="$1"

    for CHILD in "$CHECK_DIR"/*; do
        [ -d "$CHILD" ] && return 0
    done

    return 1
}

process_directory() {
    SYSTEM="$1"
    SYSTEM_ROOT="$2"
    DIR="$3"

    [ -d "$DIR" ] || return

    case "$DIR" in
        "$CONFIG_DIR"*|/tmp/cd_game_organizer_*)
            return
            ;;
    esac

    DIR_ID=$(sanitize_id "$(printf '%s' "$DIR" | sed 's#/#_#g')")
    WORK_DIR="$RUN_WORK_DIR/work_$DIR_ID"

    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"

    PROCESSED="$WORK_DIR/processed.txt"
    : > "$PROCESSED"

    for M3U_PATH in "$DIR"/*.m3u "$DIR"/*.M3U; do
        [ -f "$M3U_PATH" ] || continue

        M3U=$(basename "$M3U_PATH")
        is_internal_file_name "$M3U" && continue

        REL_M3U=$(relative_file_path "$SYSTEM_ROOT" "$DIR" "$M3U")

        if is_known_mister_bios_file "$SYSTEM" "$REL_M3U"; then
            log_line "SKIP BIOS FILE: $DIR/$M3U"
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            continue
        fi

        GROUP_NAME=$(safe_name "$(normalize_game_name "$(strip_ext "$M3U")")")
        GROUP_ID=$(sanitize_id "$GROUP_NAME")
        GROUP="$WORK_DIR/group_m3u_$GROUP_ID.txt"

        if collect_m3u_group_files "$SYSTEM" "$SYSTEM_ROOT" "$DIR" "$M3U" "$GROUP"; then
            set_group_main_file "$GROUP" "$M3U"

            while IFS= read -r ITEM || [ -n "$ITEM" ]; do
                [ -n "$ITEM" ] && add_unique_line "$ITEM" "$PROCESSED"
            done < "$GROUP"
        else
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        fi
    done

    for CUE_PATH in "$DIR"/*.cue "$DIR"/*.CUE; do
        [ -f "$CUE_PATH" ] || continue

        CUE=$(basename "$CUE_PATH")
        already_listed "$CUE" "$PROCESSED" && continue
        is_internal_file_name "$CUE" && continue

        REL_CUE=$(relative_file_path "$SYSTEM_ROOT" "$DIR" "$CUE")

        if is_known_mister_bios_file "$SYSTEM" "$REL_CUE"; then
            log_line "SKIP BIOS FILE: $DIR/$CUE"
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            continue
        fi

        GROUP_NAME=$(safe_name "$(normalize_game_name "$(strip_ext "$CUE")")")
        GROUP_ID=$(sanitize_id "$GROUP_NAME")
        GROUP="$WORK_DIR/group_cue_$GROUP_ID.txt"
        TMP_GROUP="$WORK_DIR/tmp_cue_$(sanitize_id "$CUE").txt"

        [ -f "$GROUP" ] || : > "$GROUP"

        if collect_cue_group_files "$SYSTEM" "$SYSTEM_ROOT" "$DIR" "$CUE" "$TMP_GROUP"; then
            set_group_main_file "$GROUP" "$CUE"

            while IFS= read -r ITEM || [ -n "$ITEM" ]; do
                [ -n "$ITEM" ] && add_unique_line "$ITEM" "$GROUP"
                [ -n "$ITEM" ] && add_unique_line "$ITEM" "$PROCESSED"
            done < "$TMP_GROUP"
        else
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        fi

        rm -f "$TMP_GROUP"
    done

    for DISC_PATH in "$DIR"/*; do
        [ -f "$DISC_PATH" ] || continue

        FILE=$(basename "$DISC_PATH")
        already_listed "$FILE" "$PROCESSED" && continue
        is_internal_file_name "$FILE" && continue

        REL_FILE=$(relative_file_path "$SYSTEM_ROOT" "$DIR" "$FILE")

        if is_known_mister_bios_file "$SYSTEM" "$REL_FILE"; then
            log_line "SKIP BIOS FILE: $DIR/$FILE"
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            continue
        fi

        if is_track_or_audio_file "$FILE"; then
            continue
        fi

        if ! is_supported_disc_file "$FILE"; then
            continue
        fi

        case "$(lower_text "${FILE##*.}")" in
            cue|m3u)
                continue
                ;;
        esac

        GROUP_NAME=$(safe_name "$(normalize_game_name "$(strip_ext "$FILE")")")
        GROUP_ID=$(sanitize_id "$GROUP_NAME")
        GROUP="$WORK_DIR/group_single_$GROUP_ID.txt"

        [ -f "$GROUP" ] || : > "$GROUP"

        set_group_main_file "$GROUP" "$FILE"
        add_unique_line "$FILE" "$GROUP"
        add_unique_line "$FILE" "$PROCESSED"

        case "$(lower_text "${FILE##*.}")" in
            ccd)
                add_ccd_sidecars "$DIR" "$FILE" "$GROUP"

                while IFS= read -r ITEM || [ -n "$ITEM" ]; do
                    [ -n "$ITEM" ] && add_unique_line "$ITEM" "$PROCESSED"
                done < "$GROUP"
                ;;
        esac
    done

    GROUP_COUNT=$(count_group_files "$WORK_DIR")

    if [ "$GROUP_COUNT" -eq 0 ]; then
        rm -rf "$WORK_DIR"
        return
    fi

    if [ "$GROUP_COUNT" -eq 1 ] && ! folder_has_child_dirs "$DIR"; then
        ONLY_MAIN_FILE=""

        for GROUP in "$WORK_DIR"/group_*.txt; do
            [ -f "$GROUP" ] || continue

            if [ -f "$GROUP.main" ]; then
                ONLY_MAIN_FILE=$(cat "$GROUP.main" 2>/dev/null)
            fi

            break
        done

        if [ -n "$ONLY_MAIN_FILE" ] && ! is_internal_file_name "$ONLY_MAIN_FILE"; then
            ONLY_GAME_NAME=$(safe_name "$(normalize_game_name "$(strip_ext "$ONLY_MAIN_FILE")")")
            CURRENT_FOLDER=$(basename "$DIR")

            if [ "$CURRENT_FOLDER" = "$ONLY_GAME_NAME" ]; then
                rm -rf "$WORK_DIR"
                return
            fi
        fi
    fi

    log_line "PROCESS FOLDER: $DIR"
    log_line "Reason: found $GROUP_COUNT game groups"

    process_group_files "$SYSTEM" "$SYSTEM_ROOT" "$DIR" "group_m3u"
    process_group_files "$SYSTEM" "$SYSTEM_ROOT" "$DIR" "group_cue"
    process_group_files "$SYSTEM" "$SYSTEM_ROOT" "$DIR" "group_single"

    rm -rf "$WORK_DIR"
}

walk_directory_recursive() {
    SYSTEM="$1"
    SYSTEM_ROOT="$2"
    DIR="$3"

    [ -d "$DIR" ] || return

    case "$DIR" in
        "$CONFIG_DIR"*|/tmp/cd_game_organizer_*)
            return
            ;;
    esac

    log_line "SCAN FOLDER: $DIR"

    CHILD_LIST="$RUN_WORK_DIR/children_$(sanitize_id "$DIR").tmp"
    : > "$CHILD_LIST"

    for CHILD in "$DIR"/*; do
        [ -d "$CHILD" ] || continue

        if [ -L "$CHILD" ]; then
            log_line "SKIP FOLDER: $CHILD"
            log_line "Reason: folder is a symlink"
            continue
        fi

        case "$CHILD" in
            "$CONFIG_DIR"*|/tmp/cd_game_organizer_*)
                continue
                ;;
        esac

        printf '%s\n' "$CHILD" >> "$CHILD_LIST"
    done

    process_directory "$SYSTEM" "$SYSTEM_ROOT" "$DIR"

    while IFS= read -r CHILD || [ -n "$CHILD" ]; do
        [ -d "$CHILD" ] || continue
        walk_directory_recursive "$SYSTEM" "$SYSTEM_ROOT" "$CHILD"
    done < "$CHILD_LIST"

    rm -f "$CHILD_LIST"
}

walk_system_folder() {
    SYSTEM="$1"
    SYSTEM_DIR="$2"

    [ -d "$SYSTEM_DIR" ] || return

    log_line "SCANNING SYSTEM FOLDER: $SYSTEM_DIR"

    walk_directory_recursive "$SYSTEM" "$SYSTEM_DIR" "$SYSTEM_DIR"
}

write_restore_manifest() {
    START_TIME="$1"

    if [ ! -s "$TMP_MOVES" ]; then
        rm -f "$RESTORE_FILE" "$TMP_MOVES" "$TMP_FOLDERS"
        log_line "No files moved. No restore manifest created."
        return
    fi

    {
        printf '{\n'
        printf '  "app": "%s",\n' "$APP_NAME"
        printf '  "created_at": "%s",\n' "$START_TIME"
        printf '  "moves": [\n'
        cat "$TMP_MOVES"
        printf '\n  ],\n'
        printf '  "created_folders": [\n'
        cat "$TMP_FOLDERS"
        printf '\n  ]\n'
        printf '}\n'
    } > "$RESTORE_FILE"

    rm -f "$TMP_MOVES" "$TMP_FOLDERS"

    log_line "RESTORE MANIFEST SAVED: $RESTORE_FILE"
}

organize_games() {
    SELECTED_SYSTEMS="$1"

    START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    STAMP=$(date '+%Y%m%d_%H%M%S')

    RESTORE_FILE="$CONFIG_DIR/restore_$STAMP.json"
    TMP_MOVES="$CONFIG_DIR/.moves_$STAMP.tmp"
    TMP_FOLDERS="$CONFIG_DIR/.folders_$STAMP.tmp"
    RUN_WORK_DIR="/tmp/cd_game_organizer_$$"

    rm -rf "$RUN_WORK_DIR"
    mkdir -p "$RUN_WORK_DIR"

    : > "$TMP_MOVES"
    : > "$TMP_FOLDERS"

    MOVED_COUNT=0
    CREATED_COUNT=0
    SKIPPED_COUNT=0
    ERROR_COUNT=0

    SYSTEM_FILTER="$SELECTED_SYSTEMS"

    log_line "============================================================"
    log_line "$APP_TITLE"
    log_line "Action: organize"
    log_line "Started: $START_TIME"
    log_line "Available games roots: $ROOTS"

    if [ -n "$SYSTEM_FILTER" ]; then
        log_line "Selected systems: $SYSTEM_FILTER"
    else
        log_line "Selected systems: all supported systems"
    fi

    LOCAL_ROOT="/media/fat/games"
    CIFS_ROOT="/media/fat/cifs/games"
    USB0_ROOT="/media/usb0/games"

    case "$ROOT_CHOICE" in
        local|"")
            SCAN_ROOTS="$LOCAL_ROOT"
            ROOT_CHOICE="local"
            ;;
        cifs)
            SCAN_ROOTS="$CIFS_ROOT"
            ;;
        usb0)
            SCAN_ROOTS="$USB0_ROOT"
            ;;
        *)
            log_line "ERROR: Unknown root selection: $ROOT_CHOICE"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            write_restore_manifest "$START_TIME"
            rm -rf "$RUN_WORK_DIR"
            return 1
            ;;
    esac

    log_line "Selected games root: $SCAN_ROOTS"

    for ROOT in $SCAN_ROOTS; do
        if [ ! -d "$ROOT" ]; then
            log_line "SKIP ROOT: $ROOT"
            log_line "Reason: folder does not exist or is not mounted"
            continue
        fi

        log_line "SCANNING ROOT: $ROOT"

        for SYS in $SUPPORTED_SYSTEMS; do
            if ! system_selected "$SYS"; then
                log_line "SKIP SYSTEM: $SYS"
                log_line "Reason: not selected for this run"
                continue
            fi

            SYSTEM_DIR="$ROOT/$SYS"

            if [ ! -d "$SYSTEM_DIR" ]; then
                log_line "SKIP SYSTEM: $SYSTEM_DIR"
                log_line "Reason: folder does not exist"
                continue
            fi

            walk_system_folder "$SYS" "$SYSTEM_DIR"
        done
    done

    write_restore_manifest "$START_TIME"

    rm -rf "$RUN_WORK_DIR"

    log_line "Done."
    log_line "Moved files: $MOVED_COUNT"
    log_line "Created folders: $CREATED_COUNT"
    log_line "Skipped: $SKIPPED_COUNT"
    log_line "Errors: $ERROR_COUNT"
    log_line "============================================================"
}

latest_restore_file() {
    ls -1t "$CONFIG_DIR"/restore_*.json 2>/dev/null | head -n 1
}

extract_restore_moves() {
    sed -n 's/.*"from": "\(.*\)", "to": "\(.*\)".*/\1|\2/p' "$1" | sed 's/\\"/"/g; s/\\\\/\\/g'
}

extract_restore_folders() {
    sed -n '/"created_folders": \[/,/\]/p' "$1" | \
        sed -n 's/^[[:space:]]*"\(.*\)"[,]*/\1/p' | \
        sed 's/\\"/"/g; s/\\\\/\\/g'
}

restore_last() {
    RESTORE=$(latest_restore_file)

    log_line "============================================================"
    log_line "$APP_TITLE"
    log_line "Action: restore-last"

    if [ -z "$RESTORE" ] || [ ! -f "$RESTORE" ]; then
        log_line "No restore manifest found."
        return 1
    fi

    log_line "Using restore manifest: $RESTORE"

    TMP_RESTORE="/tmp/cd_game_organizer_restore_moves_$$.tmp"
    extract_restore_moves "$RESTORE" > "$TMP_RESTORE"

    reverse_file "$TMP_RESTORE" | while IFS='|' read -r ORIGINAL CURRENT; do
        [ -z "$ORIGINAL" ] && continue
        [ -z "$CURRENT" ] && continue

        if [ ! -e "$CURRENT" ]; then
            log_line "SKIP RESTORE: $CURRENT"
            log_line "Reason: moved file no longer exists"
            continue
        fi

        if [ -e "$ORIGINAL" ]; then
            log_line "SKIP RESTORE: $CURRENT"
            log_line "Reason: original path already exists: $ORIGINAL"
            continue
        fi

        ORIGINAL_DIR=$(dirname "$ORIGINAL")
        mkdir -p "$ORIGINAL_DIR"

        log_line "RESTORE MOVE: $CURRENT"
        log_line "          -> $ORIGINAL"

        if ! mv "$CURRENT" "$ORIGINAL"; then
            log_line "ERROR: Failed to restore: $CURRENT"
        fi
    done

    rm -f "$TMP_RESTORE"

    TMP_FOLDERS_RESTORE="/tmp/cd_game_organizer_restore_folders_$$.tmp"
    extract_restore_folders "$RESTORE" > "$TMP_FOLDERS_RESTORE"

    reverse_file "$TMP_FOLDERS_RESTORE" | while IFS= read -r FOLDER; do
        [ -z "$FOLDER" ] && continue

        if [ -d "$FOLDER" ]; then
            if rmdir "$FOLDER" 2>/dev/null; then
                log_line "REMOVED EMPTY FOLDER: $FOLDER"
            else
                log_line "KEEP FOLDER: $FOLDER"
                log_line "Reason: folder is not empty or could not be removed"
            fi
        fi
    done

    rm -f "$TMP_FOLDERS_RESTORE"

    log_line "Restore finished."
    log_line "============================================================"
}

toggle_system_in_csv() {
    CSV="$1"
    SYS="$2"
    NEW=""
    FOUND=0

    OLD_IFS="$IFS"
    IFS=","

    for ITEM in $CSV; do
        ITEM=$(trim_spaces "$ITEM")
        [ -z "$ITEM" ] && continue

        if [ "$ITEM" = "$SYS" ]; then
            FOUND=1
            continue
        fi

        if [ -z "$NEW" ]; then
            NEW="$ITEM"
        else
            NEW="$NEW,$ITEM"
        fi
    done

    IFS="$OLD_IFS"

    if [ "$FOUND" -eq 0 ]; then
        if [ -z "$NEW" ]; then
            NEW="$SYS"
        else
            NEW="$NEW,$SYS"
        fi
    fi

    printf '%s' "$NEW"
}

system_is_in_csv() {
    CSV="$1"
    SYS="$2"

    OLD_IFS="$IFS"
    IFS=","

    for ITEM in $CSV; do
        ITEM=$(trim_spaces "$ITEM")
        if [ "$ITEM" = "$SYS" ]; then
            IFS="$OLD_IFS"
            return 0
        fi
    done

    IFS="$OLD_IFS"
    return 1
}

show_msg() {
    dialog --title "$APP_TITLE" --msgbox "$1" "${2:-8}" "${3:-60}"
    redraw_screen
}

show_root_select_menu() {
    CHOICE=$(dialog --clear \
        --title "$APP_TITLE" \
        --menu "Choose where your games are stored:" 12 68 4 \
        local "Local - /media/fat/games" \
        cifs "CIFS - /media/fat/cifs/games" \
        usb0 "USB0 - /media/usb0/games" \
        cancel "Cancel" \
        3>&1 1>&2 2>&3)
    STATUS=$?
    redraw_screen

    [ "$STATUS" -ne 0 ] && return 1
    [ "$CHOICE" = "cancel" ] && return 1

    ROOT_CHOICE="$CHOICE"
    return 0
}

show_system_select_menu() {
    SELECTED="$ALL_SYSTEMS_CSV"

    while true; do
        LABEL_3DO="[ ] 3DO"
        LABEL_CDI="[ ] CD-i"
        LABEL_MEGACD="[ ] MegaCD"
        LABEL_NEOGEOCD="[ ] NeoGeo-CD"
        LABEL_PSX="[ ] PSX"
        LABEL_SATURN="[ ] Saturn"
        LABEL_TGFX16CD="[ ] TGFX16-CD"

        system_is_in_csv "$SELECTED" "3DO" && LABEL_3DO="[X] 3DO"
        system_is_in_csv "$SELECTED" "CD-i" && LABEL_CDI="[X] CD-i"
        system_is_in_csv "$SELECTED" "MegaCD" && LABEL_MEGACD="[X] MegaCD"
        system_is_in_csv "$SELECTED" "NeoGeo-CD" && LABEL_NEOGEOCD="[X] NeoGeo-CD"
        system_is_in_csv "$SELECTED" "PSX" && LABEL_PSX="[X] PSX"
        system_is_in_csv "$SELECTED" "Saturn" && LABEL_SATURN="[X] Saturn"
        system_is_in_csv "$SELECTED" "TGFX16-CD" && LABEL_TGFX16CD="[X] TGFX16-CD"

        CHOICE=$(dialog --clear \
            --title "$APP_TITLE" \
            --menu "Toggle systems on/off, then choose Start organizing." 20 72 11 \
            3DO "$LABEL_3DO" \
            CD-i "$LABEL_CDI" \
            MegaCD "$LABEL_MEGACD" \
            NeoGeo-CD "$LABEL_NEOGEOCD" \
            PSX "$LABEL_PSX" \
            Saturn "$LABEL_SATURN" \
            TGFX16-CD "$LABEL_TGFX16CD" \
            SELECT_ALL "Select all systems" \
            DESELECT_ALL "Deselect all systems" \
            START "Start organizing" \
            CANCEL "Cancel" \
            3>&1 1>&2 2>&3)
        STATUS=$?
        redraw_screen

        [ "$STATUS" -ne 0 ] && return 1

        case "$CHOICE" in
            3DO|CD-i|MegaCD|NeoGeo-CD|PSX|Saturn|TGFX16-CD)
                SELECTED=$(toggle_system_in_csv "$SELECTED" "$CHOICE")
                ;;
            SELECT_ALL)
                SELECTED="$ALL_SYSTEMS_CSV"
                ;;
            DESELECT_ALL)
                SELECTED=""
                ;;
            START)
                [ -z "$SELECTED" ] && return 1
                SYSTEM_FILTER="$SELECTED"
                return 0
                ;;
            CANCEL)
                return 1
                ;;
        esac
    done
}

show_main_menu() {
    while true; do
        CHOICE=$(dialog --clear \
            --title "$APP_TITLE" \
            --menu "Choose an option:" 12 60 3 \
            1 "Organize games" \
            2 "Restore last organization" \
            3 "Exit" \
            3>&1 1>&2 2>&3)
        STATUS=$?
        redraw_screen

        [ "$STATUS" -ne 0 ] && exit 0

        case "$CHOICE" in
            1)
                if show_root_select_menu && show_system_select_menu; then
                    organize_games "$SYSTEM_FILTER"
                    show_msg "Organization finished.

Moved files: $MOVED_COUNT
Created folders: $CREATED_COUNT
Skipped: $SKIPPED_COUNT
Errors: $ERROR_COUNT

Log:
$LOG_FILE" 12 64
                else
                    show_msg "No systems were selected.

Nothing was changed." 8 50
                fi
                ;;
            2)
                restore_last
                show_msg "Restore finished.

Check the output log for details:
$LOG_FILE" 8 64
                ;;
            3)
                exit 0
                ;;
        esac
    done
}

show_help() {
    cat <<EOF
$APP_TITLE

Usage:
  $0
  $0 --organize --unattended --root local
  $0 --organize --unattended --root cifs --systems PSX,Saturn,MegaCD
  $0 --organize --unattended --root usb0
  $0 --restore-last --unattended

Options:
  --organize          Organize loose CD games into per-game folders.
  --restore-last      Restore the most recent organization run.
  --unattended        Run without dialog menus.
  --root LOCATION     Games location: local, cifs, or usb0. Default: local.
  --systems LIST      Comma-separated system list, for example PSX,Saturn.
  --help              Show this help.

Supported systems:
  $SUPPORTED_SYSTEMS

Game locations:
  local  /media/fat/games
  cifs   /media/fat/cifs/games
  usb0   /media/usb0/games

Config and logs:
  $CONFIG_DIR
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --organize)
            ACTION="organize"
            ;;
        --restore-last)
            ACTION="restore-last"
            ;;
        --unattended)
            MODE="unattended"
            ;;
        --root)
            shift
            ROOT_CHOICE="$1"
            ;;
        --systems)
            shift
            SYSTEM_FILTER="$1"
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo
            show_help
            exit 1
            ;;
    esac
    shift
done

case "$ROOT_CHOICE" in
    ""|local|cifs|usb0)
        ;;
    *)
        echo "Unknown root: $ROOT_CHOICE"
        echo "Valid roots: local, cifs, usb0"
        exit 1
        ;;
esac

if [ "$MODE" = "unattended" ]; then
    case "$ACTION" in
        organize|"")
            organize_games "$SYSTEM_FILTER"
            ;;
        restore-last)
            restore_last
            ;;
        *)
            echo "Unknown action: $ACTION"
            exit 1
            ;;
    esac
    exit 0
fi

if ! command -v dialog >/dev/null 2>&1; then
    echo "$APP_TITLE"
    echo "dialog is not installed, running unattended organize mode."
    MODE="unattended"
    organize_games ""
    exit 0
fi

show_main_menu
