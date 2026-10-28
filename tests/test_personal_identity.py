"""Checks for the personal edition's TSF identity without registering an IME."""

from pathlib import Path
import re
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[1]
CLSID = uuid.UUID("56A47253-A7C1-53AC-9028-7297207BD972")
PROFILE = uuid.UUID("1CAC6601-4479-55C1-BCA3-2B46B9AFD375")
UPSTREAM_CLSID = uuid.UUID("E3062E9A-D834-4637-8958-ED8CFA427D01")
UPSTREAM_PROFILE = uuid.UUID("4D59B1B4-D503-44AE-9259-BAD9BB2778AB")


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def guid_initializer(source, name):
    match = re.search(
        rf"\b{re.escape(name)}\s*=\s*\{{\s*(0x[0-9a-f]+)\s*,\s*"
        r"(0x[0-9a-f]+)\s*,\s*(0x[0-9a-f]+)\s*,\s*\{([^}]+)\}\s*\}",
        source,
        re.IGNORECASE,
    )
    if not match:
        raise AssertionError(f"missing GUID initializer: {name}")
    first = [int(value, 16) for value in match.group(1, 2, 3)]
    tail = [int(value.strip(), 16) for value in match.group(4).split(",")]
    if len(tail) != 8:
        raise AssertionError(f"invalid GUID initializer: {name}")
    return uuid.UUID(fields=(*first, tail[0], tail[1], int.from_bytes(bytes(tail[2:]), "big")))


class PersonalIdentityTests(unittest.TestCase):
    def test_tsf_and_watchdog_use_same_personal_guids(self):
        globals_cpp = read("windows/src/Global/Globals.cpp")
        watchdog_cpp = read("server/src/watchdog/main.cpp")
        self.assertEqual(guid_initializer(globals_cpp, "MetasequoiaIMECLSID"), CLSID)
        self.assertEqual(guid_initializer(globals_cpp, "MetasequoiaIMEGuidProfile"), PROFILE)
        self.assertEqual(guid_initializer(watchdog_cpp, "kMetasequoiaImeClsid"), CLSID)
        self.assertEqual(guid_initializer(watchdog_cpp, "kMetasequoiaImeProfileGuid"), PROFILE)
        self.assertNotEqual(CLSID, UPSTREAM_CLSID)
        self.assertNotEqual(PROFILE, UPSTREAM_PROFILE)

    def test_settings_and_uninstaller_reference_the_personal_profile(self):
        for path in (
            "server/src/settings/default_input_method.cpp",
            "server/src/settings/input_method_install.cpp",
            "server/src/settings/game_compat_name.cpp",
            "installer/msime_setup.iss",
        ):
            with self.subTest(path=path):
                source = read(path).upper()
                self.assertIn(str(CLSID).upper(), source)
                self.assertIn(str(PROFILE).upper(), source)
                self.assertNotIn(str(UPSTREAM_CLSID).upper(), source)
                self.assertNotIn(str(UPSTREAM_PROFILE).upper(), source)

    def test_all_private_tsf_guids_are_distinct(self):
        source = read("windows/src/Global/Globals.cpp")
        names = re.findall(r"extern const (?:GUID|CLSID) (MetasequoiaIME\w+)\s*=", source)
        self.assertEqual(len(names), 16)
        values = [guid_initializer(source, name) for name in names]
        self.assertEqual(len(set(values)), len(values))


if __name__ == "__main__":
    unittest.main()
