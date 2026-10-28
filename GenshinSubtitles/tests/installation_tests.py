"""Dependency/download failure checks in an isolated directory with spaces."""
import json
import os
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SHELL = pathlib.Path(os.environ["SystemRoot"]) / "System32/WindowsPowerShell/v1.0/powershell.exe"


def run(*args, env=None):
    return subprocess.run([str(SHELL), "-NoProfile", "-ExecutionPolicy", "Bypass", *map(str, args)],
                          capture_output=True, timeout=40, env=env, text=True, encoding="utf-8", errors="replace")


with tempfile.TemporaryDirectory(prefix="genshin install spaces ") as folder:
    app = pathlib.Path(folder) / "GenshinSubtitles"
    (app / "data").mkdir(parents=True)
    for name in ("setup.ps1", "resolve-python.ps1", "fetch-data.ps1", "prepare-ocr-index.ps1", "data/sources.json"):
        shutil.copyfile(ROOT / name, app / name)
    env = dict(os.environ, GENSHIN_SUBTITLES_PYTHON=str(app / "missing python.exe"))
    failed = run("-File", app / "setup.ps1", env=env)
    assert failed.returncode != 0 and "Python 3.9+" in failed.stdout, (failed.stdout, failed.stderr)
    missing = run("-File", app / "prepare-ocr-index.ps1", "-CheckOnly")
    assert missing.returncode != 0
    # Simulate unavailable fixed sources without changing URLs or contacting a substitute host.
    textmap = app / "data/TextMapCHS.json"
    textmap.write_bytes(b"partial invalid data")
    fetch_path = str(app / "fetch-data.ps1").replace("'", "''")
    failed = run("-Command", "$ErrorActionPreference='Stop'; function curl.exe { $global:LASTEXITCODE=22 }; & '" + fetch_path + "'")
    assert failed.returncode != 0 and "Download failed or timed out" in failed.stderr, (failed.stdout, failed.stderr)
    backups = list((app / "data").glob("TextMapCHS.json.invalid-*"))
    assert len(backups) == 1 and backups[0].read_bytes() == b"partial invalid data"
    assert not textmap.exists() and not (app / "data/subtitles-ocr.sqlite").exists()
    assert not (app.parent / ".local/data-receipt.json").exists()
    assert len(json.loads((app / "data/sources.json").read_text())["files"]) == 4
print("Missing Python/data and partial-download failure preserve useful errors and do not report success: OK")
