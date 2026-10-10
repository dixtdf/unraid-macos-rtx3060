#!/usr/bin/env python3
"""Check working and staged files, including tracked ignored files. Does not scan Git history."""
import ipaddress
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PRIVATE_DIRS = {"local", "build", "media", "backups", "vendor", "private"}
FORBIDDEN_SUFFIXES = {".iso", ".img", ".raw", ".qcow2", ".dmg", ".pkg", ".zip",
                      ".efi", ".aml", ".key", ".pem", ".p12", ".log", ".part", ".vnc", ".rdp"}
PUBLIC_GUIDS = {"7C436110-AB2A-4BBB-A880-FE41995C9F82", "4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14",
                "4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102", "8BE4DF61-93CA-11D2-AA0D-00E098032B8C",
                "00000000-0000-0000-0000-000000000000"}
SENSITIVE_KEYS = {"serial", "mlb", "systemserialnumber", "systemuuid", "rom", "mac",
                  "apple_smc_osk", "password", "vnc_password", "ssh_password", "uuid"}


def candidates(root):
    try:
        top = subprocess.check_output(["git", "-C", str(root), "rev-parse", "--show-toplevel"], stderr=subprocess.DEVNULL).decode().strip()
        if Path(top).resolve() == root.resolve():
            raw = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard"])
            return sorted({root / x.decode("utf-8") for x in raw.split(b"\0") if x})
    except (OSError, subprocess.CalledProcessError):
        pass
    return sorted(p for p in root.rglob("*") if p.is_file()
                  and not any(x in PRIVATE_DIRS | {".git", "__pycache__", ".idea", ".vscode"} for x in p.relative_to(root).parts)
                  and p.suffix not in {".pyc", ".pyo"})


def sensitive_json(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if key.lower() in SENSITIVE_KEYS and item not in ("", None, [], {}, "000000000000"):
                return True
            if sensitive_json(item):
                return True
    elif isinstance(value, list):
        return any(sensitive_json(item) for item in value)
    return False


def scan_text(text, suffix):
    problems = set()
    for item in re.findall(r"(?<![A-Za-z0-9_.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![A-Za-z0-9_.])", text):
        try:
            address = ipaddress.ip_address(item)
            if (address.is_private or address.is_link_local) and not address.is_loopback and item != "0.0.0.0":
                problems.add("private/link-local IP")
        except ValueError:
            pass
    for value in re.findall(r"\b[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\b", text):
        if value.upper() not in PUBLIC_GUIDS:
            problems.add("non-public UUID")
    if re.search(r"\b(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b", text):
        problems.add("filled MAC address")
    if suffix == ".xml":
        for value in re.findall(r"osk=([^\"'\n<>]+)", text):
            if value.strip() and value.strip() != "{{APPLE_SMC_OSK}}":
                problems.add("filled SMC OSK")
    elif re.search(r"osk=[A-Za-z0-9 ()]{64}", text):
        problems.add("filled SMC OSK")
    if suffix == ".json":
        try:
            if sensitive_json(json.loads(text)):
                problems.add("filled private JSON field")
        except ValueError:
            problems.add("invalid JSON")
    if suffix == ".plist":
        try:
            cfg = plistlib.loads(text.encode("utf-8"))
            generic = cfg.get("PlatformInfo", {}).get("Generic", {})
            if any(generic.get(k) for k in ("SystemSerialNumber", "MLB", "SystemUUID")):
                problems.add("filled OpenCore identity")
            if generic.get("ROM", bytes(6)) != bytes(6):
                problems.add("filled OpenCore ROM")
        except (ValueError, plistlib.InvalidFileException):
            problems.add("invalid plist")
    return problems


def scan_file(path, root):
    rel = path.relative_to(root)
    problems = set()
    if any(x in PRIVATE_DIRS for x in rel.parts) or path.name.startswith(".env"):
        problems.add("private path is tracked")
    if path.suffix in FORBIDDEN_SUFFIXES or path.name.endswith(".tar.gz"):
        problems.add("media/binary/credential file")
    if path.is_symlink():
        return problems | {"symlink requires manual review"}
    if not path.exists():
        return problems | {"tracked missing file; stage its deletion first"}
    if path.stat().st_size > 2 * 1024 * 1024:
        return problems | {"oversized file requires manual review"}
    try:
        text = path.read_text(encoding="utf-8-sig")
        if "\0" in text:
            return problems | {"binary content"}
    except UnicodeError:
        return problems | {"non-UTF8/binary content"}
    problems |= scan_text(text, path.suffix)
    if path.suffix == ".md":
        for link in re.findall(r"\[[^\]]*\]\(([^)]+)\)", text):
            if "://" in link or link.startswith(("#", "mailto:")):
                continue
            target = link.split("#", 1)[0]
            if target and not (path.parent / target).is_file():
                problems.add("broken local Markdown link")
    return problems


def staged_problems(path, root):
    """A sanitized worktree must not hide a previously staged secret."""
    spec = ":" + path.relative_to(root).as_posix()
    command = ["git", "-C", str(root)]
    try:
        size = int(subprocess.check_output(command + ["cat-file", "-s", spec], stderr=subprocess.DEVNULL))
        if size > 2 * 1024 * 1024:
            return {"staged oversized file"}
        data = subprocess.check_output(command + ["show", spec], stderr=subprocess.DEVNULL)
    except (OSError, ValueError, subprocess.CalledProcessError):
        return set()  # Not staged, or no local repository.
    try:
        text = data.decode("utf-8-sig")
    except UnicodeError:
        return {"staged binary content"}
    if "\0" in text:
        return {"staged binary content"}
    return {"staged: " + p for p in scan_text(text, path.suffix)}


def main():
    failed = 0
    paths = candidates(ROOT)
    for path in paths:
        problems = scan_file(path, ROOT) | staged_problems(path, ROOT)
        if problems:
            failed += 1
            # Report only filenames/rule labels, never the suspected secret itself.
            print(f"STOP {path.relative_to(ROOT)}: {', '.join(sorted(problems))}")
    if failed:
        print(f"Publication check failed in {failed} files. No upload was performed.")
        return 1
    print(f"PASS: {len(paths)} publishable files checked. Manually review public domains, screenshots and Git history too.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
