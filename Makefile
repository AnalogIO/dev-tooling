# Minimal local development toolchain for the Analog coffee-card stack.
#
#   make backend     Start MSSQL + MailHog, build/run the API, seed demo data
#   make app         Run the Flutter app on an iOS simulator or Android emulator
#   make open-link   Open the newest magic link from MailHog on the device
#   make list-users  List users and their unused tickets
#   make down        Stop the API and the containers
#
# Requirements: make, Docker or Podman with Compose, .NET 10, and Flutter.
# macOS uses the iOS simulator (Xcode); everything else uses Android (adb).
# Run `make help` for the full command list.
#
# Override any setting on the command line, for example:
#   make backend API_PORT=5080
#   make backend COMPOSE="podman-compose"
#   make app PLATFORM=android

SHELL := sh

ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

CORE_DIR     ?= $(ROOT)/analog-core
APP_DIR      ?= $(ROOT)/mobile_app
WEBAPI_DIR    = $(CORE_DIR)/coffeecard/CoffeeCard.WebApi
WEBAPI_CSPROJ = CoffeeCard.WebApi.csproj

API_PORT          ?= 8080
API_BIND          ?= 127.0.0.1
DB_PORT           ?= 1433
DB_BIND           ?= 127.0.0.1
DB_USER           ?= sa
DB_PASSWORD       ?= Your_password123
DB_NAME           ?= master
MAILHOG_HTTP_PORT ?= 8025
MAILHOG_SMTP_PORT ?= 1025
MAILHOG_BIND      ?= 127.0.0.1
MSSQL_IMAGE       ?= mcr.microsoft.com/mssql/server:2022-latest
MAILHOG_IMAGE     ?= mailhog/mailhog:latest
DEEP_LINK         ?= analogcoffeecard-dev://cafeanalog.dk/
APP_FLAVOR        ?= development
PLATFORM          ?= auto

# Prefer Podman when it is installed (the Linux setup); otherwise use Docker.
# podman compose ships with Podman 4.7+; older installations usually have the
# standalone podman-compose. Override with COMPOSE="..." if needed.
COMPOSE := $(shell \
	if command -v podman >/dev/null 2>&1; then \
		if podman compose version >/dev/null 2>&1; then echo podman compose; \
		elif command -v podman-compose >/dev/null 2>&1; then echo podman-compose; \
		else echo podman compose; fi; \
	else echo docker compose; fi)
COMPOSE_CMD = cd "$(ROOT)" && $(COMPOSE) -f docker-compose.yml

DEV_DIR   = $(ROOT)/.dev
LOG       = $(DEV_DIR)/backend.log
BUILD_LOG = $(DEV_DIR)/backend-build.log
SEED_LOG  = $(DEV_DIR)/seed.log

IOS_UDID_RE = [0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}

export DB_PORT DB_BIND DB_PASSWORD MSSQL_IMAGE
export MAILHOG_HTTP_PORT MAILHOG_SMTP_PORT MAILHOG_BIND MAILHOG_IMAGE

ifeq ($(PLATFORM),auto)
  ifeq ($(shell uname -s 2>/dev/null),Darwin)
    ifeq ($(shell command -v xcrun 2>/dev/null),)
      PLATFORM := android
    else
      PLATFORM := ios
    endif
  else
    PLATFORM := android
  endif
endif

.DEFAULT_GOAL := help
.PHONY: help backend deps seed _seed app open-link list-users logs down

help:
	@echo "Analog local development (platform: $(PLATFORM))"
	@echo ""
	@echo "  make backend     Start MSSQL + MailHog, build/run the API, seed data"
	@echo "  make app         Run the app on $(PLATFORM)"
	@echo "  make open-link   Open the newest magic link on the device"
	@echo "  make list-users  List users and unused ticket counts"
	@echo "  make seed        Re-apply the demo seed"
	@echo "  make logs        Follow the backend log"
	@echo "  make down        Stop the API and containers"
	@echo ""
	@echo "  API      http://localhost:$(API_PORT)"
	@echo "  MailHog  http://127.0.0.1:$(MAILHOG_HTTP_PORT)"

