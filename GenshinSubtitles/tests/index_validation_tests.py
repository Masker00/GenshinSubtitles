"""Small index-contract regressions independent of downloaded game data."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from index_schema import validate
from lookup_ocr_text import lookup_database

with tempfile.TemporaryDirectory(prefix="genshin index ") as folder:
    directory = pathlib.Path(folder)
    paths = [directory / name for name in ("zh.json", "en.json", "extra-zh.json", "extra-en.json")]
    zh = "#这 是一段 保留空格与标点的测试文本。\n{NICKNAME}"
    en = "#This is a synthetic test line, with spaces.\n{NICKNAME}"
    for path, text in zip(paths, [zh, en, None, None]):
        path.write_text(json.dumps({"123": text} if text else {}, ensure_ascii=False), encoding="utf-8")
    db = directory / "index.sqlite"
    subprocess.run([sys.executable, str(ROOT / "tools/build_ocr_index.py"), "--chs", str(paths[0]), "--en", str(paths[1]),
                    "--chs-extra", str(paths[2]), "--en-extra", str(paths[3]), "--db", str(db)], check=True, capture_output=True)
    validate(db, paths)
    result = lookup_database(db, zh.replace(" ", "").replace("\n", ""))
    assert result["matched"] and result["source"] == zh and result["opposite"] == en
    assert result["text_id"] == "123"
    # Source timestamps/size alone are not sufficient to validate an index.
    before = paths[1].stat()
    paths[1].write_text(paths[1].read_text(encoding="utf-8").replace("synthetic", "Synthetic"), encoding="utf-8")
    os.utime(paths[1], ns=(before.st_atime_ns, before.st_mtime_ns))
    try:
        validate(db, paths)
    except ValueError as error:
        assert "content has changed" in str(error)
    else:
        raise AssertionError("Same-size timestamp-preserving source change was accepted")
    missing = directory / "absent.sqlite"
    try:
        lookup_database(missing, zh)
    except Exception:
        assert not missing.exists()
    else:
        raise AssertionError("Missing database unexpectedly opened")
print("Original text fidelity, content fingerprints and read-only missing database: OK")
