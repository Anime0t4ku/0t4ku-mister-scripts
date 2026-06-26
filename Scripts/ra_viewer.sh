#!/bin/sh

TITLE="RetroAchievements Viewer for MiSTer by Anime0t4ku"
VERSION="v1.1.0"

BASE="/media/fat/Scripts/.config/ra_viewer"
HELPER="$BASE/ra_viewer.py"
LOG="$BASE/ra_viewer.log"
PY_LIB="$BASE/python_lib"
PIP_BOOTSTRAP="$BASE/pip_bootstrap"
PIP_LOG="$BASE/pip_install.log"
GET_PIP="$BASE/get-pip.py"
PILLOW_TEST="$BASE/pillow_test.log"
LIB_DIR="$BASE/lib"
DEB_DIR="$BASE/debs"
TMP_DIR="$BASE/tmp"
FONT_DIR="$BASE/fonts"

mkdir -p "$BASE" "$PY_LIB" "$PIP_BOOTSTRAP" "$LIB_DIR" "$DEB_DIR" "$TMP_DIR" "$FONT_DIR"

export PYTHONPATH="$PY_LIB:$PIP_BOOTSTRAP:$PYTHONPATH"
export LD_LIBRARY_PATH="$LIB_DIR:$LD_LIBRARY_PATH"

cat > "$HELPER" <<'PYEOF'
#!/usr/bin/env python3
import configparser
import curses
import html
import json
import os
import re
import shutil
import subprocess
import sys
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

TITLE = "RetroAchievements Viewer for MiSTer by Anime0t4ku"
API_BASE = "https://retroachievements.org/API"
RA_MEDIA_BASE = "https://media.retroachievements.org"
USER_AGENT = "MiSTer RA Viewer by Anime0t4ku/1.4"

BASE = Path("/media/fat/Scripts/.config/ra_viewer")
CONFIG = BASE / "config.ini"
ERROR_LOG = BASE / "ra_viewer.log"
CACHE = BASE / "cache"
GAME_CACHE = CACHE / "games"
BADGE_CACHE = CACHE / "badges"
CARD_CACHE = CACHE / "cards"
FONT_DIR = BASE / "fonts"

for p in (BASE, CACHE, GAME_CACHE, BADGE_CACHE, CARD_CACHE, FONT_DIR):
    p.mkdir(parents=True, exist_ok=True)

try:
    from PIL import Image, ImageDraw, ImageFont
    PIL_AVAILABLE = True
except Exception:
    PIL_AVAILABLE = False


def clear_terminal():
    os.system("clear")


def create_config_template():
    with open(CONFIG, "w", encoding="utf-8") as f:
        f.write("[retroachievements]\n")
        f.write("username=YourUsername\n")
        f.write("api_key=YourWebApiKey\n")
    try:
        os.chmod(CONFIG, 0o600)
    except Exception:
        pass


def read_config():
    if not CONFIG.exists():
        return None, None
    parser = configparser.ConfigParser()
    parser.read(CONFIG)
    username = parser.get("retroachievements", "username", fallback="").strip()
    api_key = parser.get("retroachievements", "api_key", fallback="").strip()
    if username in ("", "YourUsername") or api_key in ("", "YourWebApiKey"):
        return None, None
    return username, api_key


