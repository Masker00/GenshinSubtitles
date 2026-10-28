"""Build/verify a public-source package from an explicit, reviewable allowlist."""
import argparse
import hashlib
import json
import pathlib
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


def allowed_files():
    names = [line.strip() for line in (ROOT / "release-files.txt").read_text(encoding="utf-8").splitlines()
             if line.strip() and not line.startswith("#")]
    if len(names) != len(set(names)):
        raise ValueError("Duplicate allowlist entries")
    for name in names:
        path = pathlib.PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or "\\" in name or ":" in name:
            raise ValueError(f"Unsafe package path: {name}")
        resolved = (ROOT / name).resolve()
        if not resolved.is_relative_to(ROOT) or not resolved.is_file() or (ROOT / name).is_symlink():
            raise ValueError(f"Missing file or unsafe symlink: {name}")
        if any(part in {"archive", ".git", ".local", "test-results", "__pycache__", ".venv", "runtime"} for part in path.parts):
            raise ValueError(f"Private/local directory in allowlist: {name}")
        if ("data" in path.parts and name != "GenshinSubtitles/data/sources.json") or path.name in {"game-path.txt", "overlay-settings.json", "PROJECT_HANDOFF.md", "MIGRATION.md"} or path.suffix in {".log", ".sqlite", ".zip"}:
            raise ValueError(f"Private payload in allowlist: {name}")
    return sorted(names)


def verify(archive):
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:
            raise ValueError("ZIP CRC check failed")
        manifest = json.loads(z.read("PACKAGE.json"))
        expected = {entry["path"] for entry in manifest["files"]} | {"PACKAGE.json"}
        if len(z.namelist()) != len(expected) or set(z.namelist()) != expected:
            raise ValueError("ZIP file list differs from manifest")
        if expected != set(allowed_files()) | {"PACKAGE.json"}:
            raise ValueError("ZIP file list differs from reviewed public allowlist")
        for entry in manifest["files"]:
            payload = z.read(entry["path"])
            if len(payload) != entry["bytes"] or hashlib.sha256(payload).hexdigest() != entry["sha256"]:
                raise ValueError(f"Payload mismatch: {entry['path']}")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum = archive.with_suffix(archive.suffix + ".sha256")
    if checksum.exists() and checksum.read_text().split()[0] != digest:
        raise ValueError("ZIP SHA-256 mismatch")
    return {"zip": str(archive), "files": len(expected), "sha256": digest, "status": manifest["status"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--output", type=pathlib.Path)
    group.add_argument("--verify", type=pathlib.Path)
    parser.add_argument("--require-final-license", action="store_true")
    args = parser.parse_args()
    if args.verify:
        print(json.dumps(verify(args.verify.resolve()), ensure_ascii=True))
        return
    pending = "LICENSING PENDING" in (ROOT / "LICENSE").read_text()
    if pending and args.require_final_license:
        raise ValueError("Final license/attribution are pending; public release is not authorized")
    output = args.output.resolve()
    if output.exists():
        raise FileExistsError("Output already exists; choose a new filename")
    output.parent.mkdir(parents=True, exist_ok=True)
    manifest = {"version": (ROOT / "VERSION").read_text().strip(),
                "status": "local-review-licensing-pending" if pending else "source-package",
                "files": []}
    temporary = output.with_suffix(output.suffix + ".tmp")
    try:
        with zipfile.ZipFile(temporary, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
            for name in allowed_files():
                payload = (ROOT / name).read_bytes()
                manifest["files"].append({"path": name, "bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()})
                info = zipfile.ZipInfo(name, (2026, 10, 28, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                z.writestr(info, payload)
            z.writestr("PACKAGE.json", json.dumps(manifest, ensure_ascii=True, indent=2).encode())
        temporary.rename(output)
    finally:
        if temporary.exists():
            temporary.unlink()
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(output.suffix + ".sha256").write_text(f"{digest}  {output.name}\n", encoding="ascii")
    print(json.dumps(verify(output), ensure_ascii=True))


if __name__ == "__main__":
    main()
