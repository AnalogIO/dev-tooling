# Local E2E environment

This folder orchestrates the whole magic-link registration flow locally:

```text
docker compose (MSSQL + MailHog)
        -> analog-core backend (host dotnet run)
        -> db/seed.sql
        -> iOS simulator or Android emulator
        -> mobile_app via `flutter run`
        -> MailHog -> deep link -> registration/login
```

The backend and app stay in their own Git repositories. This repository only
contains the orchestration, seed data and configuration.

## Prerequisites

| Requirement | macOS | Windows | Linux |
| --- | --- | --- | --- |
| Python 3.9+ | yes | yes | yes |
| Git | yes | yes | yes |
| Docker + Compose v2 | Docker Desktop | Docker Desktop (WSL2 backend) | Docker Engine + compose plugin |
| .NET SDK 10 | yes | yes | yes |
| Flutter 3.47+ | yes | yes | yes |
| iOS simulator | Xcode + simulator runtime | — | — |
| Android emulator | Android Studio (optional) | Android Studio + AVD | Android Studio + AVD, KVM enabled |
| GitHub access | yes | yes | yes |

No `make`, `bash`, `lsof`, `nohup` or `open` is required: `e2e.py` uses the
Python standard library and the platform’s own tools. `make` targets are thin
wrappers for convenience.

## Repositories

The two source repositories are ordinary siblings of this folder and are
ignored by this repository:

```text
analog-dev/
├── analog-core/     # backend; needs the magic-link registration PR
├── mobile_app/      # Flutter app; registration flow is on main
├── e2e
├── e2e.py
├── config.env
├── docker-compose.yml
├── db/
├── tests/
└── LOCAL-E2E.md
```

For a fresh checkout:

```sh
./e2e setup --clone
```

This clones `CORE_REPO` and `APP_REPO` into `CORE_DIR`/`APP_DIR` and, when the
configured `CORE_REF` exists, checks it out (`om/magic-link-registration` by
default). `e2e setup` without `--clone` only checks and prints the exact commands
if something is missing.

If you prefer to clone manually:

```sh
git clone https://github.com/AnalogIO/analog-core.git analog-core
git -C analog-core switch om/magic-link-registration
git clone https://github.com/AnalogIO/mobile_app.git mobile_app
```

The check is based on code, not branch names, so it keeps working after the PRs
merge:

- `analog-core`: `CompleteRegistration` endpoint and `SendRegistrationLink` email
- `mobile_app`: `/register/:token` route and the local-backend launch config

## Quick start

Start Docker first, then:

```sh
./e2e up
```

On Windows:

```bat
.\e2e.cmd up
```

`up` does, in order:

1. `e2e check`
2. start MSSQL + MailHog and wait for both
3. `dotnet build` the backend and start the built DLL detached
4. apply `db/seed.sql`
5. boot/select the iOS simulator or Android emulator
6. print the status and URLs

Then run the app:

```sh
./e2e app
```

`e2e app` is a normal foreground `flutter run`; Ctrl-C stops the attached run.
Relaunch it with `e2e app` or the VS Code configuration. `e2e dev` combines
`up` and `app`.

Open:

- MailHog: <http://127.0.0.1:8025>
- API: <http://localhost:8080> (Swagger at `/swagger`)

## Test the flow

1. In the app, enter an unused email (for example `new.person@example.com`) and
   tap **Continue**.
2. Open MailHog and open **“Welcome to Analog - complete your registration”**.
3. Launch the link:

   ```sh
   ./e2e open-link
   ```

   `open-link` opens the newest registration **or** login link. Use `./e2e link`
   to print it first, or `./e2e link --cmd` to print the platform command:

   ```sh
   # iOS simulator
   xcrun simctl openurl <udid> "analogcoffeecard-dev://cafeanalog.dk/register/<token>"

   # Android emulator/device
   adb -s <serial> shell am start -a android.intent.action.VIEW \
     -d "analogcoffeecard-dev://cafeanalog.dk/register/<token>"
   ```

4. Enter a name, pick a programme, tap **Create account**. You land on
   **Tickets**.

To test an existing seeded account, use `john@doe.com`. Open its **“Login to
Analog”** email and launch the `/login/auth/<token>` link; the app signs in with
the seeded tickets. `./e2e open-link` handles both kinds of email. If the inbox
contains several emails, the newest wins; `./e2e reset` clears it.

## Commands

