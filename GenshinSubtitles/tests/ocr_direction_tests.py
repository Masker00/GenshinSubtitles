"""Verify both directions of the local official-text OCR lookup."""
import base64
import json
import pathlib
import shutil
import subprocess
import sys
import uuid


root = pathlib.Path(__file__).resolve().parents[1]
zh = "总之，收集克什尼克晶矿，我就可以提取其中的能量，维持您体表的温度。"
en = (
    "But for now, all you need to remember is this: If you collect Kresnik Kristall, "
    "I can extract the energy within and keep your body temperature stable."
)
medium_zh = "嘿，你好，你知道万叶在哪里吗？"
medium_en = "Hey, hello! Do you know where Kazuha is?"
prompt_zh = "#干得漂亮，{NICKNAME}！我很早就进言，想让女皇参加一次茶会。"
prompt_en = "#Well done, {NICKNAME}! I've been trying to get Her Majesty to attend a tea party for ages!"
prompt_ocr = "干得漂亮，PLAYER#（PU)(P!我很早就进言，想让女生参加一次茶会。"


def run(*args):
    return subprocess.run(
        [sys.executable, *map(str, args)],
        cwd=root,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    ).stdout


test_temp_root = root / "test-results"
test_temp_root.mkdir(exist_ok=True)
folder = test_temp_root / ("ocr-direction-" + uuid.uuid4().hex)
folder.mkdir()
try:
    chs = folder / "TextMapCHS.json"
    english = folder / "TextMapEN.json"
    db = folder / "subtitles-ocr.sqlite"
    chs.write_text(json.dumps({"1": zh, "2": prompt_zh}, ensure_ascii=False), encoding="utf-8")
    english.write_text(json.dumps({"1": en, "2": prompt_en}), encoding="utf-8")
    run(root / "tools/build_ocr_index.py", "--chs", chs, "--en", english, "--db", db)

    def lookup(source, text, output_format="text"):
        encoded = base64.b64encode(text.encode("utf-8")).decode("ascii")
        return run(root / "tools/lookup_ocr_text.py", "--db", db, "--source", source, "--format", output_format, "--text-b64", encoded)

    assert lookup("ZH", zh) == en
    assert lookup("EN", en) == zh
    assert lookup("EN", en.upper().replace(",", "")) == zh
    assert lookup("EN", "But for now, all yo u need to remember is this: If yo u collect Kresnik Kristall") == zh
    corrected = json.loads(lookup("EN", en.replace("now", "n0w") + " 0", "json"))
    assert corrected == {"source": en, "opposite": zh}
    assert lookup("EN", "unrelated English subtitle with no official match") == ""
    assert lookup("ZH", prompt_ocr) == prompt_en
    assert lookup("ZH", "我很早就进言但是内容完全无关别的事情") == ""
    assert json.loads(lookup("EN", "unrelated English subtitle with no official match", "json")) == {"source": "", "opposite": ""}
    assert lookup("ZH", medium_zh) == ""
    chs_extra = folder / "TextMap_MediumCHS.json"
    en_extra = folder / "TextMap_MediumEN.json"
    chs_extra.write_text(json.dumps({"2545425690": medium_zh}, ensure_ascii=False), encoding="utf-8")
    en_extra.write_text(json.dumps({"2545425690": medium_en}), encoding="utf-8")
    build_args = (root / "tools/build_ocr_index.py", "--chs", chs, "--en", english,
                  "--chs-extra", chs_extra, "--en-extra", en_extra, "--db", db)
    run(*build_args)
    assert lookup("ZH", " ".join(medium_zh)) == medium_en
    assert lookup("EN", medium_en) == medium_zh
    assert lookup("ZH", zh) == en
    assert lookup("EN", en) == zh
    # Reject mixed/conflicting sources before touching the existing index.
    chs_extra.write_text(json.dumps({"1": medium_zh}), encoding="utf-8")
    try:
        run(*build_args)
    except subprocess.CalledProcessError as error:
        assert "Conflicting text IDs" in error.stderr
    else:
        raise AssertionError("Conflicting TextMap IDs were silently overwritten")
    assert lookup("ZH", medium_zh) == medium_en
    try:
        run(root / "tools/build_ocr_index.py", "--chs", chs, "--en", english,
            "--chs-extra", chs_extra, "--db", db)
    except subprocess.CalledProcessError as error:
        assert "matching English TextMap" in error.stderr
    else:
        raise AssertionError("An unpaired extra TextMap was accepted")
finally:
    shutil.rmtree(folder)
print("OCR direction tests passed")

real_db = root / "data/subtitles-ocr.sqlite"
if real_db.exists():
    screenshot_ocr = "But for now, all yo u need to remember is this: If yo u collect Kresnik KristaII, can extract"
    encoded = base64.b64encode(screenshot_ocr.encode("utf-8")).decode("ascii")
    result = run(root / "tools/lookup_ocr_text.py", "--db", real_db, "--source", "EN", "--text-b64", encoded)
    assert "克什尼克晶矿" in result, "real TextMap did not match the observed English OCR fragment"
    print("Real TextMap English-to-Chinese OCR sample passed")
    screenshot = "Hmm... I hope things really d0 go smoothly over in Snezhnograd.. 0"
    encoded = base64.b64encode(screenshot.encode("utf-8")).decode("ascii")
    record = json.loads(run(root / "tools/lookup_ocr_text.py", "--db", real_db, "--source", "EN", "--format", "json", "--text-b64", encoded))
    assert record["source"] == "Hmm... I hope things really do go smoothly over in Snezhnograd..."
    assert record["opposite"], "screenshot OCR did not match official Chinese"
    print("Screenshot English OCR correction passed")
    for source, text, expected in (("ZH", " ".join(medium_zh), medium_en), ("EN", medium_en, medium_zh)):
        encoded = base64.b64encode(text.encode("utf-8")).decode("ascii")
        result = run(root / "tools/lookup_ocr_text.py", "--db", real_db, "--source", source, "--text-b64", encoded)
        assert result == expected, "Kazuha story quest dialogue missing from real index"
    print("Real TextMap Medium Kazuha dialogue passed in both directions")
    encoded = base64.b64encode(prompt_ocr.encode("utf-8")).decode("ascii")
    result = run(root / "tools/lookup_ocr_text.py", "--db", real_db, "--source", "ZH", "--text-b64", encoded)
    assert result == prompt_en, "UI prompt and nickname polluted Chinese OCR did not match"
    print("Chinese OCR with nickname and controller prompt passed")
