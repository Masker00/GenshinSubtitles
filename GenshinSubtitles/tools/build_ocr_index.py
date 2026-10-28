"""Build a local exact-text lookup index for the external OCR overlay."""
import argparse
import json
import pathlib
import re
import sqlite3


def key(text):
    return re.sub(r"\s+", "", text or "")


def english_key(text):
    return re.sub(r"[^a-z0-9]+", "", (text or "").casefold())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--chs", type=pathlib.Path, required=True)
    parser.add_argument("--en", type=pathlib.Path, required=True)
    parser.add_argument("--chs-extra", type=pathlib.Path, action="append", default=[])
    parser.add_argument("--en-extra", type=pathlib.Path, action="append", default=[])
    parser.add_argument("--db", type=pathlib.Path, required=True)
    args = parser.parse_args()
    if len(args.chs_extra) != len(args.en_extra):
        parser.error("Each extra Chinese TextMap requires a matching English TextMap.")
    chs = json.loads(args.chs.read_text(encoding="utf-8"))
    eng = json.loads(args.en.read_text(encoding="utf-8"))
    for chs_path, en_path in zip(args.chs_extra, args.en_extra):
        for target, path in ((chs, chs_path), (eng, en_path)):
            extra = json.loads(path.read_text(encoding="utf-8"))
            conflicts = [text_id for text_id, value in extra.items()
                         if text_id in target and target[text_id] != value]
            if conflicts:
                raise ValueError(f"Conflicting text IDs in {path}: {conflicts[:5]}")
            target.update(extra)
    args.db.parent.mkdir(parents=True, exist_ok=True)
    temp = args.db.with_suffix(args.db.suffix + ".tmp")
    if temp.exists():
        temp.unlink()
    db = sqlite3.connect(str(temp))
    try:
        db.execute("PRAGMA journal_mode=OFF")
        db.execute("PRAGMA synchronous=OFF")
        db.execute("CREATE TABLE subtitle (zh_key TEXT PRIMARY KEY, en TEXT NOT NULL, text_id TEXT NOT NULL)")
        db.execute("CREATE TABLE english_subtitle (en_key TEXT PRIMARY KEY, en TEXT NOT NULL, zh TEXT NOT NULL, text_id TEXT NOT NULL)")
        db.execute("CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        db.execute("INSERT INTO metadata VALUES ('extra_pairs', ?)", (str(len(args.chs_extra)),))
        rows = []
        english_rows = []
        for text_id, zh in chs.items():
            en = eng.get(text_id)
            normalized = key(zh)
            if not normalized or not en:
                continue
            if len(normalized) > 10:
                rows.append((normalized, en, str(text_id)))
            en_normalized = english_key(en)
            if len(en_normalized) > 10:
                english_rows.append((en_normalized, en, zh, str(text_id)))
            if len(rows) >= 5000:
                db.executemany("INSERT OR IGNORE INTO subtitle VALUES (?, ?, ?)", rows)
                rows.clear()
            if len(english_rows) >= 5000:
                db.executemany("INSERT OR IGNORE INTO english_subtitle VALUES (?, ?, ?, ?)", english_rows)
                english_rows.clear()
        if rows:
            db.executemany("INSERT OR IGNORE INTO subtitle VALUES (?, ?, ?)", rows)
        if english_rows:
            db.executemany("INSERT OR IGNORE INTO english_subtitle VALUES (?, ?, ?, ?)", english_rows)
        db.execute("CREATE INDEX subtitle_text_id ON subtitle(text_id)")
        db.commit()
        count = db.execute("SELECT COUNT(*) FROM subtitle").fetchone()[0]
        english_count = db.execute("SELECT COUNT(*) FROM english_subtitle").fetchone()[0]
    finally:
        db.close()
    temp.replace(args.db)
    print(json.dumps({"database": str(args.db), "zh_entries": count, "en_entries": english_count}, ensure_ascii=True))


if __name__ == "__main__":
    main()
