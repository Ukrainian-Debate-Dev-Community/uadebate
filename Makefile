# What `make release` releases (scripts/release reads these)
RELEASE_NAME      = uadebate
RELEASE_REPO      = Ukrainian-Debate-Dev-Community/uadebate
RELEASE_CI        = ci.yml
RELEASE_FILES     = mix.exs apps/dfu/mix.exs apps/uadebate/mix.exs
RELEASE_CHANGELOG = CHANGELOG.md
IMAGE             = ghcr.io/ukrainian-debate-dev-community/uadebate
RELEASE_ARTIFACT  = the image $(IMAGE):v{version} (release workflow)

RUN_DIR = .run
# Homebrew's postgresql@16 psql (survives upgrades), else psql on PATH
PSQL   ?= $(shell p="$$(brew --prefix postgresql@16 2>/dev/null)/bin/psql"; [ -x "$$p" ] && echo "$$p" || echo psql)
NIX     = nix develop --command
# cab's database lives in no app of this umbrella: name both repos
REPOS   = -r Cab.Repo -r Uadebate.Repo

.PHONY: setup dev build test test-all lint fmt clean release FORCE

# Targets named dev:<x> run against the local stack. GNU make 3.81 keeps
# the backslash of an escaped colon in .PHONY and prerequisite lists, so
# these depend on FORCE instead and call each other through $(MAKE).
FORCE:

# ---------------------------------------------------------------
# Standard targets
# ---------------------------------------------------------------

# The cab submodule (and its engine), the engine's packages, Elixir
# deps, databases
setup:
	git submodule update --init --recursive
	cd cab/engine && npm install
	$(NIX) sh -c 'mix deps.get && cd apps/uadebate && mix ecto.create $(REPOS) && mix ecto.migrate $(REPOS)'

# make dev = make dev:up
dev:
	@$(MAKE) --no-print-directory dev:up

build:
	$(NIX) mix compile --warnings-as-errors

# dfu's and uadebate's tests; cab's own run in opendebate-cab
test:
	$(NIX) sh -c 'MIX_ENV=test mix test'

# Everything that runs without the local stack (make dev:e2e needs it):
# the unit tests and the release script's own checks
test-all: test
	python3 scripts/release --self-test

# per app: from the umbrella root a clean build extracts every reference twice
lint:
	$(NIX) sh -c 'mix format --check-formatted && (cd apps/uadebate && MIX_ENV=test mix gettext.extract --check-up-to-date) && mix hex.audit'

fmt:
	$(NIX) mix format

clean:
	rm -rf _build $(RUN_DIR)

# ---------------------------------------------------------------
# Local dev stack: engine (node, :3100) + cab (phoenix, :4000) and
# uadebate.com (:4001), both endpoints in the one phoenix server
# ---------------------------------------------------------------

# The engine reads cab/engine/.env; without one it starts with these
# development settings and the JWT secret cab uses (ENGINE_JWT_SECRET in
# .env here). Prefix for a shell line that then runs in cab/engine.
ENGINE_SHELL = set -a; [ -f .env ] && . ./.env; set +a; cd cab/engine; \
	[ -f .env ] || export JWT_SECRET="$${ENGINE_JWT_SECRET:-}" PORT=3100 NODE_ENV=development \
		DB_HOST=localhost DB_PORT=5432 DB_USER=postgres DB_PASSWORD=postgres \
		DB_DATABASE=cab_dev DB_TEST=cab_test;

# Start both services in the background. Logs go to .run/*.log.
dev\:up: FORCE
	@mkdir -p $(RUN_DIR)
	@if lsof -ti :3100 >/dev/null 2>&1; then \
		echo "engine   already running on :3100"; \
	else \
		($(ENGINE_SHELL) nohup node src/app.js >> ../../$(RUN_DIR)/engine.log 2>&1 &) \
		&& echo "engine   starting on :3100  (log: $(RUN_DIR)/engine.log)"; \
	fi
	@if lsof -ti :4000 >/dev/null 2>&1; then \
		echo "cab      already running on :4000"; \
	else \
		(nohup $(NIX) mix phx.server >> $(RUN_DIR)/cab.log 2>&1 &) \
		&& echo "cab      starting on :4000, uadebate.com on :4001  (log: $(RUN_DIR)/cab.log, first boot may take a minute)"; \
	fi
	@printf "waiting for cab and uadebate.com"
	@for i in $$(seq 1 90); do \
		if curl -s -o /dev/null --max-time 2 http://localhost:4000/ 2>/dev/null \
			&& curl -s -o /dev/null --max-time 2 http://localhost:4001/ 2>/dev/null; then \
			echo " ready"; echo "open http://localhost:4000/ (cab) and http://localhost:4001/ (uadebate.com)"; exit 0; \
		fi; printf "."; sleep 2; \
	done; echo " not up after 3 min - check: make dev:logs"

# Stop the services (kills whatever listens on :3100 / :4000 / :4001).
dev\:down: FORCE
	@-lsof -ti :4000 2>/dev/null | xargs kill 2>/dev/null; true
	@-lsof -ti :4001 2>/dev/null | xargs kill 2>/dev/null; true
	@-lsof -ti :3100 2>/dev/null | xargs kill 2>/dev/null; true
	@echo "stopped (ports 3100, 4000 and 4001 freed)"

