#!/usr/bin/env python3
"""Cross-platform local E2E environment for the Analog coffee card stack.

This script owns the whole local loop:

    docker compose (MSSQL + MailHog) -> analog-core backend -> seed data
    -> iOS simulator / Android emulator -> mobile_app via `flutter run`

It is intentionally dependency-free (Python standard library only) so it works
on macOS, Linux and Windows. Use `./e2e <command>` on macOS/Linux and
`e2e.cmd <command>` on Windows. `make <target>` is a thin wrapper for people who
already have GNU make.

See README.md for the quick start and LOCAL-E2E.md for the detailed flow.
"""

from __future__ import annotations

import argparse
import json
import os
import quopri
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

VERSION = "1.0.0"
MIN_PYTHON = (3, 9)
ROOT = Path(__file__).resolve().parent

# ---------------------------------------------------------------------------
# Console
# ---------------------------------------------------------------------------


class E2EException(RuntimeError):
    """A user-facing error. The CLI prints the message without a traceback."""


class Console:
    def __init__(self, color: bool = True, verbose: bool = False) -> None:
        self.verbose = verbose
        self.color = (
            color
            and sys.stdout.isatty()
            and os.environ.get("NO_COLOR") is None
            and os.name != "nt"
        )

    def _wrap(self, code: str, text: str) -> str:
        if not self.color:
            return text
        return f"\033[{code}m{text}\033[0m"

    def log(self, message: str) -> None:
        print(f"{self._wrap('1;34', '==>')} {message}", flush=True)

    def ok(self, message: str) -> None:
        print(f"{self._wrap('1;32', '==>')} {message}", flush=True)

    def warn(self, message: str) -> None:
        print(f"{self._wrap('1;33', '==>')} {message}", file=sys.stderr, flush=True)

    def error(self, message: str) -> None:
        print(f"{self._wrap('1;31', '==>')} {message}", file=sys.stderr, flush=True)

    def plain(self, message: str = "") -> None:
        print(message, flush=True)


VERBOSE = False


# ---------------------------------------------------------------------------
# Small process / text helpers
# ---------------------------------------------------------------------------


def cmdline(cmd: Sequence[Any]) -> str:
    return shlex.join([str(part) for part in cmd])


def tail_text(text: str, lines: int = 40) -> str:
    return "\n".join(text.splitlines()[-lines:])


def tail_path(path: Path, lines: int = 40) -> str:
    try:
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            return "\n".join(deque(handle, maxlen=lines)).rstrip("\n")
    except OSError:
        return ""


