# Convenience wrappers for the local E2E environment.
#
# GNU make is optional. Windows users can call `.\e2e.cmd <command>` directly;
# macOS/Linux users can call `./e2e <command>`. All real logic lives in e2e.py.

ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
ifeq ($(OS),Windows_NT)
PYTHON ?= python
else
PYTHON ?= $(shell command -v python3 2>/dev/null || command -v python 2>/dev/null || echo python3)
endif
E2E := $(PYTHON) "$(ROOT)/e2e.py"

.DEFAULT_GOAL := help

.PHONY: help check check-backend setup setup-clone up dev app backend deps seed sim device \
        status list-users smoke reset down nuke link open-link email logs restart-backend \
        config doctor

help: ## Show this help
	@$(E2E) --help

check: ## Validate prerequisites, repositories and registration code
	@$(E2E) check

check-backend: ## Validate backend/Docker prerequisites only
	@$(E2E) check --backend-only

setup: ## Check the sibling repositories and print clone commands if missing
	@$(E2E) setup

setup-clone: ## Clone analog-core and mobile_app if they are missing
	@$(E2E) setup --clone

up: ## Start MSSQL, MailHog, backend, seed data and a device
	@$(E2E) up

dev: ## `up`, then run the app in the foreground
	@$(E2E) dev

app: ## Run the app against the local backend (foreground)
	@$(E2E) app

backend: ## Start/restart the backend and apply the seed
	@$(E2E) backend start

deps: ## Start MSSQL and MailHog only
	@$(E2E) deps

seed: ## Apply the idempotent dummy seed
	@$(E2E) seed

sim: ## Boot/select the configured simulator or emulator
	@$(E2E) device

device: ## Boot/select the configured simulator or emulator
	@$(E2E) device

status: ## Show backend/MailHog/device state
	@$(E2E) status

list-users: ## List registered users (name, email, owned tickets)
	@$(E2E) list-users

smoke: ## Backend + email + registration smoke test (no UI)
	@$(E2E) smoke

reset: ## Remove test accounts, re-seed and clear MailHog
	@$(E2E) reset

down: ## Stop the backend and Docker services (keeps data)
	@$(E2E) down

nuke: ## Destroy containers, database volume and runtime state
	@$(E2E) nuke

link: ## Print the newest registration or login deep link
	@$(E2E) link

open-link: ## Open the newest registration or login link on the device
	@$(E2E) link --open

email: ## Open the MailHog inbox in the browser
	@$(E2E) email

logs: ## Tail the backend log
	@$(E2E) logs

restart-backend: ## Restart just the backend
	@$(E2E) backend restart

config: ## Print the resolved configuration
	@$(E2E) config

doctor: ## Print tool versions and run checks
	@$(E2E) doctor