# Start the two containers and wait until they are actually usable.
deps:
	@echo "Starting MSSQL and MailHog with $(COMPOSE)..."
	@$(COMPOSE_CMD) up -d mssql mailhog
	@printf "Waiting for MSSQL"
	@i=0; while [ $$i -lt 120 ]; do \
		if $(COMPOSE_CMD) exec -T mssql sh -c 'SQLCMD=$$(command -v /opt/mssql-tools18/bin/sqlcmd || command -v /opt/mssql-tools/bin/sqlcmd); $$SQLCMD -C -S localhost -U sa -P "$$MSSQL_SA_PASSWORD" -Q "SELECT 1" >/dev/null 2>&1'; then \
			echo " ready"; exit 0; \
		fi; \
		printf "."; i=$$((i+1)); sleep 1; \
	done; \
	echo ""; echo "error: MSSQL did not become ready"; exit 1
	@printf "Waiting for MailHog"
	@i=0; while [ $$i -lt 60 ]; do \
		if curl -fsS "http://127.0.0.1:$(MAILHOG_HTTP_PORT)/api/v2/messages" >/dev/null 2>&1; then \
			echo " ready"; exit 0; \
		fi; \
		printf "."; i=$$((i+1)); sleep 1; \
	done; \
	echo ""; echo "error: MailHog did not become ready"; exit 1

# Dependencies + build + run + seed, in one command.
backend: deps
	@test -f "$(WEBAPI_DIR)/$(WEBAPI_CSPROJ)" || { \
		echo "error: backend repo not found at $(CORE_DIR)"; exit 1; \
	}
	@mkdir -p "$(DEV_DIR)"
	@echo "Building backend..."
	@cd "$(WEBAPI_DIR)" && dotnet build "$(WEBAPI_CSPROJ)" -v q --nologo > "$(BUILD_LOG)" 2>&1 || { \
		echo "error: backend build failed (log: $(BUILD_LOG))"; tail -n 40 "$(BUILD_LOG)"; exit 1; \
	}
	@echo "Backend built."
	@PID=$$(cat "$(DEV_DIR)/backend.pid" 2>/dev/null); \
	if [ -n "$$PID" ] && kill -0 "$$PID" 2>/dev/null; then \
		echo "Restarting backend (pid $$PID)..."; \
		kill "$$PID"; \
		i=0; while kill -0 "$$PID" 2>/dev/null && [ $$i -lt 50 ]; do sleep 0.2; i=$$((i+1)); done; \
	fi; \
	rm -f "$(DEV_DIR)/backend.pid"; \
	if curl -fsS "http://127.0.0.1:$(API_PORT)/api/v1/programmes" >/dev/null 2>&1; then \
		echo "error: port $(API_PORT) is already serving a backend that make did not start."; \
		echo "       Stop it first, then retry."; exit 1; \
	fi
	@DLL="$$(cd "$(WEBAPI_DIR)" && dotnet msbuild "$(WEBAPI_CSPROJ)" -getProperty:TargetPath -nologo 2>/dev/null | tail -n 1)"; \
	echo "Starting backend on http://localhost:$(API_PORT)..."; \
	( cd "$(WEBAPI_DIR)" && exec env \
		ASPNETCORE_ENVIRONMENT=Development \
		DOTNET_ENVIRONMENT=Development \
		ASPNETCORE_URLS="http://$(API_BIND):$(API_PORT)" \
		EnvironmentSettings__AnalogAppUrl="$(DEEP_LINK)" \
		SmtpSettings__Host=127.0.0.1 \
		SmtpSettings__Port="$(MAILHOG_SMTP_PORT)" \
		DatabaseSettings__ConnectionString="Server=localhost,$(DB_PORT);Initial Catalog=$(DB_NAME);User=$(DB_USER);Password=$(DB_PASSWORD);TrustServerCertificate=True;" \
		nohup dotnet exec "$$DLL" ) >> "$(LOG)" 2>&1 & \
	echo $$! > "$(DEV_DIR)/backend.pid"
	@i=0; while [ $$i -lt 90 ]; do \
		if curl -fsS "http://127.0.0.1:$(API_PORT)/api/v1/programmes" >/dev/null 2>&1; then \
			echo "Backend ready."; exit 0; \
		fi; \
		PID=$$(cat "$(DEV_DIR)/backend.pid" 2>/dev/null); \
		if [ -n "$$PID" ] && ! kill -0 "$$PID" 2>/dev/null; then \
			echo "error: backend exited during startup."; tail -n 40 "$(LOG)"; exit 1; \
		fi; \
		i=$$((i+1)); sleep 1; \
	done; \
	echo "error: backend did not become ready."; tail -n 40 "$(LOG)"; exit 1
	@$(MAKE) --no-print-directory _seed
	@echo ""
	@echo "Backend: http://localhost:$(API_PORT)  (Swagger: /swagger)"
	@echo "MailHog: http://127.0.0.1:$(MAILHOG_HTTP_PORT)"
	@echo "Next:    make app"

