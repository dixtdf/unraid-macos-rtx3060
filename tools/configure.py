#!/usr/bin/env python3
"""Build private OpenCore/libvirt files locally; never operate a host or VM."""
import argparse
import copy
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / "local"
APPLE_GUID = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
QEMU_NS = "http://libvirt.org/schemas/domain/qemu/1.0"
ET.register_namespace("qemu", QEMU_NS)
BASE_ARGS = "-v keepsyms=1 debug=0x100 -vsmccomp"
GPU_ARGS = ("-v keepsyms=1 debug=0x100 nvfb=1 nvaccel=1 nvfbheads=4 "
            "-nvkmsnosmooth amfi_get_out_of_my_way=0x1 amfi=0x80 -vsmccomp")


def private_path(value):
    raw = Path(value).absolute()
    if LOCAL.resolve() != LOCAL.absolute() or LOCAL.is_symlink() or any(x.is_symlink() for x in (raw, *raw.parents)
                                 if x.is_relative_to(LOCAL)):
        raise ValueError("Symlinks are not supported in private input/output paths")
    p = raw.resolve()
    if not p.is_relative_to(LOCAL.resolve()) or p == LOCAL.resolve():
        raise ValueError("Private input/output must be inside this repository's local/ directory")
    return p


def write_private(path, data, force=False):
    path = private_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and not force:
        raise ValueError("Output already exists; keep a backup before using --force")
    # O_EXCL prevents silent overwrite; --force is an explicit replacement.
    flags = os.O_WRONLY | os.O_CREAT | (os.O_TRUNC if force else os.O_EXCL)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(data)


def bdf_parts(value):
    if not re.fullmatch(r"[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]", value):
        raise ValueError("BDF must use lowercase domain:bus:slot.function format")
    domain, bus, sf = value.split(":")
    slot, function = sf.split(".")
    if int(slot, 16) > 31:
        raise ValueError("PCI slot must be <= 1f")
    return {"domain": "0x" + domain, "bus": "0x" + bus,
            "slot": "0x" + slot, "function": "0x" + function}


def validate(settings, require_osk=False):
    vm, identity = settings["vm"], settings["identity"]
    if settings.get("schema") != 1:
        raise ValueError("Unsupported settings schema")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}", vm["name"]):
        raise ValueError("Use a simple VM name with letters, numbers, dot, dash or underscore")
    parsed_uuid = uuid.UUID(vm["uuid"])
    if parsed_uuid.int == 0 or str(parsed_uuid) != vm["uuid"].lower():
        raise ValueError("Use a nonzero canonical UUID")
    mac = vm["mac"].lower()
    if not re.fullmatch(r"(?:[0-9a-f]{2}:){5}[0-9a-f]{2}", mac):
        raise ValueError("Invalid MAC")
    rom = bytes.fromhex(mac.replace(":", ""))
    if rom == bytes(6) or rom[0] & 1:
        raise ValueError("MAC must be a nonzero unicast address")
    if identity["product_name"] != "iMacPro1,1":
        raise ValueError("This tested profile uses iMacPro1,1")
    if not re.fullmatch(r"[A-Z0-9]{12}", identity["serial"]):
        raise ValueError("Supply a 12-character serial from official macserial")
    if not re.fullmatch(r"[A-Z0-9]{17}", identity["mlb"]):
        raise ValueError("Supply its paired 17-character MLB from official macserial")
    # Shape checks are not Apple activation/coverage or MLB checksum validation.
    for field in ("root", "ovmf_code", "ovmf_vars_template"):
        if not re.fullmatch(r"/[A-Za-z0-9_./-]+", vm[field]) or "/../" in vm[field] or vm[field].endswith("/.."):
            raise ValueError("Use an absolute Linux path without traversal, spaces or shell syntax")
    if vm["root"] in ("/", "/mnt", "/mnt/user", "/mnt/user/domains"):
        raise ValueError("VM root must be a dedicated VM directory")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", vm["bridge"]):
        raise ValueError("Invalid bridge name")
    gpu, audio = bdf_parts(vm["gpu_bdf"]), bdf_parts(vm["audio_bdf"])
    if vm["gpu_bdf"] == vm["audio_bdf"] or gpu["function"] != "0x0" or audio["function"] != "0x1":
        raise ValueError("This profile expects distinct GPU function 0 and audio function 1")
    if any(gpu[k] != audio[k] for k in ("domain", "bus", "slot")):
        raise ValueError("GPU and audio must be functions of the same card")
    if require_osk and not re.fullmatch(r"[A-Za-z0-9 ()]{64}", settings["apple_smc_osk"]):
        raise ValueError("Supply your local 64-byte Apple SMC OSK before rendering XML")
    return rom


