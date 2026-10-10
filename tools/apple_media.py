#!/usr/bin/env python3
"""Verify pinned local Apple media and decode the exact PBZX/BXDIFF50 formats used here."""
import argparse
import hashlib
import lzma
from pathlib import Path
import struct

PINNED = {
    "package": (15664523626, "e4532e3337431292a7f227fcde7eb57f7b907547e2a26b43d3aab5a3f6e44781"),
    "recovery": (1334686716, "fb7db37cb6501690f63f71b80c6e940130aeca2a30dfcc781d335aa452751343"),
}


def digest(path, algorithm):
    h = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            h.update(data)
    return h.hexdigest()


def read_exact(stream, count):
    data = stream.read(count)
    if len(data) != count:
        raise ValueError("Truncated input")
    return data


def pbzx(stream, output):
    if read_exact(stream, 4) != b"pbzx":
        raise ValueError("Expected PBZX header")
    chunk_size = struct.unpack(">Q", read_exact(stream, 8))[0]
    if not 0 < chunk_size <= 64 * 1024 * 1024:
        raise ValueError("Unsupported PBZX chunk size")
    written = 0
    while True:
        head = stream.read(16)
        if not head:
            break
        if len(head) != 16:
            raise ValueError("Truncated chunk header")
        raw_len, packed_len = struct.unpack(">QQ", head)
        if not 0 < raw_len <= 64 * 1024 * 1024 or not 0 < packed_len <= 64 * 1024 * 1024:
            raise ValueError("Unsupported chunk length")
        packed = read_exact(stream, packed_len)
        if packed.startswith(b"\xfd7zXZ\x00"):
            decoder = lzma.LZMADecompressor(memlimit=256 * 1024 * 1024)
            data = decoder.decompress(packed, max_length=raw_len + 1)
            if not decoder.eof or decoder.unused_data:
                raise ValueError("Invalid XZ chunk")
        else:
            data = packed
        if len(data) != raw_len:
            raise ValueError("Decoded chunk size mismatch")
        output.write(data)
        written += raw_len
    return written


def unpack(source, target, kind):
    if source.resolve() == target.resolve():
        raise ValueError("Input and output must differ")
    with source.open("rb") as stream:
        expected_size = expected_sha1 = None
        if kind == "bx":
            header = read_exact(stream, 60)
            if header[:8] != b"BXDIFF50":
                raise ValueError("Not a BXDIFF50 image")
            flags, expected_size, control_size, diff_size = struct.unpack_from("<4Q", header, 8)
            if flags != 0 or control_size != 0:
                raise ValueError("This is a real delta patch; a source image is required. Do not decode it as a full image.")
            expected_sha1 = header[40:60].hex()
        # Never replace an existing image. A failed output is retained for inspection.
        with target.open("xb") as output:
            actual_size = pbzx(stream, output)
    if kind == "bx" and (actual_size != expected_size or digest(target, "sha1") != expected_sha1):
        raise ValueError("Reconstructed image fails the embedded length/SHA1 check")
    return actual_size


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="command", required=True)
    v = sub.add_parser("verify")
    v.add_argument("kind", choices=PINNED)
    v.add_argument("file", type=Path)
    for name in ("pbzx", "bx"):
        s = sub.add_parser(name)
        s.add_argument("input", type=Path)
        s.add_argument("output", type=Path)
    a = p.parse_args()
    try:
        if a.command == "verify":
            size, sha = PINNED[a.kind]
            if a.file.stat().st_size != size or digest(a.file, "sha256") != sha:
                raise ValueError("Pinned size/SHA256 mismatch; do not use this file")
            print("PASS: pinned size and SHA256 match. This command does not validate Apple signatures.")
        else:
            print(f"Decoded {unpack(a.input, a.output, a.command)} bytes; verify the final recovery separately.")
    except (OSError, ValueError, lzma.LZMAError) as exc:
        p.exit(2, f"STOP: {exc}\n")


if __name__ == "__main__":
    main()
