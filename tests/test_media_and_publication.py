import importlib.util
import io
import json
import lzma
from pathlib import Path
import struct
import shutil
import subprocess
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / (name + ".py"))
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


media = module("apple_media")
guard = module("check_publication")


class MediaTest(unittest.TestCase):
    def test_uncompressed_and_compressed_pbzx_chunks(self):
        first = b"cpio header and files"
        second = b"Recovery data" * 100
        compressed = lzma.compress(second)
        stream = (b"pbzx" + struct.pack(">Q", 16384)
                  + struct.pack(">QQ", len(first), len(first)) + first
                  + struct.pack(">QQ", len(second), len(compressed)) + compressed)
        target = io.BytesIO()
        self.assertEqual(media.pbzx(io.BytesIO(stream), target), len(first + second))
        self.assertEqual(target.getvalue(), first + second)

    def test_truncated_or_oversized_data_rejected(self):
        for raw in [b"pbz", b"pbzx" + struct.pack(">Q", 16384) + b"bad",
                    b"pbzx" + struct.pack(">Q", 16384) + struct.pack(">QQ", 2**40, 2) + b"ab"]:
            with self.subTest(raw=raw[:12]), self.assertRaises(ValueError):
                media.pbzx(io.BytesIO(raw), io.BytesIO())


class PublicationTest(unittest.TestCase):
    @unittest.skipUnless(shutil.which("git"), "Git is required for staged-content verification")
    def test_staged_secret_found_after_worktree_is_cleaned(self):
        local = ROOT / "local"
        local.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="publication-test-", dir=local) as directory:
            repo = Path(directory).resolve()
            self.assertTrue(repo.is_relative_to(local.resolve()))
            subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True, capture_output=True)
            path = repo / "settings.json"
            path.write_text(json.dumps({"password": "X" * 12}))
            subprocess.run(["git", "-C", str(repo), "add", "settings.json"], check=True, capture_output=True)
            path.write_text(json.dumps({"password": ""}))
            self.assertFalse(guard.scan_text(path.read_text(), ".json"))
            self.assertIn("staged: filled private JSON field", guard.staged_problems(path, repo))

    def test_private_identifiers_blocked_without_echoing_values(self):
        private_ip = ".".join(["10", "2", "3", "4"])
        self.assertIn("private/link-local IP", guard.scan_text(private_ip, ".md"))
        self.assertIn("non-public UUID", guard.scan_text(str(uuid.uuid4()), ".md"))
        mac = ":".join(["ab"] * 6)
        self.assertIn("filled MAC address", guard.scan_text(mac, ".md"))
        self.assertIn("filled SMC OSK", guard.scan_text("osk=" + "X" * 64, ".xml"))
        self.assertIn("filled private JSON field", guard.scan_text(json.dumps({"password": "X" * 12}), ".json"))

    def test_public_guids_loopback_and_blank_settings_allowed(self):
        text = " ".join(guard.PUBLIC_GUIDS) + " 127.0.0.1 0.0.0.0"
        self.assertFalse(guard.scan_text(text, ".md"))
        self.assertFalse(guard.scan_text((ROOT / "templates/local.example.json").read_text(), ".json"))
        self.assertFalse(guard.scan_text((ROOT / "templates/opencore-1.0.5.plist").read_text(), ".plist"))
        self.assertFalse(guard.scan_text("osk={{APPLE_SMC_OSK}}", ".xml"))


if __name__ == "__main__":
    unittest.main()