dev\:restart: FORCE
	@$(MAKE) --no-print-directory dev:down
	@$(MAKE) --no-print-directory dev:up

# Wipe the engine's, cab's and uadebate.com's databases, reseed the
# engine, migrate, restart the stack and load fresh demo data around
# your own account:
#   make dev:fresh DEV_USER=<your cab username>
dev\:fresh: FORCE
	@test -n "$(DEV_USER)" || { echo "usage: make dev:fresh DEV_USER=<your cab username>"; exit 1; }
	@$(MAKE) --no-print-directory dev:down
	@echo "== wiping engine db (cab_dev) =="
	$(PSQL) -d postgres -c 'DROP DATABASE IF EXISTS cab_dev;' -c 'CREATE DATABASE cab_dev OWNER postgres;'
	$(ENGINE_SHELL) npx sequelize-cli db:migrate && npx sequelize-cli db:seed:all
	@echo "== wiping cab's and uadebate.com's dbs =="
	$(NIX) sh -c 'cd apps/uadebate && mix ecto.drop --force $(REPOS) && mix ecto.create $(REPOS) && mix ecto.migrate $(REPOS)'
	@$(MAKE) --no-print-directory dev:up
	@echo "== loading demo data =="
	set -a; [ -f .env ] && . ./.env; set +a; MIX_ROOT=$(CURDIR) cab/apps/cab/priv/prime_demo.sh $(DEV_USER)
	@echo "fresh demo ready: http://localhost:4000/ and http://localhost:4001/"

# Record lifecycle facts on cab session rows that predate them.
# Safe to re-run; needs the engine up.
dev\:backfill: FORCE
	$(NIX) mix cab.backfill_sessions

# cab's full session roundtrip (from the submodule, with this project's
# build) against the running local stack (make dev:up). Re-runnable;
# every run makes its own demo club.
dev\:e2e: FORCE
	set -a; [ -f .env ] && . ./.env; set +a; MIX_ROOT=$(CURDIR) cab/apps/cab/priv/walkthrough_rest.sh

# The uadebate.com pages and the cab pages its visitors reach, as an
# iPhone 15 against the running stack (make dev:up): fails when a page
# scrolls sideways. Not part of CI. Signs in as DEV_USER:
#   make dev:phone DEV_USER=<a cab username>
dev\:phone: FORCE
	@test -n "$(DEV_USER)" || { echo "usage: make dev:phone DEV_USER=<a cab username>"; exit 1; }
	DEV_USER=$(DEV_USER) PATH="$(dir $(PSQL)):$$PATH" uv run tools/phone/phone_check.py

dev\:logs: FORCE
	@mkdir -p $(RUN_DIR) && touch $(RUN_DIR)/engine.log $(RUN_DIR)/cab.log
	tail -n 40 -f $(RUN_DIR)/engine.log $(RUN_DIR)/cab.log

dev\:status: FORCE
	@if lsof -ti :3100 >/dev/null 2>&1; then echo "engine   up   :3100"; else echo "engine   down :3100"; fi
	@if lsof -ti :4000 >/dev/null 2>&1; then echo "cab      up   :4000"; else echo "cab      down :4000"; fi
	@if lsof -ti :4001 >/dev/null 2>&1; then echo "uadebate up   :4001"; else echo "uadebate down :4001"; fi

# Move the cab pin to opendebate-cab's latest release tag, with the
# engine pin cab carries (what the nightly workflow does). REF=<ref>
# pins another ref instead, e.g. make dev:bump-cab REF=origin/nightly
dev\:bump-cab: FORCE
	git -C cab fetch --quiet --tags origin
	@ref="$(REF)"; [ -n "$$ref" ] || ref=$$(git -C cab tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$$' | sort -V | tail -1); \
	test -n "$$ref" || { echo "opendebate-cab has no release tag yet: make dev:bump-cab REF=origin/nightly"; exit 1; }; \
	git -C cab checkout --quiet "$$ref" && echo "cab at $$ref"
	git -C cab submodule update --init --recursive
	git -C cab log --oneline -1

# Build the release image locally (needs docker running)
dev\:image: FORCE
	docker build -t $(IMAGE):local .

# ---------------------------------------------------------------
# Releases: main moves only here, by fast-forward to a release commit
# on nightly. scripts/release (the same in every repo) does it all:
#   make release BUMP=patch|minor|major   (or VERSION=X.Y.Z)
#   make release BUMP=patch DRY_RUN=1     preview, changes nothing
#   make release RESUME=1                 finish an interrupted release
# ---------------------------------------------------------------

release:
	@python3 scripts/release --name '$(RELEASE_NAME)' --repo '$(RELEASE_REPO)' \
		--ci '$(RELEASE_CI)' --files '$(RELEASE_FILES)' --changelog '$(RELEASE_CHANGELOG)' \
		--artifact '$(RELEASE_ARTIFACT)' $(if $(BUMP),--bump '$(BUMP)') \
		$(if $(VERSION),--version '$(VERSION)') $(if $(SINCE),--since '$(SINCE)') \
		$(if $(DRY_RUN),--dry-run) $(if $(RESUME),--resume)
