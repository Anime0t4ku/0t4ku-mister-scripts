import json
import os
import sys
import time
import zipfile
import hashlib
import re
from pathlib import Path


REPO_RAW_BASE = os.environ.get("REPO_RAW_BASE", "").rstrip("/")


def md5_file(path: Path) -> str:
    h = hashlib.md5()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def build_db(source_dir: str, output_zip: str):
    source = Path(source_dir)
    if not source.exists():
        raise FileNotFoundError(f"Source folder not found: {source_dir}")

    files = {}

    for file_path in sorted(source.rglob("*")):
        if not file_path.is_file():
            continue

        rel_path = file_path.relative_to(source).as_posix()

        mister_path = f"Scripts/{rel_path}"

        raw_url = f"{REPO_RAW_BASE}/{source.name}/{rel_path}"

        script_name = re.sub(r"[^a-z0-9]", "", file_path.stem.lower())
        tags = ["scripts", script_name]

        files[mister_path] = {
            "hash": md5_file(file_path),
            "size": file_path.stat().st_size,
            "url": raw_url,
            "tags": tags
        }

    db = {
        "base_files_url": "",
        "db_files": [],
        "db_id": "anime0t4ku_mister_scripts",
        "default_options": {},
        "files": files,
        "folders": {
            "Scripts": {
                "tags": ["scripts"]
            }
        },
        "timestamp": int(time.time()),
        "zips": {}
    }

    output_zip_path = Path(output_zip)
    output_zip_path.parent.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(output_zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("db.json", json.dumps(db, indent=2, sort_keys=True))

    print(f"Built {output_zip_path}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python build_script_db.py <source_dir> <output_zip>")
        sys.exit(1)

    build_db(sys.argv[1], sys.argv[2])