| Command | What it does |
| --- | --- |
| `e2e setup [--clone]` | Check/possibly clone the two sibling repos |
| `e2e check` | Validate tools, repos, code and device tooling |
| `e2e up` | Start the whole stack, seed, boot a device |
| `e2e dev` | `up`, then `flutter run` in the foreground |
| `e2e app` | `flutter run` against the local backend |
| `e2e device` / `e2e sim` | Boot/select the simulator or emulator |
| `e2e status` | Show backend/MailHog/Docker/device state |
| `e2e link [--open\|--cmd]` | Print/open the newest deep link |
| `e2e open-link` | Alias for `e2e link --open` |
| `e2e email` | Open MailHog in the browser |
| `e2e logs` | Tail `.dev/backend.log` |
| `e2e list-users` | List users and unused ticket counts |
| `e2e smoke` | Backend + email + registration smoke test |
| `e2e seed` | Re-apply the dummy seed |
| `e2e reset` | Remove `@example.com` accounts/tokens, re-seed, clear MailHog |
| `e2e backend start\|stop\|restart` | Control just the backend |
| `e2e deps` | Start MSSQL + MailHog only |
| `e2e down` | Stop the backend and Docker services (keeps data) |
| `e2e nuke` | Delete containers, DB volume and `.dev/` state |
| `e2e config` | Print resolved configuration |
| `e2e doctor` | Tool versions + checks |

`--platform ios|android|none`, `--device <serial-or-udid>`, `--no-device` and
`--backend-only` are available where they make sense. `e2e <command> --help`
documents each one.

## Platform details

### iOS simulator (macOS)

`PLATFORM=auto` picks iOS on macOS when `xcrun` exists. Selection order:

1. `SIM_UDID`
2. `SIM_NAME` (default `iPhone 16 Pro`)
3. the first available iPhone

`e2e device` boots it headlessly with `simctl bootstatus` and opens Simulator.app.
Deep links use `xcrun simctl openurl`.

Use `flutter run` (via `e2e app` or VS Code), not a `flutter build ios
--simulator` artifact installed with `simctl install`. The latter can lose the
simulator Keychain access and make `flutter_secure_storage` fail with `-34018
(“A required entitlement isn't present”)` when saving auth tokens.

### Android emulator (Windows/Linux, optional on macOS)

`PLATFORM=auto` picks Android when `adb` or the Android SDK is found. Selection
order:

1. `ANDROID_SERIAL`
2. a connected device/emulator
3. `ANDROID_AVD` (or the first AVD) launched with the emulator

The emulator reaches the host through `10.0.2.2`, so `e2e app` passes
`API_BASE_URL=http://10.0.2.2:<API_PORT>` automatically. A physical phone cannot
use `localhost`; set:

```sh
ANDROID_API_BASE_URL=http://192.168.1.10:8080 e2e app
```

with `API_BIND=0.0.0.0` (the default) and the firewall allowing the port.

Android 9+ blocks cleartext HTTP by default. The development debug manifest
(`mobile_app/android/app/src/debug/AndroidManifest.xml`) opts in with
`android:usesCleartextTraffic="true"`; release builds keep the secure default.
`e2e check` warns if that opt-in is missing.

### Physical devices (advanced)

- **Android**: set `ANDROID_SERIAL` or `--device <serial>`, plus
  `ANDROID_API_BASE_URL`. `e2e open-link` uses `adb`.
- **iOS**: the E2E tool only manages simulators. For a physical iPhone, run
  `flutter run --flavor development --dart-define=API_BASE_URL=http://<Mac-LAN-IP>:8080 -d <device-id>`
  and install the app normally. The backend already binds `0.0.0.0`.

## Seeded data

- Programmes: `SWU` (Software Engineering), `DUMMY` (Dummy Programme)
- `john@doe.com` — verified customer, 4 unused tickets
- `dummy.seed.barista@analog.local` — barista, 2 unused tickets
- Products: `Dummy Seed - 10 Coffee Clips`, `Dummy Seed - 5 Tea Clips`

The seed is idempotent; `e2e reset` removes accounts matching `%@example.com`
first. Use `e2e list-users` to inspect the whole local database.

## Configuration

Defaults live in [`config.env`](config.env). Override per command:

```sh
SIM_NAME="iPhone 17" ./e2e up
API_PORT=5080 ./e2e up
PLATFORM=android ./e2e up
```

Or create `config.local.env` (git-ignored) with the same `KEY=VALUE` syntax for
persistent overrides. Precedence: **environment → `config.local.env` →
`config.env`**.

If you change `API_PORT`, `API_BASE_URL` is derived automatically (leave it
empty). For a physical phone, set `ANDROID_API_BASE_URL` explicitly.

