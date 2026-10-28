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

    def test_server_client_and_installer_use_separate_runtime_names(self):
        client = read("windows/src/IME/MetasequoiaIME.cpp")
        server = read("server/src/main.cpp")
        installer = read("installer/msime_setup.iss")
        self.assertIn("ChengjiangImeServer_SingleInstance", client)
        self.assertIn("ChengjiangImeServer_SingleInstance", server)
        self.assertIn("ChengjiangImeServer.Launch", client)
        self.assertIn("ChengjiangImeServer.Launch", installer)
        self.assertNotIn("MetasequoiaImeServer_SingleInstance", client + server)
        self.assertNotIn("MetasequoiaImeServer.Launch", client + installer)

    def test_configuration_mutex_matches_clipboard_helper(self):
        config = read("server/src/config/ime_config_internal.h")
        clipboard = read("server/src/clipboard/clipboard_history.cpp")
        self.assertIn("ChengjiangIme.ConfigFile", config)
        self.assertIn("ChengjiangIme.ConfigFile", clipboard)
        self.assertNotIn("MetasequoiaIme.ConfigFile", config + clipboard)

    def test_settings_and_candidate_window_names_are_isolated(self):
        launcher = read("server/src/settings/settings_launcher.cpp")
        settings = read("server/src/settings/settings_app.cpp")
        installer = read("installer/msime_setup.iss")
        self.assertIn("ChengjiangImeSettingsWindow", launcher)
        self.assertIn("ChengjiangImeSettingsWindow", settings)
        self.assertIn("ChengjiangImeSettingsWindow", installer)
        self.assertNotIn("MetasequoiaImeSettingsWindow", launcher + settings + installer)
        for path in (
            "server/src/window/ime_windows.h",
            "server/src/config/ime_config_write.cpp",
            "server/src/settings/dictionary_manager.cpp",
        ):
            with self.subTest(path=path):
                source = read(path)
                self.assertIn("chengjiangime_windows", source)
                self.assertNotIn("metasequoiaime_windows", source)

    def test_installer_only_stops_personal_executable_names(self):
        installer = read("installer/msime_setup.iss")
        cmake = read("server/CMakeLists.txt")
        for suffix in ("Server", "Watchdog", "Settings", "EmojiPanel", "KeyboardPanel", "HandwritingPanel"):
            with self.subTest(executable=suffix):
                personal = f"ChengjiangIme{suffix}"
                self.assertIn(personal + ".exe", installer)
                self.assertIn('OUTPUT_NAME "' + personal + '"', cmake)
                self.assertNotIn("MetasequoiaIme" + suffix + ".exe", installer)

    def test_runtime_data_directories_and_registry_are_separate(self):
        for path in (
            "windows/src/Utils/FanyUtils.cpp",
            "server/src/utils/ime_paths.cpp",
            "engine/core/data_path.h",
        ):
            with self.subTest(path=path):
                source = read(path)
                self.assertIn('L"chengjiangime"', source)
                self.assertIn("CHENGJIANG_IME_DATA_DIR", source)
                self.assertIn(r"Software\\Chengjiang\\PersonalIME", source)
                self.assertNotIn(r"Software\\Metasequoia\\MetasequoiaIME", source)
        installer = read("installer/msime_setup.iss")
        self.assertIn("AppId={{C4548683-2C88-54A9-A7AE-CD6008F8154C}", installer)
        self.assertNotIn("AppId={{A7C3E91F-4B2D-4E8A-9F1C-6D5E8B0A2C4D}", installer)
        self.assertIn("AddBackslash(PersonalInteractiveLocalData) + 'chengjiangime'", installer)
        self.assertIn("{commonpf64}\\chengjiangime", installer)
        self.assertIn("IME\\ChengjiangIME", installer)
        self.assertNotIn("TryDeleteTree(ExpandConstant('{localappdata}\\metasequoiaime", installer)
        self.assertNotIn("TryDeleteTree(ExpandConstant('{commonappdata}\\metasequoiaime", installer)

    def test_development_certificate_identity_does_not_match_upstream(self):
        signer = read("installer/sign-dev-build.ps1")
        importer = read("installer/import-dev-trust.ps1")
        personal = "CN=Chengjiang IME Personal Dev Build Code Signing"
        upstream = "CN=Metasequoia IME Dev Build Code Signing"
        self.assertIn(personal, signer)
        self.assertIn(personal, importer)
        self.assertNotIn(upstream, signer + importer)

    def test_upstream_updater_is_disabled_for_personal_edition(self):
        main = read("server/src/main.cpp")
        about = read("server/src/settings/native/native_page_about.cpp")
        self.assertNotIn("update_check::StartPolling()", main)
        self.assertIn("constexpr bool kPersonalUpdatesEnabled = false", about)
        self.assertIn("SetDisabled(!kPersonalUpdatesEnabled)", about)


if __name__ == "__main__":
    unittest.main()