def run(
    cmd: Sequence[Any],
    *,
    cwd: Optional[Path] = None,
    env: Optional[Dict[str, str]] = None,
    input: Optional[str] = None,
    check: bool = True,
    capture: bool = False,
    timeout: Optional[float] = None,
    log_path: Optional[Path] = None,
) -> subprocess.CompletedProcess:
    """Run a command, optionally capturing output or writing it to a log file."""
    argv = [str(part) for part in cmd]
    if VERBOSE:
        print(f"$ {cmdline(argv)}", file=sys.stderr, flush=True)

    log_handle = None
    try:
        if log_path is not None:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            log_handle = log_path.open("w", encoding="utf-8", errors="replace")
            stdout: Any = log_handle
            stderr: Any = subprocess.STDOUT
        elif capture:
            stdout = subprocess.PIPE
            stderr = subprocess.STDOUT
        else:
            stdout = None
            stderr = None

        proc = subprocess.run(
            argv,
            cwd=str(cwd) if cwd is not None else None,
            env=env,
            input=input,
            stdout=stdout,
            stderr=stderr,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
    except FileNotFoundError as exc:
        raise E2EException(
            f"Command not found: {argv[0]}. Install it and make sure it is on PATH."
        ) from exc
    except subprocess.TimeoutExpired as exc:
        raise E2EException(
            f"Command timed out after {timeout:g}s: {cmdline(argv)}"
        ) from exc
    finally:
        if log_handle is not None:
            log_handle.close()

    if check and proc.returncode != 0:
        detail = ""
        if capture and proc.stdout:
            detail = "\n" + tail_text(proc.stdout)
        elif log_path is not None:
            detail = "\n" + tail_path(log_path)
        raise E2EException(
            f"Command failed (exit {proc.returncode}): {cmdline(argv)}{detail}"
        )
    return proc


def run_capture(
    cmd: Sequence[Any],
    *,
    cwd: Optional[Path] = None,
    env: Optional[Dict[str, str]] = None,
    input: Optional[str] = None,
    check: bool = True,
    timeout: Optional[float] = None,
) -> str:
    proc = run(
        cmd,
        cwd=cwd,
        env=env,
        input=input,
        check=check,
        capture=True,
        timeout=timeout,
    )
    return proc.stdout or ""


def require(name: str, hint: Optional[str] = None) -> str:
    path = shutil.which(name)
    if path:
        return path
    message = f"Missing required command: {name}"
    if hint:
        message += f"\n  {hint}"
    raise E2EException(message)


def command_argv(name: str, *args: Any) -> List[str]:
    """Resolve an executable, working around Windows .bat/.cmd shims (flutter)."""
    exe = require(name)
    if os.name == "nt" and exe.lower().endswith((".bat", ".cmd")):
        return ["cmd.exe", "/d", "/c", exe, *[str(arg) for arg in args]]
    return [exe, *[str(arg) for arg in args]]


def which(name: str) -> Optional[str]:
    return shutil.which(name)


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------


def http_request(
    method: str,
    url: str,
    *,
    body: Optional[Any] = None,
    headers: Optional[Dict[str, str]] = None,
    timeout: float = 5.0,
) -> Tuple[int, bytes]:
    data: Optional[bytes] = None
    request_headers: Dict[str, str] = dict(headers or {})
    if body is not None:
        if isinstance(body, (dict, list)):
            data = json.dumps(body).encode("utf-8")
            request_headers.setdefault("Content-Type", "application/json")
        elif isinstance(body, str):
            data = body.encode("utf-8")
        else:
            data = bytes(body)

    request = urllib.request.Request(
        url, data=data, headers=request_headers, method=method
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()
    except urllib.error.URLError as exc:
        raise E2EException(f"HTTP {method} {url} failed: {exc.reason}") from exc


def http_ok(url: str, timeout: float = 2.0) -> bool:
    try:
        status, _ = http_request("GET", url, timeout=timeout)
        return 200 <= status < 500
    except Exception:
        return False


def http_json(method: str, url: str, *, timeout: float = 5.0) -> Any:
    status, payload = http_request(method, url, timeout=timeout)
    if status >= 400:
        raise E2EException(f"HTTP {method} {url} returned {status}")
    return json.loads(payload.decode("utf-8")) if payload else None


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DEFAULTS: Dict[str, str] = {
    # Repositories (relative to this file, or absolute)
    "CORE_DIR": "analog-core",
    "APP_DIR": "mobile_app",
    "CORE_REPO": "https://github.com/AnalogIO/analog-core.git",
    "APP_REPO": "https://github.com/AnalogIO/mobile_app.git",
    "CORE_REF": "om/magic-link-registration",
    "APP_REF": "",
    # Backend
    "API_PORT": "8080",
    "API_BASE_URL": "",
    "API_BIND": "0.0.0.0",
    "DEEP_LINK_BASE": "analogcoffeecard-dev://cafeanalog.dk/",
    "SMTP_HOST": "127.0.0.1",
    "SMTP_PORT": "",
    # Database
    "DB_PORT": "1433",
    "DB_BIND": "127.0.0.1",
    "DB_USER": "sa",
    "DB_PASSWORD": "Your_password123",
    "DB_NAME": "master",
    "MSSQL_IMAGE": "mcr.microsoft.com/mssql/server:2022-latest",
    # MailHog
    "MAILHOG_HTTP_PORT": "8025",
    "MAILHOG_SMTP_PORT": "1025",
    "MAILHOG_BIND": "127.0.0.1",
    "MAILHOG_URL": "",
    "MAILHOG_IMAGE": "mailhog/mailhog:latest",
    # Device
    "PLATFORM": "auto",
    "DEVICE": "",
    "NO_DEVICE": "0",
    "SIM_NAME": "iPhone 16 Pro",
    "SIM_UDID": "",
    "ANDROID_AVD": "",
    "ANDROID_SERIAL": "",
    # Android emulators reach the host through 10.0.2.2. Set this for a
    # physical phone (e.g. http://192.168.1.10:8080).
    "ANDROID_API_BASE_URL": "",
    "APP_ID": "dk.analogio.analog.dev",
    "APP_FLAVOR": "development",
    "APP_SCHEME": "analogcoffeecard-dev",
}

ENV_LINE_RE = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$")


def parse_env_text(text: str, source: str = "<config>") -> Dict[str, str]:
    """Parse the small KEY=VALUE subset used by config.env.

    No shell expansion is performed on purpose: the same file must be readable
    on Windows, macOS and Linux. Quotes are optional; `#` starts a comment.
    """
    values: Dict[str, str] = {}
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = ENV_LINE_RE.match(line)
        if not match:
            raise E2EException(f"{source}:{lineno}: expected KEY=VALUE, got: {raw!r}")
        key, raw_value = match.group(1), match.group(2).strip()
        if raw_value[:1] in ("'", '"'):
            quote = raw_value[0]
            if quote == "'":
                end = raw_value.find("'", 1)
                if end == -1:
                    raise E2EException(
                        f"{source}:{lineno}: unterminated quoted value for {key}"
                    )
                value = raw_value[1:end]
                rest = raw_value[end + 1 :].strip()
            else:
                chars: List[str] = []
                index = 1
                while index < len(raw_value):
                    char = raw_value[index]
                    if char == "\\" and index + 1 < len(raw_value):
                        following = raw_value[index + 1]
                        if following in ('"', "\\"):
                            chars.append(following)
                            index += 2
                            continue
                    if char == '"':
                        break
                    chars.append(char)
                    index += 1
                if index >= len(raw_value):
                    raise E2EException(
                        f"{source}:{lineno}: unterminated quoted value for {key}"
                    )
                value = "".join(chars)
                rest = raw_value[index + 1 :].strip()
            if rest and not rest.startswith("#"):
                raise E2EException(
                    f"{source}:{lineno}: unexpected text after quoted value: {rest!r}"
                )
        else:
            value = re.sub(r"\s+#.*$", "", raw_value).strip()
        values[key] = value
    return values


def parse_env_file(path: Path) -> Dict[str, str]:
    if not path.exists():
        return {}
    return parse_env_text(path.read_text(encoding="utf-8"), source=str(path))


def _as_bool(value: str) -> bool:
    return value.strip().lower() in ("1", "true", "yes", "on")


def _as_int(name: str, value: str, minimum: int = 1, maximum: int = 65535) -> int:
    try:
        number = int(value)
    except (TypeError, ValueError):
        raise E2EException(f"{name} must be an integer, got: {value!r}")
    if not minimum <= number <= maximum:
        raise E2EException(f"{name} must be between {minimum} and {maximum}, got {number}")
    return number


class Config:
    def __init__(
        self, root: Path, overrides: Optional[Dict[str, str]] = None
    ) -> None:
        self.root = root
        values = dict(DEFAULTS)
        values.update(parse_env_file(root / "config.env"))
        values.update(parse_env_file(root / "config.local.env"))
        for key in DEFAULTS:
            if key in os.environ:
                values[key] = os.environ[key]
        if overrides:
            values.update({key: str(value) for key, value in overrides.items()})
        self.values = values

        self.core_dir = self._path("CORE_DIR")
        self.app_dir = self._path("APP_DIR")
        self.core_repo = self._str("CORE_REPO")
        self.app_repo = self._str("APP_REPO")
        self.core_ref = self._str("CORE_REF")
        self.app_ref = self._str("APP_REF")

        self.api_port = _as_int("API_PORT", self._str("API_PORT"))
        self.api_bind = self._str("API_BIND")
        self.api_base_url = (
            self._str("API_BASE_URL") or f"http://localhost:{self.api_port}"
        ).rstrip("/")
        self.deep_link_base = self._str("DEEP_LINK_BASE")

        self.db_port = _as_int("DB_PORT", self._str("DB_PORT"))
        self.db_bind = self._str("DB_BIND")
        self.db_user = self._str("DB_USER")
        self.db_password = self._str("DB_PASSWORD")
        self.db_name = self._str("DB_NAME")
        self.mssql_image = self._str("MSSQL_IMAGE")

        self.mailhog_http_port = _as_int(
            "MAILHOG_HTTP_PORT", self._str("MAILHOG_HTTP_PORT")
        )
        self.mailhog_smtp_port = _as_int(
            "MAILHOG_SMTP_PORT", self._str("MAILHOG_SMTP_PORT")
        )
        self.mailhog_bind = self._str("MAILHOG_BIND")
        self.mailhog_url = (
            self._str("MAILHOG_URL")
            or f"http://127.0.0.1:{self.mailhog_http_port}"
        ).rstrip("/")
        self.mailhog_image = self._str("MAILHOG_IMAGE")
        self.smtp_host = self._str("SMTP_HOST")
        self.smtp_port = _as_int(
            "SMTP_PORT", self._str("SMTP_PORT") or str(self.mailhog_smtp_port)
        )

        self.platform = self._str("PLATFORM").lower() or "auto"
        if self.platform not in ("auto", "ios", "android", "none"):
            raise E2EException(
                "PLATFORM must be one of: auto, ios, android, none "
                f"(got {self.platform!r})"
            )
        self.device = self._str("DEVICE")
        self.no_device = _as_bool(self._str("NO_DEVICE"))
        self.sim_name = self._str("SIM_NAME")
        self.sim_udid = self._str("SIM_UDID")
        self.android_avd = self._str("ANDROID_AVD")
        self.android_serial = self._str("ANDROID_SERIAL")
        self.android_api_base_url = self._str("ANDROID_API_BASE_URL").rstrip("/")
        self.app_id = self._str("APP_ID")
        self.app_flavor = self._str("APP_FLAVOR")
        self.app_scheme = self._str("APP_SCHEME")

        self.compose_file = root / "docker-compose.yml"
        self.backend_project = self.core_dir / "coffeecard" / "CoffeeCard.WebApi"
        self.csproj = self.backend_project / "CoffeeCard.WebApi.csproj"
        self.dev_dir = root / ".dev"
        self.backend_log = self.dev_dir / "backend.log"
        self.backend_build_log = self.dev_dir / "backend-build.log"
        self.backend_pid = self.dev_dir / "backend.pid"
        self.device_state = self.dev_dir / "device.json"

    def _str(self, key: str) -> str:
        return str(self.values.get(key, DEFAULTS.get(key, ""))).strip()

    def _path(self, key: str) -> Path:
        raw = self._str(key)
        if not raw:
            raise E2EException(f"{key} must not be empty.")
        path = Path(raw).expanduser()
        if not path.is_absolute():
            path = self.root / path
        return path.resolve()

    @property
    def database_connection_string(self) -> str:
        return (
            f"Server=localhost,{self.db_port};Initial Catalog={self.db_name};"
            f"User={self.db_user};Password={self.db_password};"
            "TrustServerCertificate=True;"
        )

    def compose_env(self) -> Dict[str, str]:
        env = os.environ.copy()
        env.update(
            {
                "DB_PORT": str(self.db_port),
                "DB_BIND": self.db_bind,
                "DB_PASSWORD": self.db_password,
                "MSSQL_IMAGE": self.mssql_image,
                "MAILHOG_SMTP_PORT": str(self.mailhog_smtp_port),
                "MAILHOG_HTTP_PORT": str(self.mailhog_http_port),
                "MAILHOG_BIND": self.mailhog_bind,
                "MAILHOG_IMAGE": self.mailhog_image,
            }
        )
        return env

    def describe(self) -> List[Tuple[str, str]]:
        password = "*" * len(self.db_password)
        return [
            ("root", str(self.root)),
            ("core", f"{self.core_dir} ({git_branch(self.core_dir)})"),
            ("app", f"{self.app_dir} ({git_branch(self.app_dir)})"),
            ("platform", self.platform),
            ("device", self.device or self.sim_udid or self.android_serial or "(auto)"),
            ("api", self.api_base_url),
            (
                "android api",
                self.android_api_base_url
                or f"http://10.0.2.2:{self.api_port} (emulator)",
            ),
            ("mailhog", self.mailhog_url),
            ("database", f"localhost:{self.db_port}/{self.db_name}"),
            ("db password", password),
            ("app id", self.app_id),
            ("flavor", self.app_flavor),
            ("compose", str(self.compose_file)),
            ("state", str(self.dev_dir)),
        ]


def git_branch(repo: Path) -> str:
    if not (repo / ".git").exists():
        return "not a git repo"
    proc = run(
        ["git", "-C", str(repo), "branch", "--show-current"],
        check=False,
        capture=True,
    )
    return (proc.stdout or "").strip() or "detached"


# ---------------------------------------------------------------------------
# Docker Compose
# ---------------------------------------------------------------------------


class Docker:
    def __init__(self, cfg: Config, con: Console) -> None:
        self.cfg = cfg
        self.con = con
        self._available: Optional[bool] = None
        self._docker_exe: Optional[str] = None

    @property
    def exe(self) -> str:
        if self._docker_exe is None:
            self._docker_exe = require(
                "docker",
                "Install Docker Desktop (Windows/macOS) or Docker Engine + the "
                "Compose plugin (Linux).",
            )
        return self._docker_exe

    def available(self) -> bool:
        if self._available is not None:
            return self._available
        if not which("docker"):
            self._available = False
            return False
        proc = run([self.exe, "info"], check=False, capture=True, timeout=30)
        self._available = proc.returncode == 0
        return self._available

    def require(self) -> None:
        if not self.available():
            raise E2EException(
                "Docker is not running or not accessible.\n"
                "  Start Docker Desktop (Windows/macOS) or the Docker daemon "
                "(Linux), then retry."
            )

    def compose_version(self) -> Optional[str]:
        if not self.available():
            return None
        proc = run([self.exe, "compose", "version"], check=False, capture=True)
        return (proc.stdout or "").strip() if proc.returncode == 0 else None

    def compose(
        self,
        *args: Any,
        check: bool = True,
        capture: bool = False,
        input: Optional[str] = None,
        timeout: Optional[float] = None,
    ) -> subprocess.CompletedProcess:
        self.require()
        cmd = [
            self.exe,
            "compose",
            "-f",
            str(self.cfg.compose_file),
            "--project-directory",
            str(self.cfg.root),
            *[str(arg) for arg in args],
        ]
        return run(
            cmd,
            env=self.cfg.compose_env(),
            check=check,
            capture=capture,
            input=input,
            timeout=timeout,
        )

    def up(self) -> None:
        self.con.log("Starting MSSQL and MailHog (Docker)...")
        try:
            self.compose("up", "-d", "mssql", "mailhog", timeout=600)
        except E2EException as exc:
            legacy_compose = (
                self.cfg.core_dir / "coffeecard" / "docker-compose.yml"
            )
            hint = (
                "\n\nIf a previous local stack is still running (for example the "
                "old coffeecard compose project), stop it once:\n"
                f'  docker compose -f "{legacy_compose}" '
                f'--project-directory "{legacy_compose.parent}" down\n'
                "or remove the old containers directly:\n"
                "  docker rm -f mssql coffeecard-mailhog-1"
            )
            raise E2EException(f"{exc}{hint}") from exc

    def stop(self) -> None:
        self.compose("stop", "mssql", "mailhog", check=False, capture=True)

    def down(self, volumes: bool = False) -> None:
        args = ["down", "--remove-orphans"]
        if volumes:
            args.append("--volumes")
        self.compose(*args, check=False)

    def ps(self) -> str:
        proc = self.compose("ps", check=False, capture=True)
        return (proc.stdout or "").strip()


# ---------------------------------------------------------------------------
# Database (sqlcmd inside the MSSQL container)
# ---------------------------------------------------------------------------


class Database:
    def __init__(self, cfg: Config, docker: Docker, con: Console) -> None:
        self.cfg = cfg
        self.docker = docker
        self.con = con
        self._sqlcmd: Optional[str] = None

    def _detect_sqlcmd(self) -> Optional[str]:
        shell = (
            "if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then "
            "echo /opt/mssql-tools18/bin/sqlcmd; "
            "elif [ -x /opt/mssql-tools/bin/sqlcmd ]; then "
            "echo /opt/mssql-tools/bin/sqlcmd; fi"
        )
        proc = self.docker.compose(
            "exec", "-T", "mssql", "sh", "-c", shell, check=False, capture=True
        )
        if proc.returncode != 0:
            return None
        for line in (proc.stdout or "").splitlines():
            line = line.strip()
            if line.startswith("/") and "sqlcmd" in line:
                return line
        return None

    def sqlcmd_bin(self) -> str:
        if self._sqlcmd is None:
            found = self._detect_sqlcmd()
            if not found:
                raise E2EException(
                    "Could not find sqlcmd inside the mssql container. "
                    "Is the container running?"
                )
            self._sqlcmd = found
        return self._sqlcmd

    def sqlcmd(
        self,
        *args: Any,
        input: Optional[str] = None,
        check: bool = True,
        capture: bool = True,
        timeout: Optional[float] = None,
    ) -> subprocess.CompletedProcess:
        cmd = [
            "exec",
            "-T",
            "mssql",
            self.sqlcmd_bin(),
            "-C",
            "-S",
            "localhost",
            "-U",
            self.cfg.db_user,
            "-P",
            self.cfg.db_password,
            "-d",
            self.cfg.db_name,
            *[str(arg) for arg in args],
        ]
        return self.docker.compose(
            *cmd, input=input, check=check, capture=capture, timeout=timeout
        )

    def wait_ready(self, timeout: int = 120) -> None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            found = self._sqlcmd or self._detect_sqlcmd()
            if found:
                self._sqlcmd = found
                proc = self.sqlcmd("-l", "5", "-Q", "SELECT 1", check=False)
                if proc.returncode == 0:
                    return
            time.sleep(1)
        raise E2EException(
            "MSSQL did not become ready.\n"
            "  Try: docker compose logs mssql"
        )

    def run_file(self, path: Path) -> None:
        if not path.exists():
            raise E2EException(f"SQL file not found: {path}")
        text = path.read_text(encoding="utf-8-sig")
        proc = self.sqlcmd("-b", input=text, check=False)
        if proc.returncode != 0:
            raise E2EException(
                f"{path.name} failed:\n{tail_text(proc.stdout or '', 40)}"
            )

    def query(self, sql: str) -> List[List[str]]:
        proc = self.sqlcmd(
            "-W", "-h", "-1", "-s", "\t", "-Q", sql, check=False
        )
        if proc.returncode != 0:
            raise E2EException(
                f"Query failed:\n{tail_text(proc.stdout or '', 40)}"
            )
        rows: List[List[str]] = []
        for line in (proc.stdout or "").splitlines():
            if not line.strip():
                continue
            rows.append([cell.strip() for cell in line.split("\t")])
        return rows

    def seed(self) -> None:
        self.con.log("Seeding database (db/seed.sql)...")
        self.run_file(self.cfg.root / "db" / "seed.sql")
        counts = self.query(
            "SET NOCOUNT ON; "
            "SELECT 'programmes', COUNT(*) FROM dbo.Programmes "
            "UNION ALL SELECT 'users', COUNT(*) FROM dbo.Users "
            "UNION ALL SELECT 'products', COUNT(*) FROM dbo.Products "
            "UNION ALL SELECT 'tickets', COUNT(*) FROM dbo.Tickets"
        )
        for row in counts:
            if len(row) >= 2:
                self.con.plain(f"    {row[0]:<12} {row[1]}")
        self.con.ok(
            "Seed applied (john@doe.com: 4 unused; "
            "many.tickets@analog.local: 70 unused, 120 used, 10 refunded)."
        )

    def reset(self) -> None:
        self.con.log("Removing test accounts and tokens (db/reset.sql)...")
        self.run_file(self.cfg.root / "db" / "reset.sql")
        self.seed()

    def list_users(self) -> str:
        rows = self.query(
            "SET NOCOUNT ON; "
            "SELECT u.Name, u.Email, "
            "COALESCE(SUM(CASE WHEN t.Status = 0 THEN 1 ELSE 0 END), 0) "
            "FROM dbo.Users u "
            "LEFT JOIN dbo.Tickets t ON t.[Owner_Id] = u.Id "
            "GROUP BY u.Id, u.Name, u.Email ORDER BY u.Name"
        )
        return format_table(
            ["Name", "Email", "Owned tickets"],
            rows,
            right_align={2},
        )


# ---------------------------------------------------------------------------
# MailHog
# ---------------------------------------------------------------------------


def decode_quoted_printable(text: str) -> str:
    """Decode a quoted-printable email body, tolerating already-decoded input."""
    if "=" not in text:
        return text
    try:
        raw = quopri.decodestring(text.encode("utf-8", "surrogateescape"))
        return raw.decode("utf-8", "replace")
    except Exception:
        return text


HREF_RE = re.compile(r"""href\s*=\s*["']([^"']+)["']""", re.IGNORECASE)
URL_RE = re.compile(r"""(?:https?|analogcoffeecard[^:\s"']*)://[^\s"'<>]+""", re.IGNORECASE)


def extract_links(text: str) -> List[str]:
    links = [match.group(1) for match in HREF_RE.finditer(text)]
    links.extend(URL_RE.findall(text))
    seen = set()
    unique: List[str] = []
    for link in links:
        link = link.replace("&amp;", "&").strip()
        if link not in seen:
            seen.add(link)
            unique.append(link)
    return unique


def magic_link_from_message(message: Dict[str, Any]) -> Optional[str]:
    body = (message.get("Content") or {}).get("Body") or ""
    text = decode_quoted_printable(body)
    for link in extract_links(text):
        if "/register/" in link or "/login/auth/" in link:
            return link
    return None


def message_recipients(message: Dict[str, Any]) -> str:
    headers = (message.get("Content") or {}).get("Headers") or {}
    recipients = headers.get("To") or []
    if isinstance(recipients, str):
        recipients = [recipients]
    return " ".join(str(item) for item in recipients)


class MailHog:
    def __init__(self, cfg: Config, con: Console) -> None:
        self.cfg = cfg
        self.con = con

    def _url(self, path: str) -> str:
        return f"{self.cfg.mailhog_url}{path}"

    def ok(self) -> bool:
        return http_ok(self._url("/api/v2/messages"), timeout=2)

    def wait_ready(self, timeout: int = 60) -> None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.ok():
                return
            time.sleep(1)
        raise E2EException(f"MailHog did not become ready at {self.cfg.mailhog_url}.")

    def count(self) -> int:
        try:
            data = http_json("GET", self._url("/api/v2/messages"), timeout=2)
            return int((data or {}).get("total", 0))
        except Exception:
            return 0

    def messages(self) -> List[Dict[str, Any]]:
        try:
            data = http_json("GET", self._url("/api/v2/messages?limit=1000"))
        except E2EException:
            return []
        items = (data or {}).get("items") or []
        return sorted(items, key=lambda item: item.get("Created", ""), reverse=True)

    def newest_link(self) -> str:
        if not self.ok():
            raise E2EException(
                f"MailHog is not reachable at {self.cfg.mailhog_url}. "
                "Run `e2e up` first."
            )
        for message in self.messages():
            link = magic_link_from_message(message)
            if link:
                return link
        raise E2EException(
            "No registration or login email found in MailHog. "
            "Request a link from the app first."
        )

    def find_registration_for(
        self, email: str, timeout: int = 20
    ) -> Tuple[Optional[str], Optional[str]]:
        if not self.ok():
            raise E2EException(
                f"MailHog is not reachable at {self.cfg.mailhog_url}."
            )
        deadline = time.time() + timeout
        wanted = email.lower()
        while time.time() < deadline:
            for message in self.messages():
                if wanted not in message_recipients(message).lower():
                    continue
                link = magic_link_from_message(message)
                if link and "/register/" in link:
                    return str(message.get("ID") or ""), link
            time.sleep(1)
        return None, None

    def delete_all(self) -> None:
        http_request("DELETE", self._url("/api/v1/messages"))

    def delete_message(self, message_id: str) -> None:
        if not message_id:
            return
        encoded = urllib.parse.quote(message_id, safe="")
        http_request("DELETE", self._url(f"/api/v1/messages/{encoded}"))

    def open_in_browser(self) -> bool:
        return webbrowser.open(self.cfg.mailhog_url)


# ---------------------------------------------------------------------------
# Backend process
# ---------------------------------------------------------------------------


class Backend:
    MAX_LOG_BYTES = 10 * 1024 * 1024

    def __init__(self, cfg: Config, con: Console) -> None:
        self.cfg = cfg
        self.con = con
        self._dll: Optional[Path] = None

    def is_up(self) -> bool:
        return http_ok(f"{self.cfg.api_base_url}/api/v1/programmes", timeout=2)

    def read_pid(self) -> Optional[int]:
        try:
            raw = self.cfg.backend_pid.read_text(encoding="utf-8").strip()
            return int(raw) if raw else None
        except (OSError, ValueError):
            return None

    def _pid_alive(self, pid: int) -> bool:
        if os.name == "nt":
            proc = run(
                ["tasklist", "/FI", f"PID eq {pid}", "/NH"],
                check=False,
                capture=True,
            )
            output = proc.stdout or ""
            return str(pid) in output and "No tasks" not in output
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            return True

    def listener_pid(self) -> Optional[int]:
        port = self.cfg.api_port
        if os.name == "nt":
            proc = run(["netstat", "-ano", "-p", "tcp"], check=False, capture=True)
            for line in (proc.stdout or "").splitlines():
                parts = line.split()
                if (
                    len(parts) >= 5
                    and parts[0].upper() == "TCP"
                    and parts[1].endswith(f":{port}")
                    and parts[3].upper() == "LISTENING"
                ):
                    try:
                        return int(parts[-1])
                    except ValueError:
                        return None
            return None
        if which("lsof"):
            proc = run(
                ["lsof", f"-tiTCP:{port}", "-sTCP:LISTEN"],
                check=False,
                capture=True,
            )
            for line in (proc.stdout or "").splitlines():
                try:
                    return int(line.strip())
                except ValueError:
                    continue
        if which("ss"):
            proc = run(["ss", "-ltnp"], check=False, capture=True)
            for line in (proc.stdout or "").splitlines():
                if f":{port} " in line:
                    match = re.search(r"pid=(\d+)", line)
                    if match:
                        return int(match.group(1))
        return None

    def port_in_use(self) -> bool:
        try:
            with socket.create_connection(
                ("127.0.0.1", self.cfg.api_port), timeout=0.5
            ):
                return True
        except OSError:
            return False

    def _rotate_log(self) -> None:
        log = self.cfg.backend_log
        if log.exists() and log.stat().st_size > self.MAX_LOG_BYTES:
            backup = log.with_name(log.name + ".1")
            try:
                if backup.exists():
                    backup.unlink()
                log.rename(backup)
            except OSError:
                pass

    def _build(self) -> Path:
        if not self.cfg.csproj.exists():
            raise E2EException(
                f"Backend project not found: {self.cfg.csproj}\n"
                "  Run `e2e setup --clone` or check CORE_DIR in config.env."
            )
        self.cfg.dev_dir.mkdir(parents=True, exist_ok=True)
        self.con.log("Building backend...")
        proc = run(
            command_argv(
                "dotnet", "build", self.cfg.csproj, "-v", "q", "--nologo"
            ),
            cwd=self.cfg.backend_project,
            check=False,
            timeout=900,
            log_path=self.cfg.backend_build_log,
        )
        if proc.returncode != 0:
            raise E2EException(
                "Backend build failed.\n"
                f"  Full log: {self.cfg.backend_build_log}\n"
                f"{tail_path(self.cfg.backend_build_log, 40)}"
            )

        output = run_capture(
            command_argv(
                "dotnet",
                "msbuild",
                self.cfg.csproj,
                "-getProperty:TargetPath",
                "-nologo",
            ),
            cwd=self.cfg.backend_project,
            check=False,
        )
        candidates = [
            line.strip()
            for line in output.splitlines()
            if line.strip().lower().endswith(".dll")
        ]
        dll: Optional[Path] = None
        if candidates:
            dll = Path(candidates[-1])
            if not dll.is_absolute():
                dll = (self.cfg.backend_project / dll).resolve()
        if dll is None or not dll.exists():
            matches = sorted(
                (self.cfg.backend_project / "bin").glob(
                    "**/CoffeeCard.WebApi.dll"
                ),
                key=lambda item: item.stat().st_mtime,
                reverse=True,
            )
            if not matches:
                raise E2EException(
                    "Could not locate the built backend DLL. "
                    f"Build log: {self.cfg.backend_build_log}"
                )
            dll = matches[0]
        self._dll = dll.resolve()
        return self._dll

    def start(self) -> None:
        if self.is_up():
            if self.read_pid() is None:
                pid = self.listener_pid()
                if pid is not None:
                    self.cfg.backend_pid.write_text(str(pid), encoding="utf-8")
            if self.read_pid() is not None:
                self.con.ok(
                    f"Backend already running at {self.cfg.api_base_url} "
                    f"(pid {self.read_pid()})."
                )
            else:
                self.con.ok(f"Backend already running at {self.cfg.api_base_url}.")
            return

        if self.port_in_use():
            pid = self.listener_pid()
            detail = f" (pid {pid})" if pid else ""
            raise E2EException(
                f"Port {self.cfg.api_port} is in use{detail}, but the API is not "
                "healthy.\n  Stop that process, or set API_PORT to another value."
            )

        dll = self._build()
        self.cfg.dev_dir.mkdir(parents=True, exist_ok=True)
        self._rotate_log()

        env = os.environ.copy()
        env.update(
            {
                "ASPNETCORE_ENVIRONMENT": "Development",
                "DOTNET_ENVIRONMENT": "Development",
                "ASPNETCORE_URLS": f"http://{self.cfg.api_bind}:{self.cfg.api_port}",
                "EnvironmentSettings__AnalogAppUrl": self.cfg.deep_link_base,
                "SmtpSettings__Host": self.cfg.smtp_host,
                "SmtpSettings__Port": str(self.cfg.smtp_port),
                "DatabaseSettings__ConnectionString": self.cfg.database_connection_string,
            }
        )

        self.con.log(
            f"Starting backend on http://{self.cfg.api_bind}:{self.cfg.api_port} ..."
        )
        popen_kwargs: Dict[str, Any] = {}
        if os.name == "nt":
            popen_kwargs["creationflags"] = (
                getattr(subprocess, "CREATE_NO_WINDOW", 0)
                | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
            )
        else:
            popen_kwargs["start_new_session"] = True

        with self.cfg.backend_log.open("ab", buffering=0) as log:
            process = subprocess.Popen(
                [require("dotnet"), "exec", str(dll)],
                cwd=str(self.cfg.backend_project),
                env=env,
                stdout=log,
                stderr=subprocess.STDOUT,
                **popen_kwargs,
            )
        self.cfg.backend_pid.write_text(str(process.pid), encoding="utf-8")

        if not self.wait_ready(90, pid=process.pid):
            detail = tail_path(self.cfg.backend_log, 60)
            self._terminate(process.pid)
            raise E2EException(
                f"Backend did not become healthy at {self.cfg.api_base_url}.\n"
                f"  Log: {self.cfg.backend_log}\n{detail}"
            )

        self.con.ok(
            f"Backend ready at {self.cfg.api_base_url} "
            f"(pid {self.read_pid()})."
        )
        self.con.plain(f"    Log: {self.cfg.backend_log}")

    def wait_ready(self, timeout: int = 90, pid: Optional[int] = None) -> bool:
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.is_up():
                return True
            if pid is not None and not self._pid_alive(pid):
                return False
            time.sleep(1)
        return False

    def _terminate(self, pid: int) -> None:
        if os.name == "nt":
            run(
                ["taskkill", "/PID", str(pid), "/T", "/F"],
                check=False,
                capture=True,
            )
            return
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            return
        for _ in range(20):
            if not self._pid_alive(pid):
                return
            time.sleep(0.5)
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    def stop(self) -> None:
        pid = self.read_pid()
        if pid is None:
            pid = self.listener_pid()
        if pid is not None and self._pid_alive(pid):
            self.con.log(f"Stopping backend (pid {pid})...")
            self._terminate(pid)
        try:
            self.cfg.backend_pid.unlink()
        except OSError:
            pass
        if self.is_up():
            other = self.listener_pid()
            suffix = f" (pid {other})" if other else ""
            self.con.warn(
                f"Something is still serving {self.cfg.api_base_url}{suffix}. "
                "It was not started by this tool; stop it manually."
            )
        else:
            self.con.ok("Backend stopped.")

    def restart(self) -> None:
        self.stop()
        self.start()

    def follow_log(self, lines: int = 200) -> None:
        path = self.cfg.backend_log
        if not path.exists():
            raise E2EException(
                f"No backend log yet at {path}. Run `e2e up` first."
            )
        self.con.log(f"Tailing {path} (Ctrl-C to stop)...")
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            for line in deque(handle, maxlen=lines):
                sys.stdout.write(line)
            sys.stdout.flush()
            while True:
                line = handle.readline()
                if line:
                    sys.stdout.write(line)
                    sys.stdout.flush()
                else:
                    time.sleep(0.5)


# ---------------------------------------------------------------------------
# Devices: iOS simulator (macOS) and Android emulator/device
# ---------------------------------------------------------------------------


@dataclass
class Device:
    platform: str
    serial: str
    name: str = ""


def select_ios_device(
    devices: List[Dict[str, Any]], sim_udid: str, sim_name: str
) -> Optional[Dict[str, Any]]:
    if sim_udid:
        for device in devices:
            if device["udid"] == sim_udid:
                return device
        raise E2EException(
            f"No iOS simulator with UDID {sim_udid}. "
            f"Available: {', '.join(d['name'] for d in devices) or 'none'}"
        )
    if sim_name:
        for device in devices:
            if device["name"] == sim_name:
                return device
    iphones = [device for device in devices if "iPhone" in device["name"]]
    return (iphones or devices or [None])[0]


def parse_adb_devices(output: str) -> List[Dict[str, str]]:
    devices: List[Dict[str, str]] = []
    for line in output.splitlines():
        line = line.strip()
        if not line or line.startswith("List of devices") or line.startswith("*"):
            continue
        parts = line.split()
        if len(parts) >= 2 and parts[1] in ("device", "offline", "unauthorized"):
            devices.append({"serial": parts[0], "state": parts[1]})
    return devices


class Devices:
    def __init__(self, cfg: Config, con: Console) -> None:
        self.cfg = cfg
        self.con = con

    def resolve_platform(self) -> str:
        if self.cfg.platform != "auto":
            return self.cfg.platform
        if sys.platform == "darwin" and which("xcrun"):
            return "ios"
        if self.android_sdk() is not None or which("adb"):
            return "android"
        if sys.platform == "darwin":
            return "ios"
        raise E2EException(
            "No mobile device tooling found.\n"
            "  macOS: install Xcode (iOS simulator) or Android Studio.\n"
            "  Windows/Linux: install Android Studio and an Android emulator."
        )

    # -- iOS ---------------------------------------------------------------

    def _xcrun(self) -> str:
        return require("xcrun", "iOS simulators require macOS with Xcode installed.")

    def _ios_devices(self) -> List[Dict[str, Any]]:
        output = run_capture(
            [self._xcrun(), "simctl", "list", "devices", "available", "-j"]
        )
        data = json.loads(output)
        devices: List[Dict[str, Any]] = []
        for runtime, items in (data.get("devices") or {}).items():
            for item in items:
                if item.get("isAvailable", True):
                    devices.append(
                        {
                            "udid": item.get("udid", ""),
                            "name": item.get("name", ""),
                            "state": item.get("state", "Unknown"),
                            "runtime": runtime,
                        }
                    )
        return devices

    def _ensure_ios(self) -> Device:
        devices = self._ios_devices()
        selected = select_ios_device(
            devices, self.cfg.device or self.cfg.sim_udid, self.cfg.sim_name
        )
        if selected is None:
            raise E2EException(
                "No available iOS simulator found. Install an iOS runtime in Xcode."
            )
        udid = selected["udid"]
        if selected.get("state") != "Booted":
            self.con.log(f"Booting simulator {selected['name']} ({udid})...")
            run(
                [self._xcrun(), "simctl", "boot", udid],
                check=False,
                capture=True,
            )
            proc = run(
                [self._xcrun(), "simctl", "bootstatus", udid, "-b"],
                check=False,
                capture=True,
                timeout=180,
            )
            if proc.returncode != 0:
                raise E2EException(
                    f"Could not boot simulator {udid}:\n"
                    f"{tail_text(proc.stdout or '', 30)}"
                )
        else:
            self.con.log(f"Simulator already booted: {selected['name']} ({udid}).")
        if sys.platform == "darwin" and which("open"):
            run(["open", "-a", "Simulator"], check=False, capture=True)
        self.save_state("ios", udid, selected["name"])
        self.con.ok(f"Simulator ready: {udid}")
        self.con.plain(
            f"    Deep links use {self.cfg.app_scheme}:// "
            "(approve once if iOS asks)."
        )
        return Device("ios", udid, selected["name"])

    def _ios_open_url(self, serial: str, url: str) -> None:
        proc = run(
            [self._xcrun(), "simctl", "openurl", serial, url],
            check=False,
            capture=True,
        )
        if proc.returncode != 0:
            raise E2EException(
                f"Could not open deep link in simulator:\n"
                f"{tail_text(proc.stdout or '', 20)}"
            )

    def _ios_app_installed(self, serial: str) -> bool:
        proc = run(
            [
                self._xcrun(),
                "simctl",
                "get_app_container",
                serial,
                self.cfg.app_id,
                "app",
            ],
            check=False,
            capture=True,
        )
        return proc.returncode == 0

    # -- Android -----------------------------------------------------------

    def android_sdk(self) -> Optional[Path]:
        candidates: List[Path] = []
        for key in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
            value = os.environ.get(key)
            if value:
                candidates.append(Path(value))
        for tool in ("adb", "emulator"):
            path = which(tool)
            if path:
                candidates.append(Path(path).resolve().parent.parent)
        home = Path.home()
        if sys.platform == "darwin":
            candidates.append(home / "Library" / "Android" / "sdk")
        elif os.name == "nt":
            local = os.environ.get("LOCALAPPDATA")
            if local:
                candidates.append(Path(local) / "Android" / "Sdk")
        else:
            candidates.append(home / "Android" / "Sdk")
            candidates.append(Path("/usr/lib/android-sdk"))
        for candidate in candidates:
            adb_name = "adb.exe" if os.name == "nt" else "adb"
            if (candidate / "platform-tools" / adb_name).exists():
                return candidate
        return None

    def _adb(self) -> str:
        sdk = self.android_sdk()
        if sdk is not None:
            name = "adb.exe" if os.name == "nt" else "adb"
            candidate = sdk / "platform-tools" / name
            if candidate.exists():
                return str(candidate)
        return require(
            "adb",
            "Install Android Studio (SDK Platform-Tools) or add it to PATH.",
        )

    def _emulator(self) -> str:
        sdk = self.android_sdk()
        if sdk is not None:
            name = "emulator.exe" if os.name == "nt" else "emulator"
            candidate = sdk / "emulator" / name
            if candidate.exists():
                return str(candidate)
        return require(
            "emulator",
            "Install the Android emulator from Android Studio's SDK Manager.",
        )

    def _android_running(self) -> List[Dict[str, str]]:
        output = run_capture([self._adb(), "devices", "-l"], check=False)
        return parse_adb_devices(output)

    def _ensure_android(self) -> Device:
        adb = self._adb()
        running = self._android_running()
        wanted = self.cfg.device or self.cfg.android_serial
        if wanted:
            for device in running:
                if device["serial"] == wanted:
                    return self._finish_android(adb, device)
            connected = ", ".join(d["serial"] for d in running) or "none"
            raise E2EException(
                f"Android device {wanted!r} is not connected (connected: {connected}).\n"
                "  Start it, or set ANDROID_AVD to launch an emulator by name."
            )

        usable = [device for device in running if device["state"] == "device"]
        if usable:
            preferred = next(
                (
                    device
                    for device in usable
                    if device["serial"].startswith("emulator-")
                ),
                usable[0],
            )
            return self._finish_android(adb, preferred)

        return self._launch_android_emulator(adb)

    def _finish_android(self, adb: str, device: Dict[str, str]) -> Device:
        if device["state"] != "device":
            raise E2EException(
                f"Android device {device['serial']} is {device['state']}.\n"
                "  Unlock it and accept the USB debugging prompt, then retry."
            )
        self.save_state("android", device["serial"], device["serial"])
        self.con.ok(f"Android device ready: {device['serial']}")
        return Device("android", device["serial"], device["serial"])

    def _launch_android_emulator(self, adb: str) -> Device:
        emulator = self._emulator()
        raw = run_capture([emulator, "-list-avds"], check=False)
        avds = [
            line.strip()
            for line in raw.splitlines()
            if line.strip() and not line.startswith("INFO")
        ]
        if not avds:
            raise E2EException(
                "No Android virtual devices (AVDs) found.\n"
                "  Open Android Studio -> Device Manager -> Create device, "
                "then retry."
            )
        avd = self.cfg.android_avd or avds[0]
        if avd not in avds:
            raise E2EException(
                f"Android AVD {avd!r} not found. Available: {', '.join(avds)}"
            )

        self.con.log(f"Launching Android emulator {avd}...")
        self.cfg.dev_dir.mkdir(parents=True, exist_ok=True)
        popen_kwargs: Dict[str, Any] = {}
        if os.name == "nt":
            popen_kwargs["creationflags"] = getattr(
                subprocess, "CREATE_NEW_PROCESS_GROUP", 0
            )
        else:
            popen_kwargs["start_new_session"] = True
        with (self.cfg.dev_dir / "emulator.log").open("ab", buffering=0) as log:
            subprocess.Popen(
                [emulator, "-avd", avd, "-no-snapshot-save", "-no-boot-anim"],
                stdout=log,
                stderr=subprocess.STDOUT,
                **popen_kwargs,
            )

        deadline = time.time() + 180
        serial: Optional[str] = None
        while time.time() < deadline:
            for device in self._android_running():
                if (
                    device["state"] == "device"
                    and device["serial"].startswith("emulator-")
                ):
                    serial = device["serial"]
                    break
            if serial:
                break
            time.sleep(2)
        if not serial:
            raise E2EException(
                "The Android emulator did not appear within 180s.\n"
                f"  Log: {self.cfg.dev_dir / 'emulator.log'}"
            )

        run(
            [adb, "-s", serial, "wait-for-device"],
            check=False,
            capture=True,
            timeout=180,
        )
        boot_deadline = time.time() + 180
        booted = False
        while time.time() < boot_deadline:
            output = run_capture(
                [adb, "-s", serial, "shell", "getprop", "sys.boot_completed"],
                check=False,
            ).strip()
            if output == "1":
                booted = True
                break
            time.sleep(2)
        if not booted:
            raise E2EException(
                f"Android emulator {serial} did not finish booting within 180s.\n"
                f"  Log: {self.cfg.dev_dir / 'emulator.log'}"
            )
        return self._finish_android(adb, {"serial": serial, "state": "device"})

    def _android_open_url(self, serial: str, url: str) -> None:
        proc = run(
            [
                self._adb(),
                "-s",
                serial,
                "shell",
                "am",
                "start",
                "-a",
                "android.intent.action.VIEW",
                "-d",
                url,
            ],
            check=False,
            capture=True,
        )
        output = proc.stdout or ""
        if proc.returncode != 0 or "Error:" in output:
            raise E2EException(
                f"Could not open deep link on {serial}:\n{tail_text(output, 20)}"
            )

    def _android_app_installed(self, serial: str) -> bool:
        proc = run(
            [
                self._adb(),
                "-s",
                serial,
                "shell",
                "pm",
                "list",
                "packages",
                self.cfg.app_id,
            ],
            check=False,
            capture=True,
        )
        return self.cfg.app_id in (proc.stdout or "")

    # -- public ------------------------------------------------------------

    def ensure(self) -> Device:
        platform = self.resolve_platform()
        if platform == "none":
            raise E2EException("Device support is disabled (PLATFORM=none).")
        if platform == "ios":
            if sys.platform != "darwin":
                raise E2EException(
                    "The iOS simulator only works on macOS. "
                    "Use PLATFORM=android on Windows/Linux."
                )
            return self._ensure_ios()
        if platform == "android":
            return self._ensure_android()
        raise E2EException(f"Unknown platform: {platform}")

    def command_target(self) -> Tuple[str, str]:
        """Return (platform, id) for printing a deep-link command without booting."""
        platform = self.resolve_platform()
        if platform == "ios":
            return "ios", self.cfg.device or self.cfg.sim_udid or "booted"
        if platform == "android":
            for device in self._android_running():
                if device["state"] == "device":
                    return "android", device["serial"]
            return "android", "<android-serial>"
        raise E2EException("Device support is disabled (PLATFORM=none).")

    def open_url(self, device: Device, url: str) -> None:
        if device.platform == "ios":
            self._ios_open_url(device.serial, url)
        else:
            self._android_open_url(device.serial, url)

    def app_installed(self, device: Device) -> bool:
        if device.platform == "ios":
            return self._ios_app_installed(device.serial)
        return self._android_app_installed(device.serial)

    def save_state(self, platform: str, serial: str, name: str) -> None:
        self.cfg.dev_dir.mkdir(parents=True, exist_ok=True)
        payload = {"platform": platform, "serial": serial, "name": name}
        self.cfg.device_state.write_text(
            json.dumps(payload, indent=2) + "\n", encoding="utf-8"
        )

    def selected_from_state(self) -> Optional[Device]:
        try:
            data = json.loads(self.cfg.device_state.read_text(encoding="utf-8"))
            return Device(
                str(data["platform"]), str(data["serial"]), str(data.get("name", ""))
            )
        except (OSError, ValueError, KeyError):
            return None

    def describe(self) -> str:
        try:
            platform = self.resolve_platform()
        except E2EException as exc:
            return f"unavailable ({exc})"
        if platform == "ios":
            try:
                devices = self._ios_devices()
            except E2EException as exc:
                return f"unavailable ({exc})"
            try:
                selected = (
                    select_ios_device(
                        devices,
                        self.cfg.device or self.cfg.sim_udid,
                        self.cfg.sim_name,
                    )
                    if devices
                    else None
                )
            except E2EException as exc:
                return f"unavailable ({exc})"
            if selected is None:
                return "no simulator found"
            installed = self._ios_app_installed(selected["udid"])
            state = selected.get("state", "Unknown")
            return (
                f"{selected['name']} ({selected['udid']}) [{state}] "
                f"app {'installed' if installed else 'not installed'}"
            )
        if platform == "android":
            try:
                running = self._android_running()
            except E2EException as exc:
                return f"unavailable ({exc})"
            if not running:
                return "no running device (run `e2e device`)"
            selected = self.selected_from_state()
            if selected is None or not any(
                d["serial"] == selected.serial for d in running
            ):
                selected = Device("android", running[0]["serial"])
            installed = self._android_app_installed(selected.serial)
            return (
                f"{selected.serial} [device] "
                f"app {'installed' if installed else 'not installed'}"
            )
        return platform


# ---------------------------------------------------------------------------
# App runner
# ---------------------------------------------------------------------------


class AppRunner:
    def __init__(self, cfg: Config, con: Console) -> None:
        self.cfg = cfg
        self.con = con

    def api_base_url_for(self, device: Device) -> str:
        if device.platform != "android":
            return self.cfg.api_base_url
        if self.cfg.android_api_base_url:
            return self.cfg.android_api_base_url
        if device.serial.startswith("emulator-"):
            # The Android emulator reaches the host machine through 10.0.2.2.
            return f"http://10.0.2.2:{self.cfg.api_port}"
        return self.cfg.api_base_url

    def run(self, device: Device) -> int:
        if not self.cfg.app_dir.exists():
            raise E2EException(
                f"App repo not found: {self.cfg.app_dir}\n"
                "  Run `e2e setup --clone` or check APP_DIR in config.env."
            )
        if device.platform == "android":
            if not android_cleartext_ok(self.cfg.app_dir):
                raise E2EException(
                    "Android debug builds block cleartext HTTP, so the app cannot "
                    "reach the local backend.\n"
                    "  Add android:usesCleartextTraffic=\"true\" to the "
                    "<application> element in\n"
                    "  mobile_app/android/app/src/debug/AndroidManifest.xml."
                )
            if (
                not device.serial.startswith("emulator-")
                and not self.cfg.android_api_base_url
            ):
                raise E2EException(
                    "A physical Android device cannot reach localhost on your computer.\n"
                    "  Set ANDROID_API_BASE_URL=http://<your-lan-ip>:"
                    f"{self.cfg.api_port} in config.local.env, then retry."
                )
        api_base_url = self.api_base_url_for(device)
        cmd = command_argv(
            "flutter",
            "run",
            "-d",
            device.serial,
            "--flavor",
            self.cfg.app_flavor,
            f"--dart-define=API_BASE_URL={api_base_url}",
        )
        self.con.log(f"Running app on {device.serial} against {api_base_url}")
        self.con.plain("    (Ctrl-C stops this run; relaunch with `e2e app` or VS Code)")
        try:
            return subprocess.call(cmd, cwd=str(self.cfg.app_dir))
        except FileNotFoundError as exc:
            raise E2EException(
                "Flutter was not found. Install Flutter and put it on PATH."
            ) from exc


# ---------------------------------------------------------------------------
# Presentation helpers
# ---------------------------------------------------------------------------


def format_table(
    headers: Sequence[str], rows: Sequence[Sequence[str]], right_align: Optional[set] = None
) -> str:
    right_align = right_align or set()
    string_rows = [[str(cell) for cell in row] for row in rows]
    widths = [len(header) for header in headers]
    for row in string_rows:
        for index, cell in enumerate(row):
            if index < len(widths):
                widths[index] = max(widths[index], len(cell))
    top = "+" + "+".join("-" * (width + 2) for width in widths) + "+"
    header = (
        "| "
        + " | ".join(
            f"{name:<{widths[index]}}" for index, name in enumerate(headers)
        )
        + " |"
    )
    separator = "+" + "+".join("-" * (width + 2) for width in widths) + "+"
    lines = [top, header, separator]
    for row in string_rows:
        cells = []
        for index, cell in enumerate(row):
            width = widths[index]
            if index in right_align:
                cells.append(f"{cell:>{width}}")
            else:
                cells.append(f"{cell:<{width}}")
        lines.append("| " + " | ".join(cells) + " |")
    lines.append(separator)
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------


def _check_repo_code(cfg: Config, backend_only: bool) -> None:
    if not cfg.core_dir.exists():
        raise E2EException(
            f"Backend repo not found: {cfg.core_dir}\n"
            f"  git clone {cfg.core_repo} {cfg.core_dir}"
        )
    controller = (
        cfg.core_dir
        / "coffeecard"
        / "CoffeeCard.WebApi"
        / "Controllers"
        / "v2"
        / "AccountController.cs"
    )
    email_service = (
        cfg.core_dir
        / "coffeecard"
        / "CoffeeCard.Library"
        / "Services"
        / "v2"
        / "EmailService.cs"
    )
    if not _file_contains(controller, "CompleteRegistration"):
        raise E2EException(
            "analog-core does not contain the registration endpoint.\n"
            f"  Check out the registration branch, e.g. "
            f"`git -C {cfg.core_dir} switch {cfg.core_ref or 'om/magic-link-registration'}`."
        )
    if not _file_contains(email_service, "SendRegistrationLink"):
        raise E2EException(
            "analog-core does not contain the registration email.\n"
            f"  Check out the registration branch in {cfg.core_dir}."
        )

    if backend_only:
        return
    if not cfg.app_dir.exists():
        raise E2EException(
            f"App repo not found: {cfg.app_dir}\n"
            f"  git clone {cfg.app_repo} {cfg.app_dir}"
        )
    router = cfg.app_dir / "lib" / "app" / "router.dart"
    if not _file_contains(router, "register/:token"):
        raise E2EException(
            "mobile_app does not contain the /register/:token route.\n"
            f"  Check out a branch with the registration flow in {cfg.app_dir}."
        )
    launch = cfg.app_dir / ".vscode" / "launch.json"
    if not _file_contains(launch, "API_BASE_URL=http://localhost:8080"):
        cfg.values.setdefault("_warn_launch", "1")


def _file_contains(path: Path, needle: str) -> bool:
    try:
        return needle in path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False


def android_cleartext_ok(app_dir: Path) -> bool:
    """Android 9+ blocks plain HTTP unless the debug manifest opts in."""
    for relative in (
        Path("android/app/src/debug/AndroidManifest.xml"),
        Path("android/app/src/main/AndroidManifest.xml"),
    ):
        path = app_dir / relative
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if 'usesCleartextTraffic="true"' in text or "networkSecurityConfig" in text:
            return True
    return False


def cmd_check(
    cfg: Config,
    con: Console,
    backend_only: bool = False,
    require_device: bool = True,
) -> int:
    if sys.version_info < MIN_PYTHON:
        raise E2EException(
            f"Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]}+ is required "
            f"(running {sys.version.split()[0]})."
        )
    require("git")
    require("dotnet", "Install the .NET SDK (10.x).")
    if not backend_only:
        require("flutter", "Install Flutter 3.47+ and put it on PATH.")

    docker = Docker(cfg, con)
    docker.require()
    compose_version = docker.compose_version()
    if not compose_version:
        raise E2EException(
            "`docker compose` is not available. Install the Docker Compose plugin."
        )

    if not cfg.compose_file.exists():
        raise E2EException(f"Compose file not found: {cfg.compose_file}")
    if not (cfg.root / "db" / "seed.sql").exists():
        raise E2EException("Missing db/seed.sql")

    _check_repo_code(cfg, backend_only)
    if cfg.values.get("_warn_launch"):
        con.warn(
            "VS Code 'Debug mode (local backend)' config not found in "
            f"{cfg.app_dir}/.vscode/launch.json."
        )
        con.warn("Use `e2e app` or add the config shown in LOCAL-E2E.md.")

    platform = "-"
    if not backend_only and require_device and cfg.platform != "none":
        devices = Devices(cfg, con)
        platform = devices.resolve_platform()
        if platform == "ios" and sys.platform != "darwin":
            raise E2EException("PLATFORM=ios requires macOS with Xcode.")
        if platform == "android":
            try:
                devices._adb()
            except E2EException as exc:
                raise E2EException(
                    f"{exc}\n  Android development also needs the SDK Platform-Tools."
                ) from exc
            if not android_cleartext_ok(cfg.app_dir):
                con.warn(
                    "Android debug builds block cleartext HTTP. Add "
                    'android:usesCleartextTraffic="true" to the <application> '
                    "element in mobile_app/android/app/src/debug/AndroidManifest.xml."
                )

    con.plain("")
    con.log(f"Workspace: {cfg.root}")
    con.log(f"Backend:    {cfg.core_dir} ({git_branch(cfg.core_dir)})")
    if not backend_only:
        con.log(f"App:        {cfg.app_dir} ({git_branch(cfg.app_dir)})")
        con.log(f"Device:     {platform}")
    con.log(f"API:        {cfg.api_base_url}")
    con.log(f"MailHog:    {cfg.mailhog_url}")
    con.plain("")
    con.ok("Prerequisites look good.")
    return 0


def cmd_setup(cfg: Config, con: Console, clone: bool = False) -> int:
    missing: List[Tuple[str, str, str, Path]] = []
    for label, path, url, ref in (
        ("analog-core", cfg.core_dir, cfg.core_repo, cfg.core_ref),
        ("mobile_app", cfg.app_dir, cfg.app_repo, cfg.app_ref),
    ):
        if path.exists():
            con.ok(f"{label} found: {path}")
            continue
        if clone:
            con.log(f"Cloning {label} into {path} ...")
            run(["git", "clone", url, str(path)], timeout=900)
            if ref:
                check = run(
                    [
                        "git",
                        "-C",
                        str(path),
                        "rev-parse",
                        "--verify",
                        f"origin/{ref}",
                    ],
                    check=False,
                    capture=True,
                )
                if check.returncode == 0:
                    run(["git", "-C", str(path), "switch", ref])
                else:
                    con.warn(
                        f"Branch {ref} not found in {label}; "
                        "leaving the default branch checked out."
                    )
            con.ok(f"{label} cloned.")
        else:
            missing.append((label, url, ref, path))

    if missing:
        con.plain("")
        con.warn("Missing repositories. Clone them with:")
        for label, url, ref, path in missing:
            con.plain(f"  git clone {url} {path}")
            if ref:
                con.plain(f"  git -C {path} switch {ref}")
        con.plain("")
        con.plain("Or let this tool do it:  e2e setup --clone")
        return 1

    return cmd_check(cfg, con, backend_only=False)


def cmd_up(
    cfg: Config,
    con: Console,
    backend_only: bool = False,
    no_device: bool = False,
) -> int:
    skip_device = backend_only or no_device or cfg.no_device or cfg.platform == "none"
    cmd_check(cfg, con, backend_only=backend_only, require_device=not skip_device)
    docker = Docker(cfg, con)
    database = Database(cfg, docker, con)
    mailhog = MailHog(cfg, con)
    backend = Backend(cfg, con)

    docker.up()
    con.log("Waiting for MSSQL...")
    database.wait_ready(120)
    con.ok(f"MSSQL ready (localhost:{cfg.db_port}, user {cfg.db_user})")
    con.log("Waiting for MailHog...")
    mailhog.wait_ready(60)
    con.ok(f"MailHog ready ({cfg.mailhog_url})")

    backend.start()
    database.seed()

    if not skip_device:
        Devices(cfg, con).ensure()

    con.plain("")
    cmd_status(cfg, con)
    con.plain("")
    con.plain(
        '  App:     VS Code -> "Debug mode (local backend)", or: e2e app'
    )
    con.plain(f"  Emails:  {cfg.mailhog_url}")
    con.plain(f"  Swagger: {cfg.api_base_url}/swagger")
    con.plain("")
    return 0


def cmd_app(cfg: Config, con: Console) -> int:
    cmd_check(cfg, con, backend_only=False, require_device=True)
    devices = Devices(cfg, con)
    device = devices.ensure()
    return AppRunner(cfg, con).run(device)


def cmd_dev(
    cfg: Config,
    con: Console,
    backend_only: bool = False,
    no_device: bool = False,
) -> int:
    code = cmd_up(cfg, con, backend_only=backend_only, no_device=no_device)
    if code != 0:
        return code
    return cmd_app(cfg, con)


def cmd_deps(cfg: Config, con: Console) -> int:
    require("git")
    require("dotnet")
    docker = Docker(cfg, con)
    docker.require()
    database = Database(cfg, docker, con)
    mailhog = MailHog(cfg, con)
    docker.up()
    con.log("Waiting for MSSQL...")
    database.wait_ready(120)
    con.ok(f"MSSQL ready (localhost:{cfg.db_port}, user {cfg.db_user})")
    mailhog.wait_ready(60)
    con.ok(f"MailHog ready ({cfg.mailhog_url})")
    return 0


def cmd_backend(cfg: Config, con: Console, action: str) -> int:
    if action == "stop":
        Backend(cfg, con).stop()
        return 0
    require("git")
    require("dotnet")
    docker = Docker(cfg, con)
    docker.require()
    database = Database(cfg, docker, con)
    mailhog = MailHog(cfg, con)
    docker.up()
    con.log("Waiting for MSSQL...")
    database.wait_ready(120)
    mailhog.wait_ready(60)
    backend = Backend(cfg, con)
    if action == "restart":
        backend.stop()
    backend.start()
    database.seed()
    return 0


def cmd_seed(cfg: Config, con: Console) -> int:
    require("git")
    docker = Docker(cfg, con)
    docker.require()
    database = Database(cfg, docker, con)
    database.wait_ready(120)
    database.seed()
    return 0


def cmd_reset(cfg: Config, con: Console) -> int:
    require("git")
    docker = Docker(cfg, con)
    docker.require()
    database = Database(cfg, docker, con)
    mailhog = MailHog(cfg, con)
    database.wait_ready(120)
    database.reset()
    if mailhog.ok():
        mailhog.delete_all()
    con.ok("Local E2E data reset. MailHog inbox cleared.")
    return 0


def cmd_down(cfg: Config, con: Console) -> int:
    Backend(cfg, con).stop()
    docker = Docker(cfg, con)
    if docker.available():
        con.log("Stopping MSSQL and MailHog...")
        docker.stop()
    con.ok("Local E2E stack stopped. Data is preserved; use `e2e up` to restart.")
    return 0


def cmd_nuke(cfg: Config, con: Console) -> int:
    Backend(cfg, con).stop()
    docker = Docker(cfg, con)
    if docker.available():
        con.log("Removing containers and volumes...")
        docker.down(volumes=True)
    if cfg.dev_dir.parent == cfg.root and cfg.dev_dir.name == ".dev":
        shutil.rmtree(cfg.dev_dir, ignore_errors=True)
    con.ok("Local E2E stack destroyed. Run `e2e up` to rebuild from scratch.")
    return 0


def cmd_device(cfg: Config, con: Console) -> int:
    Devices(cfg, con).ensure()
    return 0


def cmd_status(cfg: Config, con: Console) -> int:
    con.plain("")
    con.plain("Local E2E status")
    con.plain(f"  workspace   {cfg.root}")

    backend = Backend(cfg, con)
    backend_state = "UP" if backend.is_up() else "DOWN"
    pid = backend.read_pid()
    suffix = f" (pid {pid})" if pid else ""
    con.plain(f"  backend     {cfg.api_base_url}  {backend_state}{suffix}")

    mailhog = MailHog(cfg, con)
    mailhog_state = "UP" if mailhog.ok() else "DOWN"
    con.plain(
        f"  mailhog     {cfg.mailhog_url}  {mailhog_state} "
        f"messages: {mailhog.count()}"
    )

    docker = Docker(cfg, con)
    con.plain("  services")
    if docker.available():
        output = docker.ps()
        for line in output.splitlines() or ["  (none)"]:
            con.plain(f"    {line}")
    else:
        con.plain("    Docker is not running.")

    devices = Devices(cfg, con)
    con.plain(f"  device      {devices.describe()}")
    con.plain("")
    con.plain(
        "  next: e2e app   |   e2e link   |   e2e smoke   |   e2e logs"
    )
    con.plain("")
    return 0


def cmd_list_users(cfg: Config, con: Console) -> int:
    require("git")
    docker = Docker(cfg, con)
    docker.require()
    database = Database(cfg, docker, con)
    database.wait_ready(60)
    table = database.list_users()
    con.plain("")
    con.plain(table)
    con.plain("")
    return 0


def cmd_smoke(cfg: Config, con: Console) -> int:
    docker = Docker(cfg, con)
    database = Database(cfg, docker, con)
    mailhog = MailHog(cfg, con)
    backend = Backend(cfg, con)

    if not backend.is_up():
        docker.require()
        docker.up()
        database.wait_ready(120)
        mailhog.wait_ready(60)
        backend.start()
        database.seed()
    if not backend.is_up():
        raise E2EException(
            f"Backend is not healthy at {cfg.api_base_url}. Run `e2e up` first."
        )

    email = f"smoke+{int(time.time())}@example.com"
    con.log(f"Smoke test with {email}")
    status, _ = http_request(
        "POST",
        f"{cfg.api_base_url}/api/v2/account/login",
        body={"email": email, "loginType": "App"},
    )
    if status != 204:
        raise E2EException(f"Login returned HTTP {status} (expected 204).")

    con.log("Waiting for the welcome email in MailHog...")
    message_id, link = mailhog.find_registration_for(email, timeout=20)
    if not link:
        raise E2EException(f"No registration email for {email} appeared in MailHog.")
    token = link.rstrip("/").rsplit("/", 1)[-1]
    con.log(f"Registering with token {token} ...")
    status, payload = http_request(
        "POST",
        f"{cfg.api_base_url}/api/v2/account/register",
        body={"token": token, "name": "Smoke Test", "programmeId": 1},
    )
    if status != 200:
        raise E2EException(
            f"Registration returned HTTP {status}: "
            f"{payload.decode('utf-8', 'replace')}"
        )
    data = json.loads(payload.decode("utf-8"))
    if not data.get("jwt") or not data.get("refreshToken"):
        raise E2EException(
            "Registration response did not contain tokens: "
            f"{payload.decode('utf-8', 'replace')}"
        )

    database.sqlcmd(
        "-b",
        "-Q",
        "DELETE FROM dbo.Tokens WHERE User_Id IN "
        f"(SELECT Id FROM dbo.Users WHERE Email = '{email}'); "
        f"DELETE FROM dbo.Tokens WHERE Email = '{email}'; "
        f"DELETE FROM dbo.Users WHERE Email = '{email}';",
        capture=True,
    )
    if message_id:
        mailhog.delete_message(message_id)
    con.ok("SMOKE PASS - login email, registration email and token exchange all work.")
    return 0


def cmd_link(cfg: Config, con: Console, open_link: bool = False, show_cmd: bool = False) -> int:
    mailhog = MailHog(cfg, con)
    link = mailhog.newest_link()
    if show_cmd:
        platform, target = Devices(cfg, con).command_target()
        if platform == "android":
            con.plain(
                "adb -s "
                f"{target} shell am start -a android.intent.action.VIEW -d "
                f'"{link}"'
            )
        else:
            con.plain(f'xcrun simctl openurl {target} "{link}"')
        return 0
    if not open_link:
        con.plain(link)
        return 0
    devices = Devices(cfg, con)
    device = devices.ensure()
    devices.open_url(device, link)
    con.ok(f"Opened {link}")
    return 0


def cmd_email(cfg: Config, con: Console) -> int:
    mailhog = MailHog(cfg, con)
    if not mailhog.open_in_browser():
        con.plain(cfg.mailhog_url)
    return 0


def cmd_logs(cfg: Config, con: Console, lines: int = 200) -> int:
    Backend(cfg, con).follow_log(lines)
    return 0


def cmd_config(cfg: Config, con: Console) -> int:
    con.plain("")
    con.plain("Resolved local E2E configuration")
    for key, value in cfg.describe():
        con.plain(f"  {key:<12} {value}")
    con.plain("")
    con.plain("Precedence: environment > config.local.env > config.env")
    con.plain("")
    return 0


def cmd_doctor(cfg: Config, con: Console) -> int:
    con.plain("")
    con.plain(f"Python      {sys.version.split()[0]} ({sys.executable})")
    for label, cmd in (
        ("Git", ["git", "--version"]),
        ("Docker", ["docker", "--version"]),
        ("Docker Compose", ["docker", "compose", "version"]),
        ("dotnet", ["dotnet", "--version"]),
        ("Flutter", ["flutter", "--version"]),
    ):
        if not which(cmd[0]):
            con.plain(f"{label:<14} (not found)")
            continue
        proc = run(command_argv(*cmd), check=False, capture=True, timeout=60)
        first = (proc.stdout or proc.stderr or "").splitlines()
        con.plain(f"{label:<14} {first[0] if first else '(no output)'}")
    con.plain("")
    return cmd_check(cfg, con, backend_only=False)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def add_common(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--platform",
        choices=["auto", "ios", "android", "none"],
        help="override PLATFORM for this command",
    )
    parser.add_argument(
        "--device",
        metavar="SERIAL",
        help="use a specific simulator UDID or Android serial",
    )
    parser.add_argument(
        "--no-device",
        action="store_true",
        help="do not boot/require a simulator or emulator",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="e2e",
        description="Local E2E environment for analog-core + mobile_app.",
        epilog="Configuration: config.env (override in config.local.env or the environment).",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")
    parser.add_argument("--verbose", action="store_true", help="print commands")
    parser.add_argument("--no-color", action="store_true", help="disable ANSI colors")

    sub = parser.add_subparsers(dest="command", metavar="command")

    check = sub.add_parser("check", help="validate tools, repos and registration code")
    check.add_argument("--backend-only", action="store_true")
    add_common(check)

    setup = sub.add_parser("setup", help="check repos and optionally clone them")
    setup.add_argument("--clone", action="store_true", help="clone missing repos")

    up = sub.add_parser("up", help="start Docker, backend, seed data and a device")
    up.add_argument("--backend-only", action="store_true")
    add_common(up)

    dev = sub.add_parser("dev", help="`up`, then run the app in the foreground")
    dev.add_argument("--backend-only", action="store_true")
    add_common(dev)

    app = sub.add_parser("app", help="run the app against the local backend")
    add_common(app)

    backend = sub.add_parser("backend", help="start/stop/restart the backend")
    backend.add_argument("action", choices=["start", "stop", "restart"])

    sub.add_parser("deps", help="start MSSQL and MailHog only")

    seed = sub.add_parser("seed", help="apply the idempotent dummy seed")
    _ = seed

    sub.add_parser("reset", help="remove test accounts, re-seed and clear MailHog")
    sub.add_parser("down", help="stop the backend and Docker services")
    sub.add_parser("nuke", help="remove containers, volumes and runtime state")

    device = sub.add_parser("device", help="boot/select the simulator or emulator")
    add_common(device)
    sim = sub.add_parser("sim", help="alias for `device`")
    add_common(sim)

    sub.add_parser("status", help="show stack status")
    sub.add_parser("list-users", help="list registered users")
    sub.add_parser("smoke", help="backend/email/registration smoke test")
    sub.add_parser("email", help="open the MailHog inbox")
    sub.add_parser("config", help="print resolved configuration")
    sub.add_parser("doctor", help="print tool versions and run checks")

    logs = sub.add_parser("logs", help="tail the backend log")
    logs.add_argument("-n", "--lines", type=int, default=200)

    link = sub.add_parser("link", help="print the newest magic deep link")
    link.add_argument("--open", action="store_true", help="open it on the device")
    link.add_argument("--cmd", action="store_true", help="print the platform command")

    open_link = sub.add_parser("open-link", help="open the newest magic link")
    open_link.add_argument("--cmd", action="store_true")
    add_common(open_link)

    restart = sub.add_parser("restart-backend", help="restart just the backend")
    _ = restart

    return parser


GLOBAL_FLAGS = ("--no-color", "--verbose")


def normalize_global_flags(argv: Sequence[str]) -> List[str]:
    """Allow global flags before or after the subcommand.

    argparse normally rejects `e2e config --no-color` because --no-color is
    declared on the top-level parser. Moving those flags to the front keeps
    both `e2e --no-color config` and `e2e config --no-color` working.
    """
    flags: List[str] = []
    rest: List[str] = []
    for argument in argv:
        if argument in GLOBAL_FLAGS:
            flags.append(argument)
        else:
            rest.append(argument)
    return flags + rest


def main(argv: Optional[Sequence[str]] = None) -> int:
    global VERBOSE
    parser = build_parser()
    raw_argv = list(sys.argv[1:] if argv is None else argv)
    args = parser.parse_args(normalize_global_flags(raw_argv))
    VERBOSE = bool(getattr(args, "verbose", False))
    con = Console(color=not getattr(args, "no_color", False), verbose=VERBOSE)
    if sys.version_info < MIN_PYTHON:
        con.error(
            f"Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]}+ is required "
            f"(running {sys.version.split()[0]})."
        )
        return 1

    overrides: Dict[str, str] = {}
    if getattr(args, "platform", None):
        overrides["PLATFORM"] = args.platform
    if getattr(args, "device", None):
        overrides["DEVICE"] = args.device
    if getattr(args, "no_device", False):
        overrides["NO_DEVICE"] = "1"

    try:
        cfg = Config(ROOT, overrides)
        command = args.command
        if command == "check":
            return cmd_check(
                cfg,
                con,
                backend_only=args.backend_only,
                require_device=not args.no_device,
            )
        if command == "setup":
            return cmd_setup(cfg, con, clone=args.clone)
        if command == "up":
            return cmd_up(
                cfg,
                con,
                backend_only=args.backend_only,
                no_device=args.no_device,
            )
        if command == "dev":
            return cmd_dev(
                cfg,
                con,
                backend_only=args.backend_only,
                no_device=args.no_device,
            )
        if command == "app":
            return cmd_app(cfg, con)
        if command == "backend":
            return cmd_backend(cfg, con, args.action)
        if command == "restart-backend":
            return cmd_backend(cfg, con, "restart")
        if command == "deps":
            return cmd_deps(cfg, con)
        if command == "seed":
            return cmd_seed(cfg, con)
        if command == "reset":
            return cmd_reset(cfg, con)
        if command == "down":
            return cmd_down(cfg, con)
        if command == "nuke":
            return cmd_nuke(cfg, con)
        if command in ("device", "sim"):
            return cmd_device(cfg, con)
        if command == "status":
            return cmd_status(cfg, con)
        if command == "list-users":
            return cmd_list_users(cfg, con)
        if command == "smoke":
            return cmd_smoke(cfg, con)
        if command == "email":
            return cmd_email(cfg, con)
        if command == "logs":
            return cmd_logs(cfg, con, lines=args.lines)
        if command == "config":
            return cmd_config(cfg, con)
        if command == "doctor":
            return cmd_doctor(cfg, con)
        if command == "link":
            return cmd_link(cfg, con, open_link=args.open, show_cmd=args.cmd)
        if command == "open-link":
            return cmd_link(cfg, con, open_link=True, show_cmd=args.cmd)
        parser.print_help()
        return 1
    except E2EException as exc:
        con.error(str(exc))
        return 1
    except KeyboardInterrupt:
        con.warn("Interrupted.")
        return 130


if __name__ == "__main__":
    sys.exit(main())