def make_opencore(settings, stage):
    rom = validate(settings)
    with (ROOT / "templates/opencore-1.0.5.plist").open("rb") as stream:
        cfg = plistlib.load(stream)
    generic = cfg["PlatformInfo"]["Generic"]
    generic.update(SystemProductName=settings["identity"]["product_name"],
                   SystemSerialNumber=settings["identity"]["serial"],
                   MLB=settings["identity"]["mlb"], SystemUUID=settings["vm"]["uuid"],
                   ROM=rom, ProcessorType=0x1009)
    cfg["Booter"]["Quirks"]["ProvideCustomSlide"] = True
    cfg["Booter"]["Quirks"]["ResizeAppleGpuBars"] = -1
    cfg["UEFI"]["Quirks"]["ResizeGpuBars"] = -1
    cfg["Kernel"]["Quirks"]["ProvideCurrentCpuInfo"] = True
    cfg["Misc"]["Security"]["SecureBootModel"] = "Disabled"
    nv = cfg["NVRAM"]["Add"][APPLE_GUID]
    nv["boot-args"] = GPU_ARGS if stage == "gpu" else BASE_ARGS
    nv["csr-active-config"] = bytes.fromhex("430A0000") if stage == "gpu" else bytes(4)
    deletes = cfg["NVRAM"]["Delete"].setdefault(APPLE_GUID, [])
    for key in ("boot-args", "csr-active-config"):
        if key not in deletes:
            deletes.append(key)
    for block in cfg["Kernel"]["Block"]:
        if block.get("Identifier") == "com.apple.iokit.IONDRVSupport":
            block["Enabled"] = stage == "gpu"
            block["Strategy"] = "Exclude"
    return cfg