def api_get(endpoint, params, timeout=30):
    query = urllib.parse.urlencode(params)
    url = f"{API_BASE}/{endpoint}?{query}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"RetroAchievements API error HTTP {e.code}:\n\n{body[:1000]}")
    except urllib.error.URLError as e:
        raise RuntimeError(f"Network error while contacting RetroAchievements:\n\n{e}")
    try:
        return json.loads(raw)
    except Exception:
        raise RuntimeError(f"RetroAchievements returned invalid JSON:\n\n{raw[:1000]}")


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path, data):
    tmp = Path(str(path) + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    tmp.replace(path)


def clean_text(value):
    value = html.unescape(str(value or ""))
    value = value.replace("\n", " ").replace("\r", " ")
    value = re.sub(r"\s+", " ", value).strip()
    value = value.encode("ascii", "replace").decode("ascii")
    return value


def short_text(value, max_len=70):
    value = clean_text(value)
    if len(value) > max_len:
        return value[: max_len - 3] + "..."
    return value


def get_games(force=False):
    username, api_key = read_config()
    cache_file = CACHE / "games.json"
    if cache_file.exists() and not force:
        return load_json(cache_file)
    all_results = []
    offset = 0
    count = 500
    while True:
        data = api_get("API_GetUserCompletionProgress.php", {"y": api_key, "u": username, "c": count, "o": offset})
        results = data.get("Results", [])
        if not isinstance(results, list):
            raise RuntimeError("Unexpected RetroAchievements response. Missing Results list.")
        all_results.extend(results)
        total = int(data.get("Total", len(all_results)) or len(all_results))
        offset += len(results)
        if not results or offset >= total:
            break
        time.sleep(0.25)
    payload = {"fetched_at": int(time.time()), "username": username, "Count": len(all_results), "Total": len(all_results), "Results": all_results}
    save_json(cache_file, payload)
    return payload


def get_game(game_id, force=False):
    username, api_key = read_config()
    cache_file = GAME_CACHE / f"{game_id}.json"
    if cache_file.exists() and not force:
        return load_json(cache_file)
    data = api_get("API_GetGameInfoAndUserProgress.php", {"y": api_key, "u": username, "g": str(game_id), "a": "1"})
    save_json(cache_file, data)
    return data


def normalize_achievements(game_data):
    achievements = game_data.get("Achievements", {})
    if isinstance(achievements, dict):
        rows = list(achievements.values())
    elif isinstance(achievements, list):
        rows = achievements
    else:
        rows = []

    def order_key(a):
        try:
            return int(a.get("DisplayOrder", 999999))
        except Exception:
            return 999999

    return sorted(rows, key=order_key)


def achievement_dates(achievement):
    softcore = achievement.get("DateEarned") or achievement.get("DateEarnedSoftcore")
    hardcore = achievement.get("DateEarnedHardcore")
    return softcore, hardcore


def is_unlocked(achievement):
    softcore, hardcore = achievement_dates(achievement)
    return bool(softcore or hardcore)


def achievement_status(achievement):
    softcore, hardcore = achievement_dates(achievement)
    if softcore and hardcore:
        return "Unlocked SC+HC"
    if hardcore:
        return "Unlocked HC"
    if softcore:
        return "Unlocked SC"
    return "Locked"


def achievement_mark(achievement):
    softcore, hardcore = achievement_dates(achievement)
    if hardcore:
        return "[H]"
    if softcore:
        return "[S]"
    return "[ ]"


def detect_framebuffer_size():
    paths = [
        Path("/sys/class/graphics/fb0/virtual_size"),
        Path("/sys/class/graphics/fb0/modes"),
    ]
    for path in paths:
        try:
            text = path.read_text(encoding="utf-8", errors="replace").strip()
        except Exception:
            continue
        match = re.search(r"(\d{3,5})\s*[,x]\s*(\d{3,5})", text)
        if match:
            width = int(match.group(1))
            height = int(match.group(2))
            if width >= 320 and height >= 240:
                return width, height
    try:
        output = subprocess.check_output(["fbset", "-s"], stderr=subprocess.DEVNULL, timeout=2).decode("utf-8", errors="replace")
        match = re.search(r'geometry\s+(\d{3,5})\s+(\d{3,5})', output)
        if match:
            width = int(match.group(1))
            height = int(match.group(2))
            if width >= 320 and height >= 240:
                return width, height
    except Exception:
        pass
    return None, None


def clamp(value, minimum, maximum):
    return max(minimum, min(maximum, value))


def build_card_layout():
    fb_width, fb_height = detect_framebuffer_size()
    if not fb_width or not fb_height:
        fb_width, fb_height = 1280, 720

    ratio = fb_width / float(fb_height)
    is_four_three = ratio < 1.55

    if is_four_three:
        if fb_width >= 1024 and fb_height >= 768:
            width, height = 1024, 768
        else:
            width = clamp(fb_width, 320, 1024)
            height = clamp(fb_height, 240, 768)
        base_width, base_height = 1024, 768
        scale = min(width / base_width, height / base_height)
        compact = width <= 720 or height <= 576
        return {
            "name": "4:3" if not compact else "SD 4:3",
            "width": int(width),
            "height": int(height),
            "scale": scale,
            "card_rect": (32, 32, 992, 736),
            "badge_box": (64, 88, 280, 304),
            "badge_pos": (88, 112),
            "badge_size": 168,
            "text_x": 318,
            "text_y": 70,
            "text_right_margin": 58,
            "divider_right_margin": 58,
            "footer_y": 700,
            "title_size": 48,
            "subtitle_size": 28,
            "small_size": 25,
            "label_size": 28,
            "desc_size": 31,
            "footer_size": 23,
            "title_lines": 2,
            "meta_lines": 2,
            "desc_lines": 4 if not compact else 3,
            "line_gap": 6 if not compact else 4,
            "card_radius": 24,
            "badge_radius": 18,
        }

    if fb_width >= 1280 and fb_height >= 720:
        width, height = 1280, 720
    else:
        width = clamp(fb_width, 426, 1280)
        height = clamp(fb_height, 240, 720)
    base_width, base_height = 1280, 720
    scale = min(width / base_width, height / base_height)
    compact = width <= 854 or height <= 480
    return {
        "name": "16:9" if not compact else "SD 16:9",
        "width": int(width),
        "height": int(height),
        "scale": scale,
        "card_rect": (40, 40, 1240, 680),
        "badge_box": (72, 96, 328, 352),
        "badge_pos": (104, 128),
        "badge_size": 192,
        "text_x": 370,
        "text_y": 82,
        "text_right_margin": 90,
        "divider_right_margin": 100,
        "footer_y": 635,
        "title_size": 60,
        "subtitle_size": 34,
        "small_size": 30,
        "label_size": 34,
        "desc_size": 38,
        "footer_size": 28,
        "title_lines": 2,
        "meta_lines": 2,
        "desc_lines": 4 if not compact else 3,
        "line_gap": 8 if not compact else 5,
        "card_radius": 28,
        "badge_radius": 22,
    }


def scale_rect(rect, scale):
    return tuple(int(round(value * scale)) for value in rect)


def scale_point(point, scale):
    return tuple(int(round(value * scale)) for value in point)


def scale_value(value, scale, minimum=1):
    return max(minimum, int(round(value * scale)))


def find_font(size, bold=False):
    candidates = []
    if bold:
        candidates.extend([
            str(FONT_DIR / "DejaVuSans-Bold.ttf"),
            str(FONT_DIR / "dejavu/DejaVuSans-Bold.ttf"),
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
            "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
        ])
    candidates.extend([
        str(FONT_DIR / "DejaVuSans.ttf"),
        str(FONT_DIR / "dejavu/DejaVuSans.ttf"),
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
        "/usr/share/fonts/dejavu/DejaVuSans.ttf",
    ])
    for path in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size=size)
            except Exception:
                pass
    return ImageFont.load_default()


def draw_wrapped(draw, text, font, x, y, max_width, fill, line_gap=8, max_lines=None):
    text = clean_text(text)
    words = text.split()
    lines = []
    line = ""
    for word in words:
        test = word if not line else line + " " + word
        bbox = draw.textbbox((0, 0), test, font=font)
        width = bbox[2] - bbox[0]
        if width <= max_width:
            line = test
        else:
            if line:
                lines.append(line)
            line = word
    if line:
        lines.append(line)
    if max_lines is not None and len(lines) > max_lines:
        lines = lines[:max_lines]
        if lines:
            lines[-1] = lines[-1].rstrip(".") + "..."
    for line in lines:
        draw.text((x, y), line, font=font, fill=fill)
        bbox = draw.textbbox((0, 0), line, font=font)
        y += (bbox[3] - bbox[1]) + line_gap
    return y


def badge_url(badge_name, unlocked=True):
    if not badge_name:
        return None
    suffix = "" if unlocked else "_lock"
    return f"{RA_MEDIA_BASE}/Badge/{badge_name}{suffix}.png"


