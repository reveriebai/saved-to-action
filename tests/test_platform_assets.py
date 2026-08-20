import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skill" / "saved-to-action"


class PlatformAssetTests(unittest.TestCase):
    def test_shared_board_is_packaged_by_both_native_apps(self):
        board = SKILL / "assets" / "shared" / "Board.html"
        self.assertTrue(board.is_file())
        html = board.read_text(encoding="utf-8")
        self.assertIn("window.webkit", html)
        self.assertIn("window.chrome", html)

        mac_builder = (SKILL / "scripts" / "build_app.sh").read_text(encoding="utf-8")
        windows_project = (SKILL / "assets" / "windows-app" / "SavedToAction.Windows.csproj").read_text(
            encoding="utf-8"
        )
        self.assertIn("assets/shared", mac_builder)
        self.assertIn("..\\shared\\Board.html", windows_project)

    def test_windows_build_is_local_and_platform_scoped(self):
        script = (SKILL / "scripts" / "build_windows_app.ps1").read_text(encoding="utf-8")
        self.assertIn('ValidateSet("auto", "win-x64", "win-arm64")', script)
        self.assertIn("$env:LOCALAPPDATA", script)
        self.assertNotIn("Invoke-WebRequest", script)
        self.assertNotIn("Start-BitsTransfer", script)

    def test_windows_sources_and_ci_harness_exist(self):
        required = [
            SKILL / "assets" / "windows-app" / "ActionStore.cs",
            SKILL / "assets" / "windows-app" / "SafeSourceResolver.cs",
            SKILL / "assets" / "windows-app" / "Resources" / "DesktopCard.html",
            ROOT / "tests" / "windows" / "WindowsIntegrationHarness.csproj",
        ]
        self.assertTrue(all(path.is_file() for path in required))


if __name__ == "__main__":
    unittest.main()