seed: deps
	@$(MAKE) --no-print-directory _seed

_seed:
	@curl -fsS "http://127.0.0.1:$(API_PORT)/api/v1/programmes" >/dev/null 2>&1 || { \
		echo "error: backend is not running; run 'make backend' first."; exit 1; \
	}
	@SQLCMD=$$($(COMPOSE_CMD) exec -T mssql sh -c 'command -v /opt/mssql-tools18/bin/sqlcmd || command -v /opt/mssql-tools/bin/sqlcmd' 2>/dev/null); \
	if [ -z "$$SQLCMD" ]; then echo "error: sqlcmd not found in the MSSQL container."; exit 1; fi; \
	echo "Seeding demo data..."; \
	if ! $(COMPOSE_CMD) exec -T mssql "$$SQLCMD" -C -S localhost -U "$(DB_USER)" -P "$(DB_PASSWORD)" -d "$(DB_NAME)" -b < "$(ROOT)/db/seed.sql" > "$(SEED_LOG)" 2>&1; then \
		echo "error: seed failed (log: $(SEED_LOG))"; tail -n 40 "$(SEED_LOG)"; exit 1; \
	fi; \
	echo "Seed applied (a@analog.local is the busy account)."

app:
	@test -d "$(APP_DIR)" || { echo "error: app repo not found at $(APP_DIR)"; exit 1; }
	@mkdir -p "$(DEV_DIR)"
	@curl -fsS "http://127.0.0.1:$(API_PORT)/api/v1/programmes" >/dev/null 2>&1 || \
		echo "warning: backend is not running; run 'make backend' first."
	@echo "Fetching Flutter dependencies..."
	@cd "$(APP_DIR)" && flutter pub get
	@if [ "$(PLATFORM)" = "ios" ]; then \
		UDID=$$(xcrun simctl list devices booted 2>/dev/null | grep -oE '$(IOS_UDID_RE)' | head -1); \
		if [ -z "$$UDID" ]; then \
			UDID=$$(xcrun simctl list devices available 2>/dev/null | grep iPhone | grep -oE '$(IOS_UDID_RE)' | head -1); \
			[ -n "$$UDID" ] || { echo "error: no iOS simulator found; install a runtime in Xcode."; exit 1; }; \
			echo "Booting simulator $$UDID..."; \
			xcrun simctl boot "$$UDID" 2>/dev/null || true; \
			open -a Simulator; \
			xcrun simctl bootstatus "$$UDID" -b; \
		fi; \
		echo "Running app on $$UDID against http://localhost:$(API_PORT)..."; \
		cd "$(APP_DIR)" && flutter run -d "$$UDID" --flavor "$(APP_FLAVOR)" --dart-define=API_BASE_URL="http://localhost:$(API_PORT)"; \
	else \
		command -v adb >/dev/null 2>&1 || { echo "error: adb is not on PATH."; exit 1; }; \
		SERIAL=$$(adb devices | awk '$$2 == "device" { print $$1; exit }'); \
		if [ -z "$$SERIAL" ]; then \
			command -v emulator >/dev/null 2>&1 || { echo "error: no Android device and 'emulator' is not on PATH."; exit 1; }; \
			AVD=$$(emulator -list-avds | head -1); \
			[ -n "$$AVD" ] || { echo "error: no Android AVD; create one in Android Studio."; exit 1; }; \
			echo "Starting emulator $$AVD..."; \
			( emulator -avd "$$AVD" -no-snapshot-save -no-boot-anim > "$(DEV_DIR)/emulator.log" 2>&1 & ); \
			adb wait-for-device; \
			i=0; while [ "$$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\015')" != "1" ] && [ $$i -lt 180 ]; do sleep 1; i=$$((i+1)); done; \
			SERIAL=$$(adb devices | awk '$$2 == "device" { print $$1; exit }'); \
			[ -n "$$SERIAL" ] || { echo "error: emulator did not start; see $(DEV_DIR)/emulator.log"; exit 1; }; \
		fi; \
		adb -s "$$SERIAL" reverse "tcp:$(API_PORT)" "tcp:$(API_PORT)" || \
			echo "warning: adb reverse failed; the app may not reach the API."; \
		echo "Running app on $$SERIAL against http://localhost:$(API_PORT)..."; \
		cd "$(APP_DIR)" && flutter run -d "$$SERIAL" --flavor "$(APP_FLAVOR)" --dart-define=API_BASE_URL="http://localhost:$(API_PORT)"; \
	fi