## How it works

- **Docker**: this repo owns `docker-compose.yml` (MSSQL 2022 + MailHog) so it
  does not depend on another repository’s compose project and does not collide
  with `analog-core`’s own `coffeecard` compose project.
- **Backend**: `dotnet build`, then `dotnet exec <built dll>` as a detached
  process with:
  - `ASPNETCORE_ENVIRONMENT=Development`
  - `ASPNETCORE_URLS=http://${API_BIND}:${API_PORT}`
  - `EnvironmentSettings__AnalogAppUrl=${DEEP_LINK_BASE}`
  - `SmtpSettings__Host=127.0.0.1`, `SmtpSettings__Port=${SMTP_PORT}`
  - `DatabaseSettings__ConnectionString=Server=localhost,${DB_PORT};...`
- **Seeding**: `db/seed.sql` (vendored, idempotent) after the backend has applied
  migrations.
- **App**: `flutter run --flavor development --dart-define=API_BASE_URL=...`.
  Android emulators get `http://10.0.2.2:<port>`; everything else gets
  `API_BASE_URL`.
- **Runtime state**: `.dev/backend.pid`, `.dev/backend.log`,
  `.dev/backend-build.log`, `.dev/device.json`, `.dev/emulator.log`.

## CI / backend-only use

`e2e smoke` needs Docker, .NET and the backend repo; it does not need Xcode or
Flutter. Use:

```sh
./e2e check --backend-only
./e2e up --backend-only
./e2e smoke
```

The smoke test performs:

1. unknown email → `POST /api/v2/account/login` → `204`
2. wait for the welcome email in MailHog
3. extract the `/register/<token>` link
4. `POST /api/v2/account/register` → `200` with JWT + refresh token
5. remove the smoke user/token and its email

## Migrating from the old harness

The old Makefile/bash harness reused `analog-core/coffeecard/docker-compose.yml`
and therefore created containers in the `coffeecard` Compose project (`mssql`,
`coffeecard-mailhog-1`). It also left the backend running as a host process. This
version owns its own Compose project, so the old pieces can conflict on the API,
database and MailHog ports. Stop them once:

```sh
./e2e down    # stops the backend on API_PORT (and this tool's own services)

docker compose -f analog-core/coffeecard/docker-compose.yml \
  --project-directory analog-core/coffeecard down
```

or, if that compose file is no longer available:

```sh
docker rm -f mssql coffeecard-mailhog-1
```

Then start the new stack with `./e2e up`. The new `e2e nuke` only removes this
tool's own project and volumes.

## Troubleshooting

Run `e2e doctor` first.

- **Docker not running** — start Docker Desktop/daemon before any command.
- **Port conflict** — stop the other process or override `API_PORT`, `DB_PORT`,
  `MAILHOG_HTTP_PORT`, `MAILHOG_SMTP_PORT`. Set them consistently; `API_BASE_URL`
  is derived from `API_PORT` when empty.
- **No simulator** — Xcode → Settings → Platforms, install an iOS runtime; or
  create an AVD in Android Studio.
- **`adb: no devices/emulators found`** — start an emulator, enable USB debugging
  for a physical device, or set `ANDROID_AVD`.
- **Android cleartext error** — see the debug-manifest note above; `e2e check`
  warns about it.
- **Android app can’t reach the API** — confirm `10.0.2.2` for emulators,
  `ANDROID_API_BASE_URL` + firewall for physical devices.
- **iOS keychain / `-34018`** — use `e2e app`/VS Code instead of installing a
  `simctl` build artifact.
- **Deep link opens the app but no registration screen** — request a new link
  (single-use, 30 minutes) and confirm the email contains
  `analogcoffeecard-dev://cafeanalog.dk/register/...`. A backend started outside
  `e2e` may have the wrong `AnalogAppUrl`.
- **No emails** — `e2e status`, then MailHog; backend SMTP errors are in
  `e2e logs`.
- **Backend won’t start** — `.dev/backend.log` and `.dev/backend-build.log`.
- **Reset everything** — `e2e nuke && e2e up` (destroys the local DB volume).

## Why `.gitignore` is small

`.gitignore` only contains what the E2E tool itself creates:

```gitignore
/.dev/
/config.local.env
/analog-core/
/mobile_app/
```

Machine-specific leftovers (the legacy `coffeecard_app/`, harness logs,
`.cache/`, `artifacts/`, editor state) live in `.git/info/exclude`, which is
local-only and never committed.