def make_domain(settings, stage):
    validate(settings, require_osk=True)
    root = ET.parse(ROOT / "templates/domain.xml").getroot()
    vm = settings["vm"]
    root.find("name").text = vm["name"]
    root.find("uuid").text = vm["uuid"]
    root.find("os/loader").text = vm["ovmf_code"]
    nvram = root.find("os/nvram")
    nvram.text = vm["root"] + "/nvram/VARS.fd"
    nvram.set("template", vm["ovmf_vars_template"])
    devices = root.find("devices")
    for disk in devices.findall("disk"):
        source = disk.find("source")
        if source is not None:
            source.set("file", source.get("file").replace("{{VM_ROOT}}", vm["root"]))
    iface = devices.find("interface")
    iface.find("mac").set("address", vm["mac"].lower())
    iface.find("source").set("bridge", vm["bridge"])
    for dev, bdf in zip(devices.findall("hostdev"), (vm["gpu_bdf"], vm["audio_bdf"])):
        dev.find("source/address").attrib.update(bdf_parts(bdf))
    for arg in root.findall(f"{{{QEMU_NS}}}commandline/{{{QEMU_NS}}}arg"):
        if "{{APPLE_SMC_OSK}}" in arg.get("value", ""):
            arg.set("value", arg.get("value").replace("{{APPLE_SMC_OSK}}", settings["apple_smc_osk"]))
    if stage == "install":
        for dev in list(devices.findall("hostdev")):
            devices.remove(dev)
        video = devices.find("video")
        video.clear()
        ET.SubElement(video, "model", type="cirrus", vram="16384", heads="1", primary="yes")
        ET.SubElement(video, "address", type="pci", domain="0x0000", bus="0x00", slot="0x1e", function="0x0")
        graphics = ET.SubElement(devices, "graphics", type="vnc", port="-1", autoport="yes", listen="127.0.0.1")
        ET.SubElement(graphics, "listen", type="address", address="127.0.0.1")
        disk = ET.SubElement(devices, "disk", type="file", device="disk")
        ET.SubElement(disk, "driver", name="qemu", type="raw", cache="none")
        ET.SubElement(disk, "source", file=vm["root"] + "/media/Recovery.img")
        ET.SubElement(disk, "target", dev="hdb", bus="sata")
        ET.SubElement(disk, "address", type="drive", controller="0", bus="0", target="0", unit="1")
        installer = ET.SubElement(devices, "disk", type="file", device="disk")
        ET.SubElement(installer, "driver", name="qemu", type="raw", cache="none")
        ET.SubElement(installer, "source", file=vm["root"] + "/media/Installer.raw")
        ET.SubElement(installer, "target", dev="hdc", bus="sata")
        ET.SubElement(installer, "address", type="drive", controller="0", bus="0", target="0", unit="2")
    ET.indent(root, space="  ")
    return ET.tostring(root, encoding="utf-8", xml_declaration=True) + b"\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    init = sub.add_parser("init", help="Generate UUID/MAC once; retain them across stages")
    init.add_argument("--serial", required=True)
    init.add_argument("--mlb", required=True)
    init.add_argument("--gpu", required=True)
    init.add_argument("--audio", required=True)
    init.add_argument("--vm", default="macos15")
    init.add_argument("--root", default="/mnt/user/domains/macos15")
    init.add_argument("--output", default=str(LOCAL / "settings.json"))
    build = sub.add_parser("build")
    build.add_argument("--settings", default=str(LOCAL / "settings.json"))
    build.add_argument("--stage", choices=("install", "gpu"), required=True)
    build.add_argument("--domain", action="store_true", help="Also render XML (requires local OSK)")
    build.add_argument("--force", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "init":
            settings = json.loads((ROOT / "templates/local.example.json").read_text(encoding="utf-8"))
            settings["vm"].update(name=args.vm, root=args.root, uuid=str(uuid.uuid4()),
                                  mac="52:54:00:" + ":".join(f"{x:02x}" for x in secrets.token_bytes(3)),
                                  gpu_bdf=args.gpu, audio_bdf=args.audio)
            settings["identity"].update(serial=args.serial, mlb=args.mlb)
            validate(settings)
            write_private(args.output, (json.dumps(settings, indent=2) + "\n").encode())
            print("Created local settings; add OSK locally before rendering XML. Do not regenerate identity.")
        else:
            settings = json.loads(private_path(args.settings).read_text(encoding="utf-8-sig"))
            cfg = make_opencore(settings, args.stage)
            # Validate XML before writing either output, if XML was requested.
            xml = make_domain(settings, args.stage) if args.domain else None
            out = LOCAL / args.stage
            for p in (out / "config.plist", out / "domain.xml") if xml else (out / "config.plist",):
                if p.exists() and not args.force:
                    raise ValueError("Stage output exists; backup before --force")
            write_private(out / "config.plist", plistlib.dumps(cfg, sort_keys=False), args.force)
            if xml:
                write_private(out / "domain.xml", xml, args.force)
            print(f"Built local/{args.stage}/. Run official ocvalidate 1.0.5; no VM or host was changed.")
    except (ValueError, KeyError, OSError, ET.ParseError) as exc:
        parser.exit(2, f"STOP: {exc}\n")


if __name__ == "__main__":
    main()