open-link:
	@curl -fsS "http://127.0.0.1:$(MAILHOG_HTTP_PORT)/api/v2/messages" >/dev/null 2>&1 || { \
		echo "error: MailHog is not reachable; run 'make backend' first."; exit 1; \
	}
	@LINK=$$(curl -fsS "http://127.0.0.1:$(MAILHOG_HTTP_PORT)/api/v2/messages?limit=1000" | \
		sed -e 's/=\\r\\n//g' -e 's/=\\n//g' | \
		grep -oE '$(DEEP_LINK)(register/|login/auth/)[^"\\<> ]+' | head -1); \
	if [ -z "$$LINK" ]; then \
		echo "error: no magic link in MailHog; request one from the app first."; \
		echo "       MailHog: http://127.0.0.1:$(MAILHOG_HTTP_PORT)"; \
		exit 1; \
	fi; \
	echo "$$LINK"; \
	if [ "$(PLATFORM)" = "ios" ]; then \
		UDID=$$(xcrun simctl list devices booted 2>/dev/null | grep -oE '$(IOS_UDID_RE)' | head -1); \
		[ -n "$$UDID" ] || { echo "error: no booted simulator; run 'make app' first."; exit 1; }; \
		xcrun simctl openurl "$$UDID" "$$LINK"; \
	else \
		command -v adb >/dev/null 2>&1 || { echo "error: adb is not on PATH."; exit 1; }; \
		SERIAL=$$(adb devices | awk '$$2 == "device" { print $$1; exit }'); \
		[ -n "$$SERIAL" ] || { echo "error: no Android device; run 'make app' first."; exit 1; }; \
		adb -s "$$SERIAL" shell am start -a android.intent.action.VIEW -d "$$LINK"; \
	fi

list-users:
	@SQLCMD=$$($(COMPOSE_CMD) exec -T mssql sh -c 'command -v /opt/mssql-tools18/bin/sqlcmd || command -v /opt/mssql-tools/bin/sqlcmd' 2>/dev/null); \
	[ -n "$$SQLCMD" ] || { echo "error: MSSQL is not running; run 'make backend' first."; exit 1; }; \
	DATA=$$($(COMPOSE_CMD) exec -T mssql "$$SQLCMD" -C -S localhost -U "$(DB_USER)" -P "$(DB_PASSWORD)" -d "$(DB_NAME)" -W -h -1 -s "|" -Q "SET NOCOUNT ON; SELECT u.Name, u.Email, COUNT(t.Id) FROM dbo.Users u LEFT JOIN dbo.Tickets t ON t.[Owner_Id] = u.Id AND t.Status = 0 GROUP BY u.Id, u.Name, u.Email ORDER BY u.Name") || { \
		echo "error: could not read users; run 'make backend' first."; exit 1; \
	}; \
	printf '%s\n' "$$DATA" | awk -F'|' 'NF { \
		name[++n] = $$1; email[n] = $$2; count[n] = $$3; \
		if (length($$1) > wn) wn = length($$1); \
		if (length($$2) > we) we = length($$2); \
	} END { \
		if (wn < 4) wn = 4; \
		if (we < 5) we = 5; \
		print ""; \
		printf "%-*s  %-*s  %s\n", wn, "Name", we, "Email", "Unused"; \
		printf "%-*s  %-*s  %s\n", wn, "----", we, "-----", "------"; \
		for (i = 1; i <= n; i++) \
			printf "%-*s  %-*s  %s\n", wn, name[i], we, email[i], count[i]; \
	}'

logs:
	@test -f "$(LOG)" || { echo "error: no backend log yet; run 'make backend' first."; exit 1; }
	@tail -n 200 -f "$(LOG)"

down:
	@PID=$$(cat "$(DEV_DIR)/backend.pid" 2>/dev/null); \
	if [ -n "$$PID" ] && kill -0 "$$PID" 2>/dev/null; then \
		kill "$$PID"; echo "Stopped backend ($$PID)."; \
	fi; \
	rm -f "$(DEV_DIR)/backend.pid"
	-@$(COMPOSE_CMD) stop mssql mailhog
