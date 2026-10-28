"""Look up the opposite official subtitle from OCR text."""
import argparse
import base64
import json
import pathlib
import re
import sqlite3
import sys
from difflib import SequenceMatcher


def key(text):
    return re.sub(r"\s+", "", text or "")


def english_key(text):
    return re.sub(r"[^a-z0-9]+", "", (text or "").casefold())


def chinese_fuzzy_key(text):
    # UI prompts, controller hints, and dynamic nicknames are often captured
    # beside a Chinese subtitle. Keep the Han text for fuzzy comparison so
    # those Latin fragments do not drown out the actual dialogue.
    return "".join(re.findall(r"[\u3400-\u4dbf\u4e00-\u9fff]", text or ""))


parser = argparse.ArgumentParser()
parser.add_argument("--db", type=pathlib.Path, required=True)
parser.add_argument("--text-b64")
parser.add_argument("--source", choices=("ZH", "EN"), default="ZH")
parser.add_argument("--format", choices=("text", "json"), default="text")
args = parser.parse_args()
if args.text_b64:
    text = base64.b64decode(args.text_b64).decode("utf-8")
else:
    text = sys.stdin.read()
normalized = english_key(text) if args.source == "EN" else key(text)
with sqlite3.connect(str(args.db)) as db:
    table, column, values = ("english_subtitle", "en_key", "en, zh") if args.source == "EN" else ("subtitle", "zh_key", "en")
    row = db.execute(f"SELECT {values} FROM {table} WHERE {column} = ? LIMIT 1", (normalized,)).fetchone()
    best_score = 1.0 if row else 0.0
    if not row and len(normalized) >= 10:
        # Windows OCR can insert spaces or misread one or two glyphs. Use a
        # long contiguous fragment to narrow the local index, then score only
        # those candidates. The returned text is still the official TextMap.
        search_key = chinese_fuzzy_key(text) if args.source == "ZH" else normalized
        fragment_width = 6 if args.source == "ZH" else 12
        fragments = [search_key[i:i + fragment_width] for i in range(0, len(search_key) - fragment_width + 1)]
        if len(fragments) > 12:
            fragments = [fragments[round(i * (len(fragments) - 1) / 11)] for i in range(12)]
        candidates = {}
        for fragment in fragments:
            for candidate in db.execute(
                f"SELECT {column}, {values} FROM {table} WHERE {column} LIKE ? LIMIT 80",
                (f"%{fragment}%",),
            ):
                candidates[candidate[0]] = candidate[1:]
        best = None
        for candidate_key, candidate_values in candidates.items():
            score_key = chinese_fuzzy_key(candidate_key) if args.source == "ZH" else candidate_key
            input_key = search_key if args.source == "ZH" else normalized
            score = SequenceMatcher(None, input_key, score_key).ratio()
            if args.source == "EN" and len(normalized) >= 25:
                score = max(score, SequenceMatcher(None, normalized, candidate_key[:len(normalized)]).ratio())
            if score > best_score:
                best_score = score
                best = candidate_values
        threshold = 0.82 if args.source == "ZH" else 0.80
        if best is not None and best_score >= threshold:
            row = best
opposite = row[1] if row and args.source == "EN" else row[0] if row else ""
source = row[0] if row and args.source == "EN" and best_score >= 0.9 else ""
if args.format == "json":
    sys.stdout.buffer.write(json.dumps({"source": source, "opposite": opposite}, ensure_ascii=False).encode("utf-8"))
elif opposite:
    sys.stdout.buffer.write(opposite.encode("utf-8"))
