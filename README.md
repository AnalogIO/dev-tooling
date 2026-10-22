# analog-dev

One-command local development environment for the new Analog coffee card stack:

- [`analog-core`](https://github.com/AnalogIO/analog-core) — .NET backend
- [`mobile_app`](https://github.com/AnalogIO/mobile_app) — Flutter app

It starts MSSQL + [MailHog](https://github.com/mailhog/MailHog) in Docker, builds and
runs the backend, applies an idempotent seed, boots an iOS simulator or Android
emulator, and launches the Flutter app against the local API. It also has a
backend/email/registration smoke test that needs no UI.

The legacy `coffeecard_app` is **not** part of this environment and is not tracked
in this repository.

## Quick start

Prerequisites are listed below. Start Docker first, then:

```sh
git clone <this-repo-url> analog-dev
cd analog-dev

./e2e setup --clone    # clone analog-core + mobile_app if missing
./e2e up               # Docker + backend + seed + device
./e2e app              # flutter run against the local backend
```

On Windows use `.\e2e.cmd` instead of `./e2e`:

```bat
.\e2e.cmd setup --clone
.\e2e.cmd up
.\e2e.cmd app
```

If you already have `analog-core/` and `mobile_app/` next to this README:

```sh
./e2e check
./e2e up
```

`make` is optional. Every command has a Make target for people who prefer it
(`make up`, `make app`, `make smoke`, ...). Windows does not need `make`; the
`.\e2e.cmd` launcher works from PowerShell or `cmd.exe`.

Once the stack is up:

- API: <http://localhost:8080> (Swagger at `/swagger`)
- Emails: <http://127.0.0.1:8025> (MailHog)

In VS Code you can instead use the mobile_app launch configuration
**“Debug mode (local backend)”**, which points at the same API.

## Prerequisites

| Tool | All platforms | Notes |
| --- | --- | --- |
| Python | 3.9+ | Standard library only. On Windows install from python.org and tick “Add to PATH” (or use the `py` launcher). |
| Git | any recent | Needed to clone the two source repositories. |
| Docker | Docker Desktop (macOS/Windows) or Docker Engine + Compose v2 (Linux) | The daemon must be running before `e2e setup`/`e2e up`. |
| .NET SDK | 10.x | `dotnet --version`. |
| Flutter | 3.47+ (Dart 3.13+) | `flutter --version`. |
| Xcode | macOS only | Required for the iOS simulator (`xcrun simctl`). |
| Android Studio | Optional on macOS, required on Windows/Linux | Provides the Android SDK, `adb` and an emulator/AVD. |

Platform notes:

- **macOS** defaults to the iOS simulator. Use `PLATFORM=android e2e up` if you
  prefer an Android emulator instead.
- **Windows/Linux** use an Android emulator. iOS simulators are macOS-only.
- Android emulators need hardware virtualization enabled (WSL2/Hyper-V on
  Windows, KVM on Linux) and at least one AVD created in Android Studio’s
  Device Manager.
- GitHub access to the two AnalogIO repositories is required. SSH keys or
  `gh auth login` both work for `git clone`.

## Daily commands

| Command | What it does |
| --- | --- |
| `./e2e setup` | Check the repos and print clone commands if anything is missing |
| `./e2e setup --clone` | Clone `analog-core` and `mobile_app` if missing, then check |
| `./e2e check` | Validate tools, repos, registration code and device tooling |
| `./e2e up` | Start Docker, backend, seed data and the device |
| `./e2e dev` | `up`, then run the app in the foreground |
| `./e2e app` | Run the app against the local backend (foreground) |
| `./e2e device` | Boot/select the simulator or emulator (`e2e sim` is an alias) |
| `./e2e status` | Show backend, MailHog, Docker and device state |
| `./e2e link` | Print the newest registration/login deep link |
| `./e2e link --open` | Open the newest deep link on the device |
| `./e2e link --cmd` | Print the `xcrun`/`adb` command instead of running it |
| `./e2e email` | Open the MailHog inbox |
| `./e2e logs` | Tail the backend log |
| `./e2e list-users` | List users and unused ticket counts |
| `./e2e smoke` | Login → email → registration smoke test (no UI) |
| `./e2e seed` | Re-apply the dummy seed |
| `./e2e reset` | Remove `@example.com` test accounts, re-seed, clear MailHog |
| `./e2e backend start\|stop\|restart` | Control just the backend |
| `./e2e deps` | Start MSSQL + MailHog only |
| `./e2e down` | Stop the backend and Docker services (keeps data) |
| `./e2e nuke` | Remove containers, DB volume and `.dev/` state |
| `./e2e config` | Print the resolved configuration |
| `./e2e doctor` | Print tool versions and run the checks |

All commands accept `--help`. Device-related commands accept
`--platform ios|android|none` and `--device <serial-or-udid>`.

## Test the registration flow

1. In the app, enter an unused email (for example `new.person@example.com`) and
   tap **Continue**.
2. Open MailHog and open **“Welcome to Analog - complete your registration”**.
3. Launch the link:

   ```sh
   ./e2e open-link
   ```

   `open-link` uses the newest registration **or** login email. Use `./e2e link`
   to print it first, or `./e2e link --cmd` to get the exact simulator/emulator
   command.
4. Enter a name, pick a programme, and tap **Create account**. You land on
   **Tickets**.

To test an existing account, use `john@doe.com` (4 unused seeded tickets). Open
its **“Login to Analog”** email and launch the `/login/auth/<token>` link;
`./e2e open-link` handles that too.

For a busy history, use `many.tickets@analog.local`: 200 tickets (70 unused, 120
used across all six menu items and ~1.5 years, 10 refunded), 25 purchases
covering MobilePay/Free/Voucher/PointOfSale, purchase + voucher + ticket-swipe
receipts, and populated leaderboard statistics. Seeded accounts use password
`1234` for the v1 API login endpoint; the app itself uses the magic link.

The backend/email/registration path can be checked without the UI:

```sh
./e2e smoke
```

It logs in with a throwaway `@example.com` address, waits for the MailHog email,
extracts the registration token, completes registration, verifies the JWT and
refresh token, then removes the test user and email.

## Configuration

Defaults live in [`config.env`](config.env). Override them per command:

```sh
API_PORT=5080 ./e2e up
PLATFORM=android ./e2e up
SIM_NAME="iPhone 17" ./e2e up
```

Or create `config.local.env` (git-ignored) for persistent machine-specific
overrides:

```sh
API_PORT=5080
PLATFORM=android
ANDROID_AVD=Pixel_7_API_35
```

Precedence, highest first: **environment → `config.local.env` → `config.env`**.

Useful settings:

| Setting | Default | Purpose |
| --- | --- | --- |
| `CORE_DIR` / `APP_DIR` | `analog-core` / `mobile_app` | Where the sibling repos live (relative or absolute). |
| `CORE_REF` | `om/magic-link-registration` | Branch checked out by `e2e setup --clone`. Set empty after the registration PR merges. |
| `API_PORT` | `8080` | Backend port. `API_BASE_URL` is derived automatically if left empty. |
| `API_BIND` | `0.0.0.0` | Bind address; `0.0.0.0` lets a physical phone reach the API. |
| `DB_PORT` | `1433` | Host port for MSSQL. Change it if it conflicts with a local SQL Server. |
| `MAILHOG_HTTP_PORT` / `MAILHOG_SMTP_PORT` | `8025` / `1025` | MailHog ports. |
| `PLATFORM` | `auto` | `auto`, `ios`, `android`, or `none`. |
| `SIM_NAME` / `SIM_UDID` | `iPhone 16 Pro` / empty | iOS simulator selection. |
| `ANDROID_AVD` / `ANDROID_SERIAL` | empty | Android emulator/device selection. |
| `ANDROID_API_BASE_URL` | empty | Required for a physical Android phone, e.g. `http://192.168.1.10:8080`. Emulators use `http://10.0.2.2:<API_PORT>` automatically. |
| `APP_ID` / `APP_FLAVOR` / `APP_SCHEME` | dev values | App identifiers for the development flavor. |

For Android emulators the app is launched with `API_BASE_URL=http://10.0.2.2:<port>`
because `localhost` inside the emulator is the emulator itself. For a physical
phone set `ANDROID_API_BASE_URL` to your computer’s LAN address and make sure the
firewall allows the API port.

The development build opts into cleartext HTTP **only in the debug manifest**
(`mobile_app/android/app/src/debug/AndroidManifest.xml`), which is needed for a
plain-HTTP local backend. Release builds keep Android’s secure default. On a
`mobile_app` revision without this opt-in, `e2e check` warns and `e2e app` stops
with the exact file to edit.

## Repository layout

```text
analog-dev/
├── e2e                 # macOS/Linux launcher
├── e2e.cmd             # Windows launcher
├── e2e.py              # the whole tool (Python stdlib only)
├── Makefile            # optional convenience wrappers
├── config.env          # defaults
├── docker-compose.yml  # MSSQL + MailHog
├── db/                 # vendored, idempotent seed/reset SQL
├── tests/              # unit tests for the tool
├── LOCAL-E2E.md        # detailed flow and troubleshooting
├── analog-core/        # separate Git repo, cloned by setup
├── mobile_app/         # separate Git repo, cloned by setup
└── .dev/               # PID/log/device state, created at runtime
```

`analog-core/` and `mobile_app/` are ordinary sibling Git repositories. They are
ignored by this repo and should be committed in their own repositories.

## Troubleshooting

Run `./e2e doctor` first; it prints the tool versions and the same checks as
`./e2e check`.

- **Docker is not running** — start Docker Desktop/daemon, then retry.
- **Port already in use** — `./e2e status` shows the API state. Stop the other
  process or override `API_PORT` (and optionally `API_BASE_URL`), `DB_PORT`,
  `MAILHOG_HTTP_PORT` and `MAILHOG_SMTP_PORT`.
- **Coming from the old make/bash harness** — its `coffeecard` Compose project
  may still hold ports 1433/8025. Stop it once with
  `docker compose -f analog-core/coffeecard/docker-compose.yml --project-directory analog-core/coffeecard down`;
  see [LOCAL-E2E.md](LOCAL-E2E.md#migrating-from-the-old-harness).
- **`analog-core` is missing the registration endpoint** — check out the
  registration branch (`CORE_REF`). `./e2e setup --clone` does this for a fresh
  clone; for an existing checkout run
  `git -C analog-core switch om/magic-link-registration`.
- **Android app cannot reach the backend** — emulators use `10.0.2.2`, which is
  handled automatically. For a physical phone set `ANDROID_API_BASE_URL` to the
  computer’s LAN IP and allow the port through the firewall.
- **Android “Cleartext HTTP traffic not permitted”** — the debug manifest must
  opt in. See the note above; `./e2e check` warns if it is missing.
- **iOS keychain / `-34018` entitlement error** — use `./e2e app` or the VS Code
  launch configuration. Do not install a `flutter build ios --simulator` artifact
  with `simctl install`; that can lose the keychain access `flutter run` sets up.
- **Deep link opens the app but no registration screen** — request a new link
  (tokens are single-use and expire after 30 minutes) and confirm the email
  contains `analogcoffeecard-dev://cafeanalog.dk/register/...`. A backend started
  outside this tool may have the wrong `AnalogAppUrl`.
- **No emails** — check `./e2e status`, then <http://127.0.0.1:8025>. Backend SMTP
  errors are in `./e2e logs`.
- **Backend will not start** — `tail -n 80 .dev/backend.log` and
  `.dev/backend-build.log`.
- **Reset from scratch** — `./e2e nuke && ./e2e up` (destroys the local DB
  volume).

## CI / backend-only use

`./e2e smoke` needs Docker, .NET and the backend repo; it does not need Xcode or
Flutter. Use `./e2e check --backend-only` and `./e2e up --backend-only` for a
headless backend-only environment.

## A note on Git hygiene

- `.gitignore` is intentionally small and only covers state that the E2E tool
  itself creates (`.dev/` and `config.local.env`) plus the two sibling
  repositories that `e2e setup` clones.
- Machine-specific noise (the legacy `coffeecard_app/`, harness logs/artifacts,
  editor state) is kept in `.git/info/exclude`, which is local to each clone and
  never committed.

See [`LOCAL-E2E.md`](LOCAL-E2E.md) for the detailed flow, seed data and
platform-specific troubleshooting.