def download_file(url, dest, fallback_url=None):
    if dest.exists() and dest.stat().st_size > 0:
        return dest

    def attempt(fetch_url):
        req = urllib.request.Request(fetch_url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = resp.read()
        if not data:
            raise RuntimeError("Downloaded file was empty.")
        with open(dest, "wb") as f:
            f.write(data)

    try:
        attempt(url)
    except Exception:
        if fallback_url and fallback_url != url:
            attempt(fallback_url)
        else:
            raise
    return dest


def render_card(game_id, achievement_id):
    if not PIL_AVAILABLE:
        raise RuntimeError("Python Pillow is not installed, image cards cannot be generated.")
    game = get_game(game_id, force=False)
    achievements = normalize_achievements(game)
    achievement = None
    for a in achievements:
        if str(a.get("ID")) == str(achievement_id):
            achievement = a
            break
    if not achievement:
        raise RuntimeError("Achievement not found.")

    layout = build_card_layout()
    width = layout["width"]
    height = layout["height"]
    scale = layout["scale"]

    unlocked = is_unlocked(achievement)
    badge_name = str(achievement.get("BadgeName", "")).strip()
    badge_image = None
    if badge_name:
        badge_file = BADGE_CACHE / f"{badge_name}{'' if unlocked else '_lock'}.png"
        try:
            download_file(badge_url(badge_name, unlocked=unlocked), badge_file, fallback_url=badge_url(badge_name, unlocked=True))
            badge_image = Image.open(badge_file).convert("RGBA")
        except Exception:
            badge_image = None

    card_file = CARD_CACHE / f"game_{game_id}_achievement_{achievement_id}_{width}x{height}.png"
    img = Image.new("RGB", (width, height), (14, 16, 20))
    draw = ImageDraw.Draw(img)

    card_rect = scale_rect(layout["card_rect"], scale)
    badge_box = scale_rect(layout["badge_box"], scale)
    badge_pos = scale_point(layout["badge_pos"], scale)
    badge_size = scale_value(layout["badge_size"], scale, 48)
    card_radius = scale_value(layout["card_radius"], scale, 8)
    badge_radius = scale_value(layout["badge_radius"], scale, 6)

    card_rect = (
        max(4, card_rect[0]),
        max(4, card_rect[1]),
        min(width - 4, card_rect[2]),
        min(height - 4, card_rect[3]),
    )
    badge_box = (
        max(8, badge_box[0]),
        max(8, badge_box[1]),
        min(width - 8, badge_box[2]),
        min(height - 8, badge_box[3]),
    )

    draw.rounded_rectangle(card_rect, radius=card_radius, fill=(28, 31, 38), outline=(75, 80, 92), width=scale_value(3, scale, 1))
    draw.rounded_rectangle(badge_box, radius=badge_radius, fill=(10, 12, 16), outline=(80, 86, 100), width=scale_value(2, scale, 1))

    if badge_image:
        badge_image = badge_image.resize((badge_size, badge_size), Image.Resampling.LANCZOS)
        img.paste(badge_image, badge_pos, badge_image)
    else:
        no_font = find_font(scale_value(34, scale, 12), bold=True)
        no_text = "NO BADGE"
        bbox = draw.textbbox((0, 0), no_text, font=no_font)
        bx = badge_box[0] + max(0, ((badge_box[2] - badge_box[0]) - (bbox[2] - bbox[0])) // 2)
        by = badge_box[1] + max(0, ((badge_box[3] - badge_box[1]) - (bbox[3] - bbox[1])) // 2)
        draw.text((bx, by), no_text, font=no_font, fill=(220, 220, 220))

    title_font = find_font(scale_value(layout["title_size"], scale, 18), bold=True)
    subtitle_font = find_font(scale_value(layout["subtitle_size"], scale, 13))
    small_font = find_font(scale_value(layout["small_size"], scale, 12))
    label_font = find_font(scale_value(layout["label_size"], scale, 13), bold=True)
    desc_font = find_font(scale_value(layout["desc_size"], scale, 14))
    footer_font = find_font(scale_value(layout["footer_size"], scale, 11))

    x = scale_value(layout["text_x"], scale, badge_box[2] + 12)
    y = scale_value(layout["text_y"], scale, 20)
    right_margin = scale_value(layout["text_right_margin"], scale, 20)
    text_width = max(120, width - x - right_margin)
    line_gap = scale_value(layout["line_gap"], scale, 3)

    y = draw_wrapped(
        draw,
        achievement.get("Title", "Achievement"),
        title_font,
        x,
        y,
        text_width,
        (245, 245, 245),
        line_gap=line_gap,
        max_lines=layout["title_lines"],
    )

    status = achievement_status(achievement)
    points = achievement.get("Points", 0)
    true_ratio = achievement.get("TrueRatio", "")
    ach_type = achievement.get("type") or achievement.get("Type") or "standard"
    meta = f"{status} - {points} pts"
    if true_ratio:
        meta += f" - TrueRatio {true_ratio}"
    meta += f" - {ach_type}"

    y += scale_value(8, scale, 2)
    y = draw_wrapped(
        draw,
        meta,
        subtitle_font,
        x,
        y,
        text_width,
        (204, 210, 222),
        line_gap=max(2, line_gap - 1),
        max_lines=layout["meta_lines"],
    )
    y += scale_value(16, scale, 4)
    divider_right = width - scale_value(layout["divider_right_margin"], scale, 24)
    draw.line((x, y, divider_right, y), fill=(75, 80, 92), width=scale_value(2, scale, 1))
    y += scale_value(24, scale, 6)

    draw.text((x, y), "Description", font=label_font, fill=(245, 245, 245))
    y += scale_value(42, scale, 14)
    y = draw_wrapped(
        draw,
        achievement.get("Description", ""),
        desc_font,
        x,
        y,
        text_width,
        (232, 232, 232),
        line_gap=max(2, line_gap - 1),
        max_lines=layout["desc_lines"],
    )
    y += scale_value(24, scale, 6)

    earned_softcore, earned_hardcore = achievement_dates(achievement)
    date_step = scale_value(42, scale, 16)
    if earned_softcore and y < height - scale_value(120, scale, 44):
        draw.text((x, y), f"Unlocked SC: {earned_softcore}", font=small_font, fill=(204, 210, 222))
        y += date_step
    if earned_hardcore and y < height - scale_value(100, scale, 38):
        draw.text((x, y), f"Unlocked HC: {earned_hardcore}", font=small_font, fill=(204, 210, 222))
        y += date_step

    game_title = clean_text(game.get("Title", "Unknown Game"))
    console = clean_text(game.get("ConsoleName", ""))
    if y < height - scale_value(82, scale, 36):
        y = draw_wrapped(draw, f"Game: {game_title}", small_font, x, y, text_width, (204, 210, 222), line_gap=max(2, line_gap - 2), max_lines=1)
    if console and y < height - scale_value(64, scale, 28):
        y += scale_value(2, scale, 1)
        draw.text((x, y), f"System: {console}", font=small_font, fill=(204, 210, 222))

    footer = "Press A / Enter to return"
    bbox = draw.textbbox((0, 0), footer, font=footer_font)
    footer_y = min(height - scale_value(38, scale, 16), scale_value(layout["footer_y"], scale, height - 40))
    draw.text(((width - (bbox[2] - bbox[0])) // 2, footer_y), footer, font=footer_font, fill=(180, 186, 198))

    img.save(card_file, "PNG")
    return str(card_file)


def show_card(card):
    curses.endwin()
    clear_terminal()
    if not os.path.exists(card):
        print("Achievement card was not created.")
        print()
        print(card)
        print()
        input("Press Enter to return...")
        clear_terminal()
        return
    if shutil.which("fbv"):
        subprocess.run(["fbv", card], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif shutil.which("fbi"):
        subprocess.run(["fbi", "-T", "1", "-d", "/dev/fb0", "-a", "-noverbose", card], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        print("Achievement card created, but no framebuffer image viewer was found.")
        print()
        print(card)
        print()
        input("Press Enter to return...")
    clear_terminal()


def safe_add(stdscr, y, x, text, attr=0):
    h, w = stdscr.getmaxyx()
    if y < 0 or y >= h or x >= w:
        return
    text = clean_text(text)
    max_len = max(0, w - x - 1)
    if max_len <= 0:
        return
    try:
        stdscr.addstr(y, x, text[:max_len], attr)
    except curses.error:
        pass


def safe_add_center(stdscr, y, text, attr=0, max_width=None):
    h, w = stdscr.getmaxyx()
    text = clean_text(text)
    if max_width:
        text = text[:max_width]
    x = max(0, (w - len(text)) // 2)
    safe_add(stdscr, y, x, text, attr)


def wait_message(stdscr, title, lines):
    while True:
        stdscr.clear()
        h, w = stdscr.getmaxyx()
        box_w = min(90, max(44, w - 4))
        x = max(0, (w - box_w) // 2)
        y = 1
        safe_add_center(stdscr, y, title, curses.A_BOLD, box_w)
        y += 2
        for line in lines:
            safe_add(stdscr, y, x, line)
            y += 1
            if y >= h - 3:
                break
        safe_add_center(stdscr, h - 2, "A/Enter = Continue | B/Esc/Q = Back")
        stdscr.refresh()
        key = stdscr.getch()
        if key in (10, 13, 27, ord("q"), ord("Q"), curses.KEY_ENTER):
            return


def loading(stdscr, text):
    stdscr.clear()
    h, w = stdscr.getmaxyx()
    y = max(2, h // 2 - 1)
    safe_add_center(stdscr, y, text, curses.A_BOLD)
    safe_add_center(stdscr, y + 2, "Please wait...")
    stdscr.refresh()


def list_menu(stdscr, title, rows, subtitle=""):
    selected = 0
    top = 0
    while True:
        stdscr.clear()
        h, w = stdscr.getmaxyx()
        menu_w = min(96, max(44, w - 4))
        x = max(0, (w - menu_w) // 2)
        title_y = 1
        subtitle_y = 2
        list_y = 4 if subtitle else 3
        footer_y = h - 2
        visible_h = max(1, footer_y - list_y - 1)
        if selected < top:
            top = selected
        if selected >= top + visible_h:
            top = selected - visible_h + 1
        safe_add_center(stdscr, title_y, title, curses.A_BOLD, menu_w)
        if subtitle:
            safe_add_center(stdscr, subtitle_y, subtitle, 0, menu_w)
        for idx in range(top, min(len(rows), top + visible_h)):
            tag, label = rows[idx]
            attr = curses.A_REVERSE if idx == selected else 0
            safe_add(stdscr, list_y + idx - top, x, label, attr)
        safe_add_center(stdscr, footer_y, "Up/Down = Navigate | A/Enter = Select | B/Esc/Q = Back")
        stdscr.refresh()
        key = stdscr.getch()
        if key in (curses.KEY_UP, ord("w"), ord("W"), ord("k"), ord("K")):
            selected = max(0, selected - 1)
        elif key in (curses.KEY_DOWN, ord("s"), ord("S"), ord("j"), ord("J")):
            selected = min(len(rows) - 1, selected + 1)
        elif key in (10, 13, curses.KEY_ENTER):
            if rows:
                return rows[selected][0]
        elif key in (27, ord("q"), ord("Q"), curses.KEY_BACKSPACE, 127, 8):
            return None


def setup_or_exit(stdscr):
    username, api_key = read_config()
    if username and api_key:
        return
    if not CONFIG.exists():
        create_config_template()
    wait_message(stdscr, "Setup Required", [
        "RetroAchievements Viewer needs your username and Web API key.",
        "", "A config template has been created here:", str(CONFIG), "",
        "Edit it manually or use MiSTer Companion.", "",
        "[retroachievements]", "username=YourUsername", "api_key=YourWebApiKey", "",
        "After saving the file, run this script again.",
    ])
    sys.exit(0)


def main_menu(stdscr):
    while True:
        choice = list_menu(stdscr, "RetroAchievements Viewer By Anime0t4ku", [
            ("games", "View My Games"),
            ("recent", "Recently Played / Updated"),
            ("refresh", "Refresh My Games Cache"),
            ("settings", "Settings / Info"),
            ("exit", "Exit"),
        ])
        if not choice or choice == "exit":
            return
        if choice == "games":
            games_menu(stdscr, "all")
        elif choice == "recent":
            games_menu(stdscr, "recent")
        elif choice == "refresh":
            loading(stdscr, "Refreshing RetroAchievements game cache")
            try:
                get_games(force=True)
                wait_message(stdscr, "Done", ["Game cache refreshed."])
            except Exception as e:
                wait_message(stdscr, "Error", str(e).splitlines())
        elif choice == "settings":
            settings_menu(stdscr)


def settings_menu(stdscr):
    username, _ = read_config()
    while True:
        choice = list_menu(stdscr, "Settings / Info", [
            ("info", "Show config file location"),
            ("display", "Show detected display/card size"),
            ("test", "Test API connection"),
            ("clear", "Clear cache"),
            ("back", "Back"),
        ], f"Current user: {username or 'not configured'}")
        if not choice or choice == "back":
            return
        if choice == "info":
            wait_message(stdscr, "Config Info", ["Config file:", str(CONFIG), "", "Use MiSTer Companion or edit this file manually:", "", "[retroachievements]", "username=YourUsername", "api_key=YourWebApiKey"])
        elif choice == "display":
            fb_width, fb_height = detect_framebuffer_size()
            layout = build_card_layout()
            wait_message(stdscr, "Detected Display", [
                f"Framebuffer: {fb_width or 'unknown'}x{fb_height or 'unknown'}",
                f"Card layout: {layout.get('name')}",
                f"Card size: {layout.get('width')}x{layout.get('height')}",
                f"Scale: {layout.get('scale'):.2f}",
                "",
                "The card renderer chooses this automatically.",
            ])
        elif choice == "test":
            loading(stdscr, "Testing RetroAchievements API")
            try:
                username, api_key = read_config()
                data = api_get("API_GetUserCompletionProgress.php", {"y": api_key, "u": username, "c": 1, "o": 0})
                wait_message(stdscr, "API Test Successful", [f"Username: {username}", f"Games found: {data.get('Total', 0)}"])
            except Exception as e:
                wait_message(stdscr, "API Test Failed", str(e).splitlines())
        elif choice == "clear":
            if CACHE.exists():
                shutil.rmtree(CACHE)
            for p in (CACHE, GAME_CACHE, BADGE_CACHE, CARD_CACHE):
                p.mkdir(parents=True, exist_ok=True)
            wait_message(stdscr, "Done", ["Cache cleared."])


def games_menu(stdscr, mode):
    loading(stdscr, "Loading RetroAchievements games")
    try:
        payload = get_games(force=False)
        games = payload.get("Results", [])
    except Exception as e:
        wait_message(stdscr, "Error", str(e).splitlines())
        return
    if mode == "recent":
        games = sorted(games, key=lambda g: str(g.get("MostRecentAwardedDate") or g.get("LastUpdated") or g.get("Updated") or ""), reverse=True)
    else:
        games = sorted(games, key=lambda g: str(g.get("Title", "")).lower())
    rows = []
    for g in games:
        game_id = g.get("GameID") or g.get("ID")
        if not game_id:
            continue
        title = short_text(g.get("Title", f"Game {game_id}"), 42)
        console = short_text(g.get("ConsoleName", ""), 16)
        awarded = g.get("NumAwarded")
        awarded_hc = g.get("NumAwardedHardcore")
        max_possible = g.get("MaxPossible")
        progress = ""
        if awarded is not None and awarded_hc is not None and max_possible is not None:
            progress = f"ALL {awarded}/{max_possible} | HC {awarded_hc}/{max_possible}"
        elif awarded is not None and max_possible is not None:
            progress = f"ALL {awarded}/{max_possible}"
        elif awarded_hc is not None and max_possible is not None:
            progress = f"HC {awarded_hc}/{max_possible}"
        label = title
        if console:
            label += f" [{console}]"
        if progress:
            label += f" - {progress}"
        rows.append((str(game_id), label))
    if not rows:
        wait_message(stdscr, "No Games", ["No games found."])
        return
    while True:
        game_id = list_menu(stdscr, "Select Game", rows, "A/Enter = show achievements")
        if not game_id:
            return
        achievements_menu(stdscr, game_id)


def achievements_menu(stdscr, game_id):
    loading(stdscr, "Loading achievements")
    try:
        game_data = get_game(game_id, force=False)
        achievements = normalize_achievements(game_data)
    except Exception as e:
        wait_message(stdscr, "Error", str(e).splitlines())
        return
    rows = []
    for a in achievements:
        ach_id = a.get("ID")
        if not ach_id:
            continue
        mark = achievement_mark(a)
        title = short_text(a.get("Title", f"Achievement {ach_id}"), 46)
        points = a.get("Points", 0)
        status = achievement_status(a)
        rows.append((str(ach_id), f"{mark} {title} - {points} pts - {status}"))
    if not rows:
        wait_message(stdscr, "No Achievements", ["No achievements found for this game."])
        return
    while True:
        ach_id = list_menu(stdscr, "Select Achievement", rows, "[S]=softcore | [H]=hardcore | A/Enter = render card")
        if not ach_id:
            return
        achievement_detail(stdscr, game_id, ach_id)


def achievement_detail(stdscr, game_id, ach_id):
    loading(stdscr, "Rendering achievement card")
    try:
        card = render_card(game_id, ach_id)
        show_card(card)
    except Exception as e:
        wait_message(stdscr, "Card Error", str(e).splitlines())


def app(stdscr):
    curses.curs_set(0)
    stdscr.keypad(True)
    stdscr.timeout(-1)
    setup_or_exit(stdscr)
    main_menu(stdscr)


if __name__ == "__main__":
    try:
        curses.wrapper(app)
    except SystemExit:
        raise
    except Exception:
        with open(ERROR_LOG, "w", encoding="utf-8") as f:
            traceback.print_exc(file=f)
        raise
PYEOF

chmod 700 "$HELPER" 2>/dev/null

DID_SETUP=0

show_text_error() {
    clear
    echo "$1"
    echo
    if [ -n "$2" ] && [ -f "$2" ]; then
        tail -n 30 "$2"
        echo
        echo "Full log:"
        echo "$2"
    fi
    echo
    echo "Press Enter to close..."
    read dummy
}

show_dialog_error() {
    MSG="$1"
    FILE="$2"
    if command -v dialog >/dev/null 2>&1; then
        ERROR_TEXT=""
        if [ -n "$FILE" ] && [ -f "$FILE" ]; then
            ERROR_TEXT="$(tail -n 30 "$FILE" 2>/dev/null)"
        fi
        dialog --clear --no-shadow --backtitle "$TITLE" --title "$TITLE" --msgbox "$MSG\n\n$ERROR_TEXT\n\nFull log:\n$FILE" 24 78
        clear
    else
        show_text_error "$MSG" "$FILE"
    fi
}

download_file_to() {
    URL="$1"
    OUT="$2"
    rm -f "$OUT"
    if command -v curl >/dev/null 2>&1; then
        curl -k -L "$URL" -o "$OUT" >>"$PIP_LOG" 2>&1
        return $?
    fi
    if command -v wget >/dev/null 2>&1; then
        wget --no-check-certificate -O "$OUT" "$URL" >>"$PIP_LOG" 2>&1
        return $?
    fi
    echo "Neither curl nor wget is available." >>"$PIP_LOG"
    return 1
}

extract_deb_library() {
    DEB="$1"
    TARGET_DIR="$2"
    LIB_NAME="$3"
    EXTRACT_DIR="$TMP_DIR/deb_extract"
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"
    if command -v ar >/dev/null 2>&1; then
        (cd "$EXTRACT_DIR" || exit 1; ar x "$DEB" >>"$PIP_LOG" 2>&1)
    else
        echo "ar command not found. Cannot extract deb package." >>"$PIP_LOG"
        return 1
    fi
    DATA_ARCHIVE=""
    for f in "$EXTRACT_DIR"/data.tar.*; do
        if [ -f "$f" ]; then
            DATA_ARCHIVE="$f"
            break
        fi
    done
    if [ -z "$DATA_ARCHIVE" ]; then
        echo "No data archive found inside deb package." >>"$PIP_LOG"
        return 1
    fi
    mkdir -p "$EXTRACT_DIR/data"
    tar -xf "$DATA_ARCHIVE" -C "$EXTRACT_DIR/data" >>"$PIP_LOG" 2>&1 || return 1
    FOUND_FILE="$(find "$EXTRACT_DIR/data" -name "$LIB_NAME*" -type f 2>/dev/null | head -n 1)"
    FOUND_LINK="$(find "$EXTRACT_DIR/data" -name "$LIB_NAME*" -type l 2>/dev/null | head -n 1)"
    if [ -n "$FOUND_FILE" ]; then
        cp "$FOUND_FILE" "$TARGET_DIR/$LIB_NAME" >>"$PIP_LOG" 2>&1
        return 0
    fi
    if [ -n "$FOUND_LINK" ]; then
        cp -L "$FOUND_LINK" "$TARGET_DIR/$LIB_NAME" >>"$PIP_LOG" 2>&1
        [ -s "$TARGET_DIR/$LIB_NAME" ] && return 0
    fi
    echo "Could not find usable $LIB_NAME inside deb package." >>"$PIP_LOG"
    return 1
}

install_runtime_deb() {
    NAME="$1"
    LIB_NAME="$2"
    DEB_FILE="$3"
    URLS="$4"
    FORCE="$5"
    if [ "$FORCE" = "force" ]; then
        rm -f "$LIB_DIR/$LIB_NAME" "$LIB_DIR/$LIB_NAME."* 2>/dev/null
    fi
    if [ -s "$LIB_DIR/$LIB_NAME" ]; then
        echo "$NAME runtime already available: $LIB_DIR/$LIB_NAME" >>"$PIP_LOG"
        return 0
    fi
    FOUND_DEB=0
    for URL in $URLS; do
        echo "Trying $NAME package: $URL" >>"$PIP_LOG"
        download_file_to "$URL" "$DEB_FILE"
        if [ "$?" -eq 0 ] && [ -s "$DEB_FILE" ]; then
            FOUND_DEB=1
            break
        fi
    done
    [ "$FOUND_DEB" -ne 1 ] && return 1
    extract_deb_library "$DEB_FILE" "$LIB_DIR" "$LIB_NAME" || return 1
    [ -s "$LIB_DIR/$LIB_NAME" ]
}

install_runtime_libraries() {
    install_runtime_deb "libjpeg" "libjpeg.so.62" "$DEB_DIR/libjpeg62-turbo_armhf.deb" "https://ftp.debian.org/debian/pool/main/libj/libjpeg-turbo/libjpeg62-turbo_2.1.5-2_armhf.deb http://ftp.debian.org/debian/pool/main/libj/libjpeg-turbo/libjpeg62-turbo_2.1.5-2_armhf.deb" "" || return 1
    install_runtime_deb "OpenJPEG Bullseye" "libopenjp2.so.7" "$DEB_DIR/libopenjp2-7_bullseye_armhf.deb" "https://deb.debian.org/debian/pool/main/o/openjpeg2/libopenjp2-7_2.4.0-3_armhf.deb https://ftp.debian.org/debian/pool/main/o/openjpeg2/libopenjp2-7_2.4.0-3_armhf.deb http://deb.debian.org/debian/pool/main/o/openjpeg2/libopenjp2-7_2.4.0-3_armhf.deb http://ftp.debian.org/debian/pool/main/o/openjpeg2/libopenjp2-7_2.4.0-3_armhf.deb" "force" || return 1
    install_runtime_deb "XCB Bullseye" "libxcb.so.1" "$DEB_DIR/libxcb1_bullseye_armhf.deb" "https://ftp.debian.org/debian/pool/main/libx/libxcb/libxcb1_1.14-3_armhf.deb https://deb.debian.org/debian/pool/main/libx/libxcb/libxcb1_1.14-3_armhf.deb http://ftp.debian.org/debian/pool/main/libx/libxcb/libxcb1_1.14-3_armhf.deb http://deb.debian.org/debian/pool/main/libx/libxcb/libxcb1_1.14-3_armhf.deb" "force" || return 1
    install_runtime_deb "Xau Bullseye" "libXau.so.6" "$DEB_DIR/libxau6_bullseye_armhf.deb" "https://ftp.debian.org/debian/pool/main/libx/libxau/libxau6_1.0.9-1_armhf.deb https://deb.debian.org/debian/pool/main/libx/libxau/libxau6_1.0.9-1_armhf.deb http://ftp.debian.org/debian/pool/main/libx/libxau/libxau6_1.0.9-1_armhf.deb http://deb.debian.org/debian/pool/main/libx/libxau/libxau6_1.0.9-1_armhf.deb" "force" || return 1
    install_runtime_deb "Xdmcp Bullseye" "libXdmcp.so.6" "$DEB_DIR/libxdmcp6_bullseye_armhf.deb" "https://ftp.debian.org/debian/pool/main/libx/libxdmcp/libxdmcp6_1.1.2-3_armhf.deb https://deb.debian.org/debian/pool/main/libx/libxdmcp/libxdmcp6_1.1.2-3_armhf.deb http://ftp.debian.org/debian/pool/main/libx/libxdmcp/libxdmcp6_1.1.2-3_armhf.deb http://deb.debian.org/debian/pool/main/libx/libxdmcp/libxdmcp6_1.1.2-3_armhf.deb" "force" || return 1
    install_runtime_deb "libmd Bullseye" "libmd.so.0" "$DEB_DIR/libmd0_bullseye_armhf.deb" "https://ftp.debian.org/debian/pool/main/libm/libmd/libmd0_1.0.3-3_armhf.deb https://deb.debian.org/debian/pool/main/libm/libmd/libmd0_1.0.3-3_armhf.deb http://ftp.debian.org/debian/pool/main/libm/libmd/libmd0_1.0.3-3_armhf.deb http://deb.debian.org/debian/pool/main/libm/libmd/libmd0_1.0.3-3_armhf.deb" "force" || return 1
    install_runtime_deb "libbsd Bullseye" "libbsd.so.0" "$DEB_DIR/libbsd0_bullseye_armhf.deb" "https://ftp.debian.org/debian/pool/main/libb/libbsd/libbsd0_0.11.3-1+deb11u1_armhf.deb https://deb.debian.org/debian/pool/main/libb/libbsd/libbsd0_0.11.3-1+deb11u1_armhf.deb http://ftp.debian.org/debian/pool/main/libb/libbsd/libbsd0_0.11.3-1+deb11u1_armhf.deb http://deb.debian.org/debian/pool/main/libb/libbsd/libbsd0_0.11.3-1+deb11u1_armhf.deb" "force" || return 1
    return 0
}

install_fonts() {
    if [ -s "$FONT_DIR/DejaVuSans.ttf" ] && [ -s "$FONT_DIR/DejaVuSans-Bold.ttf" ]; then
        return 0
    fi
    DID_SETUP=1
    FONT_DEB="$DEB_DIR/fonts-dejavu-core.deb"
    for URL in "https://deb.debian.org/debian/pool/main/f/fonts-dejavu/fonts-dejavu-core_2.37-2_all.deb" "https://ftp.debian.org/debian/pool/main/f/fonts-dejavu/fonts-dejavu-core_2.37-2_all.deb" "http://deb.debian.org/debian/pool/main/f/fonts-dejavu/fonts-dejavu-core_2.37-2_all.deb" "http://ftp.debian.org/debian/pool/main/f/fonts-dejavu/fonts-dejavu-core_2.37-2_all.deb"; do
        download_file_to "$URL" "$FONT_DEB"
        [ "$?" -eq 0 ] && [ -s "$FONT_DEB" ] && break
    done
    [ ! -s "$FONT_DEB" ] && return 1
    command -v ar >/dev/null 2>&1 || return 1
    EXTRACT_DIR="$TMP_DIR/font_extract"
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"
    (cd "$EXTRACT_DIR" || exit 1; ar x "$FONT_DEB" >>"$PIP_LOG" 2>&1)
    DATA_ARCHIVE=""
    for f in "$EXTRACT_DIR"/data.tar.*; do
        [ -f "$f" ] && DATA_ARCHIVE="$f" && break
    done
    [ -z "$DATA_ARCHIVE" ] && return 1
    mkdir -p "$EXTRACT_DIR/data"
    tar -xf "$DATA_ARCHIVE" -C "$EXTRACT_DIR/data" >>"$PIP_LOG" 2>&1 || return 1
    REGULAR_FONT="$(find "$EXTRACT_DIR/data" -name "DejaVuSans.ttf" -type f 2>/dev/null | head -n 1)"
    BOLD_FONT="$(find "$EXTRACT_DIR/data" -name "DejaVuSans-Bold.ttf" -type f 2>/dev/null | head -n 1)"
    [ -n "$REGULAR_FONT" ] && cp "$REGULAR_FONT" "$FONT_DIR/DejaVuSans.ttf" >>"$PIP_LOG" 2>&1
    [ -n "$BOLD_FONT" ] && cp "$BOLD_FONT" "$FONT_DIR/DejaVuSans-Bold.ttf" >>"$PIP_LOG" 2>&1
    [ -s "$FONT_DIR/DejaVuSans.ttf" ] && [ -s "$FONT_DIR/DejaVuSans-Bold.ttf" ]
}

run_with_live_log() {
    DESC="$1"
    CMD="$2"
    EXIT_FILE="$BASE/install_exit.code"
    rm -f "$EXIT_FILE"
    (sh -c "$CMD"; echo $? > "$EXIT_FILE") &
    RUN_PID=$!
    if command -v dialog >/dev/null 2>&1; then
        dialog --clear --no-shadow --backtitle "$TITLE" --title "$DESC" --tailbox "$PIP_LOG" 24 78 &
        TAIL_PID=$!
        while kill -0 "$RUN_PID" 2>/dev/null; do sleep 1; done
        kill "$TAIL_PID" 2>/dev/null
        wait "$TAIL_PID" 2>/dev/null
    else
        while kill -0 "$RUN_PID" 2>/dev/null; do clear; echo "$DESC"; echo; tail -n 20 "$PIP_LOG" 2>/dev/null; sleep 2; done
    fi
    wait "$RUN_PID" 2>/dev/null
    RET_CODE="$(cat "$EXIT_FILE" 2>/dev/null)"
    rm -f "$EXIT_FILE"
    [ -z "$RET_CODE" ] && RET_CODE=1
    return "$RET_CODE"
}

test_pillow_import() {
    PYTHONPATH="$PY_LIB:$PIP_BOOTSTRAP:$PYTHONPATH" LD_LIBRARY_PATH="$LIB_DIR:$LD_LIBRARY_PATH" python3 -c "from PIL import Image, ImageDraw, ImageFont" >/dev/null 2>"$PILLOW_TEST"
    return $?
}

clear

if ! command -v python3 >/dev/null 2>&1; then
    show_text_error "Python 3 was not found on this MiSTer." ""
    exit 1
fi

PYTHONPATH="$PY_LIB:$PIP_BOOTSTRAP:$PYTHONPATH" python3 -m py_compile "$HELPER" 2>"$LOG"
RET=$?
if [ "$RET" -ne 0 ]; then
    show_text_error "RetroAchievements Viewer has a Python syntax error." "$LOG"
    exit 1
fi

if ! test_pillow_import; then
    DID_SETUP=1
    echo "=== RetroAchievements Viewer Pillow Install ===" >"$PIP_LOG"
    echo "Date: $(date)" >>"$PIP_LOG"
    echo "Python: $(python3 --version 2>&1)" >>"$PIP_LOG"
    echo "BASE: $BASE" >>"$PIP_LOG"
    echo "PY_LIB: $PY_LIB" >>"$PIP_LOG"
    echo "PIP_BOOTSTRAP: $PIP_BOOTSTRAP" >>"$PIP_LOG"
    echo "LIB_DIR: $LIB_DIR" >>"$PIP_LOG"
    echo "FONT_DIR: $FONT_DIR" >>"$PIP_LOG"
    echo >>"$PIP_LOG"
    cat "$PILLOW_TEST" >>"$PIP_LOG" 2>/dev/null
    if command -v dialog >/dev/null 2>&1; then
        dialog --clear --no-shadow --backtitle "$TITLE" --title "$TITLE" --msgbox "Python Pillow needs to be installed first.\n\nThe script will install Pillow locally, add the missing ARM runtime libraries, and install local TrueType fonts inside:\n\n$BASE\n\nThis does not modify the MiSTer system files.\n\nThis only happens on first run and may take a while." 20 78
        clear
    else
        echo "Python Pillow needs to be installed first."
        echo
        echo "Press Enter to continue..."
        read dummy
    fi
    install_runtime_libraries || { show_dialog_error "Failed to install one or more local runtime libraries." "$PIP_LOG"; exit 1; }
    if ! test_pillow_import; then
        if ! PYTHONPATH="$PIP_BOOTSTRAP:$PYTHONPATH" python3 -m pip --version >/dev/null 2>&1; then
            rm -f "$GET_PIP"
            if command -v curl >/dev/null 2>&1; then
                DOWNLOAD_CMD="curl -k -L https://bootstrap.pypa.io/pip/3.9/get-pip.py -o '$GET_PIP' >>'$PIP_LOG' 2>&1"
            elif command -v wget >/dev/null 2>&1; then
                DOWNLOAD_CMD="wget --no-check-certificate -O '$GET_PIP' https://bootstrap.pypa.io/pip/3.9/get-pip.py >>'$PIP_LOG' 2>&1"
            else
                show_dialog_error "Failed to download get-pip.py." "$PIP_LOG"
                exit 1
            fi
            run_with_live_log "Downloading get-pip.py" "$DOWNLOAD_CMD"
            [ "$?" -ne 0 ] || [ ! -s "$GET_PIP" ] && { show_dialog_error "Failed to download get-pip.py." "$PIP_LOG"; exit 1; }
            BOOTSTRAP_CMD="PYTHONPATH='$PIP_BOOTSTRAP:$PYTHONPATH' python3 '$GET_PIP' --target '$PIP_BOOTSTRAP' --trusted-host pypi.org --trusted-host files.pythonhosted.org --trusted-host bootstrap.pypa.io --no-cache-dir >>'$PIP_LOG' 2>&1"
            run_with_live_log "Installing pip locally" "$BOOTSTRAP_CMD" || { show_dialog_error "Failed to bootstrap pip." "$PIP_LOG"; exit 1; }
        fi
        PILLOW_CMD="PYTHONPATH='$PIP_BOOTSTRAP:$PY_LIB:$PYTHONPATH' LD_LIBRARY_PATH='$LIB_DIR:$LD_LIBRARY_PATH' python3 -m pip install --upgrade --target '$PY_LIB' --extra-index-url https://www.piwheels.org/simple --prefer-binary --only-binary=:all: --trusted-host pypi.org --trusted-host files.pythonhosted.org --trusted-host pypi.python.org --trusted-host www.piwheels.org --no-cache-dir 'Pillow==10.4.0' >>'$PIP_LOG' 2>&1"
        run_with_live_log "Installing Pillow from piwheels" "$PILLOW_CMD" || { show_dialog_error "Failed to install Python Pillow from piwheels." "$PIP_LOG"; exit 1; }
        install_runtime_libraries || { show_dialog_error "Pillow installed, but one or more runtime libraries could not be installed." "$PIP_LOG"; exit 1; }
        test_pillow_import || { cat "$PILLOW_TEST" >>"$PIP_LOG" 2>/dev/null; show_dialog_error "Pillow installed, but Python still cannot import it." "$PIP_LOG"; exit 1; }
    fi
else
    echo "=== RetroAchievements Viewer Startup ===" >"$PIP_LOG"
    echo "Date: $(date)" >>"$PIP_LOG"
    echo "Pillow already available." >>"$PIP_LOG"
fi

install_fonts || show_dialog_error "Pillow is ready, but local TrueType fonts could not be installed.\n\nThe viewer can still run, but large text may fall back to a tiny default font." "$PIP_LOG"

if [ "$DID_SETUP" = "1" ]; then
    if command -v dialog >/dev/null 2>&1; then
        dialog --clear --no-shadow --backtitle "$TITLE" --title "$TITLE" --msgbox "RetroAchievements Viewer is ready.\n\nThe viewer will now start." 9 66
        clear
    else
        echo "RetroAchievements Viewer is ready."
        sleep 2
    fi
fi

PYTHONPATH="$PY_LIB:$PIP_BOOTSTRAP:$PYTHONPATH" LD_LIBRARY_PATH="$LIB_DIR:$LD_LIBRARY_PATH" python3 "$HELPER"
RET=$?
clear
if [ "$RET" -ne 0 ]; then
    echo "RetroAchievements Viewer crashed."
    echo
    [ -f "$LOG" ] && tail -n 25 "$LOG"
    echo
    echo "Full log:"
    echo "$LOG"
    echo
    echo "Press Enter to close..."
    read dummy
fi
exit "$RET"
