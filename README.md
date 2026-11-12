# analog-dev

Makefile helper to quickly spin up a local development stack for the app.

## Requirements

| Tool             | Notes                                                                                                |
| ---------------- | ---------------------------------------------------------------------------------------------------- |
| GNU make         | Any recent version.                                                                                  |
| Docker or Podman | Docker Compose v2, or `podman-compose` 1.6+ (needs `up --wait`). The daemon/machine must be running. |
| .NET SDK 10      | Check with `dotnet --version`.                                                                       |
| Flutter          | Version: Check mobile_app repository.                                                                |
| iOS simulator    | for macOS only                                                                                       |
| Android emulator | Linux, macOS or Windows: Android SDK, `adb`, `emulator`, one AVD.                                    |
| POSIX tools      | `sh`, `curl`, `sed`, `grep`, `awk`, `tail`. On Windows use Git Bash.                                 |

`analog-core/` and `mobile_app/` must be siblings of this Makefile:

```sh
git clone https://github.com/AnalogIO/analog-core.git analog-core
git clone https://github.com/AnalogIO/mobile_app.git mobile_app
```

## Quick start

```sh
make backend  # MSSQL + MailHog + API + demo seed
make app      # boot a device and run the app (foreground)
```

In another terminal, once the app has requested a registration or login email:

```sh
make open-link    # open the newest magic link on the device
make list-users   # list all registered users' names, emails, and unused tickets
```

`make backend` always rebuilds and restarts the API, so running it again picks up backend changes.

## Commands

| Command           | What it does                                                          |
| ----------------- | --------------------------------------------------------------------- |
| `make backend`    | Start MSSQL + MailHog, build/restart the API, apply the seed          |
| `make app`        | `flutter pub get`, boot the simulator/emulator if needed, run the app |
| `make open-link`  | Open the newest registration/login link on the device                 |
| `make list-users` | List users and their unused ticket counts                             |
| `make seed`       | Re-apply the idempotent demo seed                                     |
| `make logs`       | Follow `.dev/backend.log`                                             |
| `make down`       | Stop the API and the MSSQL/MailHog containers                         |

The API is at <http://localhost:8080> (Swagger at `/swagger`), MailHog is at <http://127.0.0.1:8025>.

## Test the magic-link flow

1. In the app, enter an unused email (for example `new.person@example.com`) and tap **Continue**.
2. Run `make open-link` (or open the email in MailHog).
3. Enter a name, pick a programme, and tap **Create account**.

For an existing account, use `a@analog.local` — the busy seed account with
tickets, receipts and leaderboard history. Request a login link from the app,
then run `make open-link`. Seeded accounts are `a@analog.local` …
`z@analog.local`; every one uses password `1234` for the old v1 password login.

## Configuration

Every setting is a Make variable, so it can be overridden per command:

```sh
make backend API_PORT=5080
make app PLATFORM=android
make backend COMPOSE="podman-compose"
```

| Variable                                  | Default                                 | Purpose                                                        |
| ----------------------------------------- | --------------------------------------- | -------------------------------------------------------------- |
| `API_PORT` / `API_BIND`                   | `8080` / `127.0.0.1`                    | API listener.                                                  |
| `DB_PORT` / `DB_PASSWORD`                 | `1433` / `Your_password123`             | MSSQL host port and SA password.                               |
| `MAILHOG_HTTP_PORT` / `MAILHOG_SMTP_PORT` | `8025` / `1025`                         | MailHog ports.                                                 |
| `DEEP_LINK`                               | `analogcoffeecard-dev://cafeanalog.dk/` | Prefix of the registration/login links.                        |
| `PLATFORM`                                | `auto`                                  | `ios`, `android`, or `auto` (iOS on macOS, Android elsewhere). |
| `APP_FLAVOR`                              | `development`                           | Flutter flavor.                                                |
| `CORE_DIR` / `APP_DIR`                    | sibling directories                     | Source checkout locations.                                     |
| `COMPOSE`                                 | auto                                    | Compose command. Podman is preferred when installed.           |

To change the database password after the volume exists, remove the volume:

```sh
make down
docker compose -f docker-compose.yml down -v   # or: podman compose ...
```

## Podman

`make` uses `podman` automatically when it is installed: `podman compose` when
available, otherwise the standalone `podman-compose`. It falls back to
`docker compose` when Podman is absent. Override it if your setup is different:

```sh
make backend COMPOSE="podman-compose"
```

`deps` uses `compose up --wait`, so `podman-compose` must be 1.6 or newer (or
`podman compose` must be backed by Docker Compose v2).

Rootless Podman needs subordinate UID/GID ranges (`/etc/subuid`, `/etc/subgid`)
for the MSSQL container. The published ports are all above 1024, so no extra
privileges are needed. To wipe the database volume:

```sh
make down
podman compose -f docker-compose.yml down -v
```

## Windows

Use Git Bash. Install GNU make (`choco install make` or `scoop install make`) and make sure `sh`, `curl`, `sed`, `grep`, `awk` and `tail` resolve — Git Bash provides them. iOS simulators require macOS; on Windows, use the Android emulator. The Makefile sets `SHELL := sh`, so recipes always run in Git Bash's shell rather than `cmd.exe`.

## How it works

- **Containers:** `docker-compose.yml` publishes MSSQL on `1433` and MailHog on `1025` (SMTP) and `8025` (UI), all bound to localhost. Both define a `healthcheck`; `make deps` runs `compose up -d --wait`, so the API starts only after MSSQL and MailHog report healthy.
- **API:** `make backend` runs `dotnet build`, then starts the built DLL detached with `ASPNETCORE_ENVIRONMENT=Development`, a localhost connection string, and SMTP pointed at MailHog. It becomes ready when `/api/v1/programmes` answers.
- **Seed:** `db/seed.sql` runs after the API has applied migrations. It is idempotent and creates 26 users, products, ~1,600 tickets, receipts and vouchers.
- **App:** the app is started with `--dart-define=API_BASE_URL=http://localhost:<API_PORT>`. On Android, `adb reverse` maps the device's localhost to the host, so the same URL works in the emulator and on a USB device.
- **State:** `.dev/` holds `backend.pid`, `backend.log`, `backend-build.log`, `seed.log` and `emulator.log`.

## Troubleshooting

- **Backend does not start** — `make logs`; the build log is `.dev/backend-build.log`.
- **Port 8080 is in use** — `make backend API_PORT=5080` and run `make app API_PORT=5080`.
- **MSSQL does not become ready** — `docker compose -f docker-compose.yml logs mssql` (or `podman compose ...`). The first start can take a minute.
- **No device** — `make app PLATFORM=android`; start an emulator in Android Studio or create an AVD. `make app` launches the first AVD automatically when none is running.
- **No magic link** — request one from the app first, then check <http://127.0.0.1:8025>. Links are single-use and expire after 30 minutes.
- **Android app cannot reach the API** — check `adb reverse --list`; `make app` adds the reverse mapping. Re-run `make app` if the device was restarted.
- **Stale backend code** — `make backend` restarts the API, so just run it again.
- **Start over** — `make down`, remove the database volume, then `make backend`.

## Layout

```text
analog-dev/
├── Makefile
├── docker-compose.yml
├── db/seed.sql
├── analog-core/     # separate Git repo (you clone this)
├── mobile_app/      # separate Git repo (you clone this)
└── .dev/            # runtime state (ignored)
```
