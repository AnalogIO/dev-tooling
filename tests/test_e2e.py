"""Unit tests for the cross-platform E2E helper.

Run with:  python -m unittest discover -s tests -v
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("analog_e2e", ROOT / "e2e.py")
assert SPEC and SPEC.loader
e2e = importlib.util.module_from_spec(SPEC)
sys.modules["analog_e2e"] = e2e
SPEC.loader.exec_module(e2e)


class ParseEnvTests(unittest.TestCase):
    def test_basic_values_comments_and_blanks(self) -> None:
        parsed = e2e.parse_env_text(
            "\n".join(
                [
                    "# a comment",
                    "",
                    "API_PORT=8080",
                    "CORE_DIR = analog-core",
                    "export DB_NAME=master",
                ]
            )
        )
        self.assertEqual(parsed["API_PORT"], "8080")
        self.assertEqual(parsed["CORE_DIR"], "analog-core")
        self.assertEqual(parsed["DB_NAME"], "master")

    def test_quoted_values_and_inline_comments(self) -> None:
        parsed = e2e.parse_env_text(
            "\n".join(
                [
                    'SIM_NAME="iPhone 16 Pro" # preferred',
                    "DB_PASSWORD='with spaces'",
                    'GREETING="say \\"hi\\""',
                    "EMPTY=",
                ]
            )
        )
        self.assertEqual(parsed["SIM_NAME"], "iPhone 16 Pro")
        self.assertEqual(parsed["DB_PASSWORD"], "with spaces")
        self.assertEqual(parsed["GREETING"], 'say "hi"')
        self.assertEqual(parsed["EMPTY"], "")

    def test_invalid_line_raises(self) -> None:
        with self.assertRaises(e2e.E2EException):
            e2e.parse_env_text("NOT A KEY VALUE")

    def test_unterminated_quote_raises(self) -> None:
        with self.assertRaises(e2e.E2EException):
            e2e.parse_env_text('SIM_NAME="iPhone')


class MailTests(unittest.TestCase):
    def test_decode_quoted_printable_soft_breaks_and_escapes(self) -> None:
        self.assertEqual(
            e2e.decode_quoted_printable("Hello=3D=0AWorld"), "Hello=\nWorld"
        )
        self.assertEqual(e2e.decode_quoted_printable("one=\r\ntwo"), "onetwo")
        self.assertEqual(e2e.decode_quoted_printable("plain text"), "plain text")

    def test_extract_links_from_hrefs_and_raw_urls(self) -> None:
        html = (
            '<a href="analogcoffeecard-dev://cafeanalog.dk/register/abc">go</a>'
            " and https://example.test/login/auth/xyz"
        )
        links = e2e.extract_links(html)
        self.assertIn("analogcoffeecard-dev://cafeanalog.dk/register/abc", links)
        self.assertIn("https://example.test/login/auth/xyz", links)

    def test_magic_link_from_message_decodes_body(self) -> None:
        message = {
            "Content": {
                "Body": (
                    '<html><a href=3D"analogcoffeecard-dev://cafeanalog.dk/'
                    'register/token-123">Complete</a></html>'
                )
            }
        }
        self.assertEqual(
            e2e.magic_link_from_message(message),
            "analogcoffeecard-dev://cafeanalog.dk/register/token-123",
        )

    def test_message_without_magic_link(self) -> None:
        message = {"Content": {"Body": '<a href="https://example.test/">x</a>'}}
        self.assertIsNone(e2e.magic_link_from_message(message))


class DeviceSelectionTests(unittest.TestCase):
    DEVICES = [
        {"udid": "ipad", "name": "iPad Pro", "state": "Shutdown"},
        {"udid": "iphone-a", "name": "iPhone 16 Pro", "state": "Booted"},
        {"udid": "iphone-b", "name": "iPhone 17", "state": "Shutdown"},
    ]

    def test_select_by_udid(self) -> None:
        selected = e2e.select_ios_device(self.DEVICES, "iphone-b", "")
        self.assertEqual(selected["udid"], "iphone-b")

    def test_select_by_name(self) -> None:
        selected = e2e.select_ios_device(self.DEVICES, "", "iPhone 17")
        self.assertEqual(selected["udid"], "iphone-b")

    def test_falls_back_to_first_iphone(self) -> None:
        selected = e2e.select_ios_device(self.DEVICES, "", "Missing model")
        self.assertEqual(selected["udid"], "iphone-a")

    def test_missing_explicit_udid_raises(self) -> None:
        with self.assertRaises(e2e.E2EException):
            e2e.select_ios_device(self.DEVICES, "nope", "")

    def test_parse_adb_devices(self) -> None:
        output = "\n".join(
            [
                "List of devices attached",
                "emulator-5554 device product:sdk_gphone model:Pixel_7",
                "R58M123 unauthorized usb:1-1",
                "R58M999 offline",
                "",
            ]
        )
        devices = e2e.parse_adb_devices(output)
        self.assertEqual(
            devices,
            [
                {"serial": "emulator-5554", "state": "device"},
                {"serial": "R58M123", "state": "unauthorized"},
                {"serial": "R58M999", "state": "offline"},
            ],
        )


class TableTests(unittest.TestCase):
    def test_format_table(self) -> None:
        rendered = e2e.format_table(
            ["Name", "Email", "Owned tickets"],
            [["John Doe", "a@analog.local", "4"]],
            right_align={2},
        )
        self.assertIn("| Name", rendered)
        self.assertIn("| a@analog.local", rendered)
        self.assertRegex(rendered, r"\|\s+4 \|")
        self.assertTrue(rendered.startswith("+"))


class ConfigTests(unittest.TestCase):
    def test_precedence_environment_over_local_over_default(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "config.env").write_text(
                "API_PORT=8080\nCORE_DIR=base-core\nDB_PASSWORD=base\n",
                encoding="utf-8",
            )
            (root / "config.local.env").write_text(
                "API_PORT=9090\nCORE_DIR=local-core\n",
                encoding="utf-8",
            )
            with mock.patch.dict(os.environ, {"API_PORT": "7070"}, clear=False):
                cfg = e2e.Config(root)
            self.assertEqual(cfg.api_port, 7070)
            self.assertEqual(cfg.api_base_url, "http://localhost:7070")
            self.assertEqual(cfg.core_dir, (root / "local-core").resolve())
            self.assertEqual(cfg.db_password, "base")

    def test_cli_overrides_win(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "config.env").write_text("API_PORT=8080\n", encoding="utf-8")
            cfg = e2e.Config(root, {"API_PORT": "6060"})
            self.assertEqual(cfg.api_port, 6060)

    def test_mailhog_and_smtp_ports_are_linked(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "config.env").write_text(
                "MAILHOG_HTTP_PORT=8123\nMAILHOG_SMTP_PORT=1125\n",
                encoding="utf-8",
            )
            cfg = e2e.Config(root)
            self.assertEqual(cfg.mailhog_url, "http://127.0.0.1:8123")
            self.assertEqual(cfg.smtp_port, 1125)

    def test_database_connection_string(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "config.env").write_text(
                "DB_PORT=14330\nDB_NAME=testdb\nDB_USER=sa\nDB_PASSWORD=pw\n",
                encoding="utf-8",
            )
            cfg = e2e.Config(root)
            connection = cfg.database_connection_string
            self.assertIn("Server=localhost,14330", connection)
            self.assertIn("Initial Catalog=testdb", connection)
            self.assertIn("Password=pw", connection)

    def test_continue_on_health_error_defaults_off(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "config.env").write_text("API_PORT=8080\n", encoding="utf-8")
            self.assertFalse(e2e.Config(root).continue_on_health_error)

    def test_continue_on_health_error_can_be_enabled(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "config.env").write_text(
                "CONTINUE_ON_HEALTH_ERROR=1\n", encoding="utf-8"
            )
            self.assertTrue(e2e.Config(root).continue_on_health_error)
            self.assertTrue(
                e2e.Config(
                    root, {"CONTINUE_ON_HEALTH_ERROR": "1"}
                ).continue_on_health_error
            )


class AndroidAppUrlTests(unittest.TestCase):
    def _runner(self, extra: str = "") -> "e2e.AppRunner":
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        (root / "config.env").write_text(
            "API_PORT=8080\n" + extra, encoding="utf-8"
        )
        cfg = e2e.Config(root)
        return e2e.AppRunner(cfg, e2e.Console(color=False))

    def test_android_emulator_uses_host_alias(self) -> None:
        runner = self._runner()
        device = e2e.Device("android", "emulator-5554")
        self.assertEqual(runner.api_base_url_for(device), "http://10.0.2.2:8080")

    def test_android_physical_device_uses_override(self) -> None:
        runner = self._runner("ANDROID_API_BASE_URL=http://192.168.1.10:8080\n")
        device = e2e.Device("android", "R58M123")
        self.assertEqual(
            runner.api_base_url_for(device), "http://192.168.1.10:8080"
        )

    def test_ios_uses_localhost(self) -> None:
        runner = self._runner()
        device = e2e.Device("ios", "ABC-123")
        self.assertEqual(runner.api_base_url_for(device), "http://localhost:8080")

    def test_android_cleartext_detection(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            app = Path(tmp)
            self.assertFalse(e2e.android_cleartext_ok(app))
            debug = app / "android" / "app" / "src" / "debug"
            debug.mkdir(parents=True)
            (debug / "AndroidManifest.xml").write_text(
                '<manifest><application android:usesCleartextTraffic="true"/></manifest>',
                encoding="utf-8",
            )
            self.assertTrue(e2e.android_cleartext_ok(app))


class GlobalFlagTests(unittest.TestCase):
    def test_global_flags_are_moved_before_the_subcommand(self) -> None:
        self.assertEqual(
            e2e.normalize_global_flags(["config", "--no-color"]),
            ["--no-color", "config"],
        )
        self.assertEqual(
            e2e.normalize_global_flags(["up", "--no-device", "--verbose"]),
            ["--verbose", "up", "--no-device"],
        )
        self.assertEqual(
            e2e.normalize_global_flags(["--no-color", "status"]),
            ["--no-color", "status"],
        )

    def test_parser_accepts_global_flags_either_side(self) -> None:
        parser = e2e.build_parser()
        after = parser.parse_args(
            e2e.normalize_global_flags(["config", "--no-color", "--verbose"])
        )
        before = parser.parse_args(
            e2e.normalize_global_flags(["--no-color", "--verbose", "config"])
        )
        for args in (after, before):
            self.assertEqual(args.command, "config")
            self.assertTrue(args.no_color)
            self.assertTrue(args.verbose)

    def test_continue_on_health_error_is_a_global_flag(self) -> None:
        self.assertEqual(
            e2e.normalize_global_flags(["up", "--continue-on-health-error"]),
            ["--continue-on-health-error", "up"],
        )
        args = e2e.build_parser().parse_args(
            e2e.normalize_global_flags(["up", "--continue-on-health-error"])
        )
        self.assertTrue(args.continue_on_health_error)
        self.assertEqual(
            e2e.overrides_from_args(args),
            {"CONTINUE_ON_HEALTH_ERROR": "1"},
        )


class HealthCheckTests(unittest.TestCase):
    def _config(self, extra: str = "") -> "e2e.Config":
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        (root / "config.env").write_text("API_PORT=8080\n" + extra, encoding="utf-8")
        return e2e.Config(root)

    def _console(self) -> "e2e.Console":
        return e2e.Console(color=False)

    def test_mssql_probe_is_fatal_by_default(self) -> None:
        database = e2e.Database(self._config(), mock.Mock(), self._console())
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(e2e.E2EException):
                database.wait_ready(timeout=0)

    def test_mssql_probe_warns_and_continues_when_enabled(self) -> None:
        cfg = self._config("CONTINUE_ON_HEALTH_ERROR=1\n")
        database = e2e.Database(cfg, mock.Mock(), self._console())
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertFalse(database.wait_ready(timeout=0))

    def test_mailhog_probe_is_fatal_by_default(self) -> None:
        mailhog = e2e.MailHog(self._config(), self._console())
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(e2e.E2EException):
                mailhog.wait_ready(timeout=0)

    def test_mailhog_probe_warns_and_continues_when_enabled(self) -> None:
        cfg = self._config("CONTINUE_ON_HEALTH_ERROR=1\n")
        mailhog = e2e.MailHog(cfg, self._console())
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertFalse(mailhog.wait_ready(timeout=0))

    def _start_backend(self, cfg: "e2e.Config", expect_error: bool) -> mock.Mock:
        backend = e2e.Backend(cfg, self._console())
        process = mock.Mock()
        process.pid = 4242
        with contextlib.ExitStack() as stack:
            stack.enter_context(
                mock.patch.object(e2e.Backend, "is_up", return_value=False)
            )
            stack.enter_context(
                mock.patch.object(e2e.Backend, "port_in_use", return_value=False)
            )
            stack.enter_context(
                mock.patch.object(
                    e2e.Backend,
                    "_build",
                    return_value=cfg.root / "CoffeeCard.WebApi.dll",
                )
            )
            stack.enter_context(
                mock.patch.object(e2e.Backend, "wait_ready", return_value=False)
            )
            terminate = stack.enter_context(
                mock.patch.object(e2e.Backend, "_terminate")
            )
            popen = stack.enter_context(mock.patch("e2e.subprocess.Popen"))
            stack.enter_context(
                mock.patch.object(e2e, "require", return_value="dotnet")
            )
            stack.enter_context(contextlib.redirect_stderr(io.StringIO()))
            stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
            popen.return_value = process
            if expect_error:
                with self.assertRaises(e2e.E2EException):
                    backend.start()
            else:
                backend.start()
        return terminate

    def test_backend_probe_is_fatal_by_default(self) -> None:
        terminate = self._start_backend(self._config(), expect_error=True)
        terminate.assert_called_once_with(4242)

    def test_backend_probe_continues_when_enabled(self) -> None:
        cfg = self._config("CONTINUE_ON_HEALTH_ERROR=1\n")
        terminate = self._start_backend(cfg, expect_error=False)
        terminate.assert_not_called()
        self.assertEqual(cfg.backend_pid.read_text(encoding="utf-8"), "4242")

    def test_seed_runs_when_database_is_ready(self) -> None:
        database = mock.Mock()
        e2e._seed_when_ready(self._console(), database, True)
        database.seed.assert_called_once_with()

    def test_seed_is_skipped_when_readiness_was_not_confirmed(self) -> None:
        database = mock.Mock()
        with contextlib.redirect_stderr(io.StringIO()) as stderr:
            e2e._seed_when_ready(self._console(), database, False)
        database.seed.assert_not_called()
        self.assertIn("Skipping the demo seed", stderr.getvalue())

    def test_up_continues_when_mssql_probe_times_out(self) -> None:
        cfg = self._config("CONTINUE_ON_HEALTH_ERROR=1\n")
        con = self._console()
        with contextlib.ExitStack() as stack:
            stack.enter_context(mock.patch.object(e2e, "cmd_check"))
            docker_cls = stack.enter_context(mock.patch.object(e2e, "Docker"))
            database_cls = stack.enter_context(mock.patch.object(e2e, "Database"))
            mailhog_cls = stack.enter_context(mock.patch.object(e2e, "MailHog"))
            backend_cls = stack.enter_context(mock.patch.object(e2e, "Backend"))
            stack.enter_context(mock.patch.object(e2e, "cmd_status"))
            stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
            stack.enter_context(contextlib.redirect_stderr(io.StringIO()))
            database = database_cls.return_value
            database.wait_ready.return_value = False
            mailhog_cls.return_value.wait_ready.return_value = True

            self.assertEqual(e2e.cmd_up(cfg, con, backend_only=True), 0)
            docker_cls.return_value.up.assert_called_once_with()
            backend_cls.return_value.start.assert_called_once_with()
            database.seed.assert_not_called()


if __name__ == "__main__":
    unittest.main()
