"""Offline checks for privacy boundaries, identity consistency and boot stages."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("configure", ROOT / "tools/configure.py")
cfg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cfg)


def settings():
    result = json.loads((ROOT / "templates/local.example.json").read_text())
    result["vm"].update(uuid=str(uuid.uuid4()), mac="52:54:00:" + ":".join(["aa"] * 3),
                        gpu_bdf="0000:01:00.0", audio_bdf="0000:01:00.1")
    result["identity"].update(serial="F" + "A" * 11, mlb="C" + "A" * 16)
    result["apple_smc_osk"] = "X" * 64
    return result


class ConfigurationTest(unittest.TestCase):
    def test_identity_preserved_between_stages(self):
        s = settings()
        install = cfg.make_opencore(s, "install")
        gpu = cfg.make_opencore(s, "gpu")
        self.assertEqual(install["PlatformInfo"], gpu["PlatformInfo"])
        generic = gpu["PlatformInfo"]["Generic"]
        self.assertEqual(generic["ROM"].hex(), s["vm"]["mac"].replace(":", ""))
        self.assertEqual(generic["SystemUUID"], s["vm"]["uuid"])
        self.assertIn("-vsmccomp", gpu["NVRAM"]["Add"][cfg.APPLE_GUID]["boot-args"])
        self.assertTrue(gpu["Booter"]["Quirks"]["ProvideCustomSlide"])
        self.assertEqual(install["NVRAM"]["Add"][cfg.APPLE_GUID]["csr-active-config"], bytes(4))
        self.assertEqual(gpu["NVRAM"]["Add"][cfg.APPLE_GUID]["csr-active-config"].hex(), "430a0000")

    def test_recovery_and_display_only_in_install_domain(self):
        s = settings()
        i = cfg.ET.fromstring(cfg.make_domain(s, "install"))
        g = cfg.ET.fromstring(cfg.make_domain(s, "gpu"))
        self.assertEqual(len(i.findall("devices/hostdev")), 0)
        self.assertEqual(len(g.findall("devices/hostdev")), 2)
        self.assertIsNotNone(i.find("devices/graphics"))
        self.assertIsNone(g.find("devices/graphics"))
        self.assertEqual(g.find("devices/video/model").get("type"), "none")
        self.assertIn("Recovery.img", cfg.ET.tostring(i).decode())
        self.assertNotIn("Recovery.img", cfg.ET.tostring(g).decode())
        self.assertNotIn("{{", cfg.ET.tostring(g).decode())

    def test_invalid_input_rejected(self):
        for section, field, bad in [("vm", "mac", "ff:" + ":".join(["00"] * 5)),
                                    ("vm", "root", "/mnt/user/domains/../escape"),
                                    ("vm", "gpu_bdf", "0000:01:20.0"),
                                    ("identity", "serial", ""),
                                    ("identity", "product_name", "iMac19,1")]:
            s = settings()
            s[section][field] = bad
            with self.subTest(field=field), self.assertRaises(ValueError):
                cfg.validate(s)
        s = settings()
        s["apple_smc_osk"] = ""
        with self.assertRaises(ValueError):
            cfg.make_domain(s, "gpu")

    def test_output_cannot_escape_private_directory(self):
        for value in (ROOT / "config.plist", ROOT / "local/../../escape", ROOT / "local"):
            with self.assertRaises(ValueError):
                cfg.private_path(value)

    def test_ai_index_routes_to_existing_files(self):
        index = json.loads((ROOT / "ai/knowledge.json").read_text())
        paths = index["entrypoints"] + [p for route in index["routes"] for p in route["paths"]]
        for path in paths:
            with self.subTest(path=path):
                self.assertTrue((ROOT / path).is_file())


if __name__ == "__main__":
    unittest.main()
