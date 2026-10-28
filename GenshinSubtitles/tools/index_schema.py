"""Shared index contract; no desktop or third-party dependencies."""
import argparse
import hashlib
import json
import pathlib
import sqlite3
import sys

SCHEMA_VERSION = "2"


def fingerprints(paths):
    result = []
    for path in map(pathlib.Path, paths):
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        result.append({"name": path.name, "bytes": path.stat().st_size, "sha256": digest.hexdigest()})
    return result


def check_schema(db):
    version = db.execute("SELECT value FROM metadata WHERE key='schema_version'").fetchone()
    if version != (SCHEMA_VERSION,):
        raise ValueError("Outdated index schema; rebuild with prepare-ocr-index.ps1")
    for table, key in (("subtitle", "zh_key"), ("english_subtitle", "en_key")):
        columns = {r[1] for r in db.execute(f"PRAGMA table_info({table})")}
        if not {key, "zh", "en", "text_id"} <= columns:
            raise ValueError(f"Incomplete index table: {table}")


def validate(path, sources, extra_pairs=1):
    with sqlite3.connect(pathlib.Path(path).resolve().as_uri() + "?mode=ro", uri=True) as db:
        check_schema(db)
        metadata = dict(db.execute("SELECT key, value FROM metadata"))
        if metadata.get("extra_pairs") != str(extra_pairs):
            raise ValueError("Index is missing the paired Medium TextMaps")
        if json.loads(metadata["sources"]) != fingerprints(sources):
            raise ValueError("TextMap content has changed; rebuild the index")
        if db.execute("PRAGMA quick_check").fetchone() != ("ok",):
            raise ValueError("SQLite integrity check failed")
        if any(db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0] == 0
               for table in ("subtitle", "english_subtitle")):
            raise ValueError("Empty subtitle index")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--source", action="append", required=True)
    args = parser.parse_args()
    try:
        validate(args.db, args.source)
        print("Index schema, paired sources and integrity: OK")
    except (OSError, sqlite3.Error, ValueError, KeyError) as error:
        print(f"Index needs preparation: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
