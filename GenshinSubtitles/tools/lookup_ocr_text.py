"""Local official-text lookup. Similarity is a heuristic, not a probability."""
import argparse
import base64
import json
import pathlib
import re
import sqlite3
import sys
from difflib import SequenceMatcher
from contextlib import closing


def key(text):
    return re.sub(r"\s+", "", text or "")


def english_key(text):
    return re.sub(r"[^a-z0-9]+", "", (text or "").casefold())


def chinese_fuzzy_key(text):
    return "".join(re.findall(r"[\u3400-\u4dbf\u4e00-\u9fff]", text or ""))


def lookup_text(db, text, source="ZH"):
    """Accept exact matches or the existing ZH .82 / EN .80 fuzzy thresholds.

    Both languages always come from the same accepted row. Search keys are
    never exposed as official text. Caller owns the SQLite connection.
    """
    if source not in ("ZH", "EN"):
        raise ValueError("source must be ZH or EN")
    normalized = english_key(text) if source == "EN" else key(text)
    table, column = ("english_subtitle", "en_key") if source == "EN" else ("subtitle", "zh_key")
    row = db.execute(f"SELECT zh, en, text_id FROM {table} WHERE {column} = ? LIMIT 1", (normalized,)).fetchone()
    best_score = 1.0 if row else 0.0
    method = "exact" if row else "none"
    if not row and len(normalized) >= 10:
        search_key = chinese_fuzzy_key(text) if source == "ZH" else normalized
        width = 6 if source == "ZH" else 12
        fragments = [search_key[i:i + width] for i in range(len(search_key) - width + 1)]
        if len(fragments) > 12:
            fragments = [fragments[round(i * (len(fragments) - 1) / 11)] for i in range(12)]
        candidates = {}
        for fragment in fragments:
            for candidate in db.execute(
                f"SELECT {column}, zh, en, text_id FROM {table} WHERE {column} LIKE ? LIMIT 80",
                (f"%{fragment}%",),
            ):
                candidates[candidate[0]] = candidate[1:]
        best = None
        for candidate_key, candidate_values in candidates.items():
            score_key = chinese_fuzzy_key(candidate_key) if source == "ZH" else candidate_key
            score = SequenceMatcher(None, search_key, score_key).ratio()
            if source == "EN" and len(normalized) >= 25:
                score = max(score, SequenceMatcher(None, normalized, candidate_key[:len(normalized)]).ratio())
            if score > best_score:
                best_score, best = score, candidate_values
        if best is not None and best_score >= (0.82 if source == "ZH" else 0.80):
            row, method = best, "fuzzy"
    zh, en, text_id = row if row else ("", "", None)
    return {"matched": row is not None, "zh": zh, "en": en, "text_id": text_id,
            "method": method, "similarity": best_score,
            "source": en if source == "EN" else zh,
            "opposite": zh if source == "EN" else en}


def lookup_database(path, text, source="ZH"):
    from index_schema import check_schema
    with closing(sqlite3.connect(pathlib.Path(path).resolve().as_uri() + "?mode=ro", uri=True)) as db:
        check_schema(db)
        return lookup_text(db, text, source)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=pathlib.Path, required=True)
    parser.add_argument("--text-b64")
    parser.add_argument("--source", choices=("ZH", "EN"), default="ZH")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args()
    try:
        text = base64.b64decode(args.text_b64, validate=True).decode("utf-8") if args.text_b64 else sys.stdin.read()
        result = lookup_database(args.db, text, args.source)
        output = json.dumps(result, ensure_ascii=False) if args.format == "json" else result["opposite"]
        sys.stdout.buffer.write(output.encode("utf-8"))
    except (ValueError, OSError, sqlite3.Error) as error:
        print(f"Lookup failed: {error}. Run setup.bat to validate/rebuild the index.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
