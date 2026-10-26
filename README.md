# uadebate

uadebate.com and the cab it runs at cab.uadebate.com, as one Elixir
umbrella:

- `apps/uadebate`: the public site, uadebate.com (its own database for
  news, events and editors; clubs and accounts read from cab)
- `cab/`: [opendebate-cab](https://github.com/Ukrainian-Debate-Dev-Community/opendebate-cab),
  pinned as a git submodule: `cab/apps/core` (the engine client and the
  shared mailer), `cab/apps/cab` (debate clubs and their sessions) and
  `cab/engine`, the debate engine, pinned in turn by cab

Dependencies point down only: uadebate -> cab -> core.
uadebate depends on core and cab as path deps into the submodule; cab
knows nothing above it. uadebate tells cab who runs it
(`UadebateWeb.CabOperator`, `config :cab, :operator`): the texts, links
and addresses in cab's footer, on its sign-in and on its account page,
translated with uadebate's own words in cab's page language.

Configuration is cab's own plus uadebate's: `config/config.exs` imports
`cab/config/config.exs` (and with it cab's dev, test and prod files) and
adds only uadebate's settings and overrides. `config/runtime.exs` cannot
import, so it holds cab's runtime settings (a copy of
`cab/config/runtime.exs`, to keep in step when the cab pin moves) and
uadebate's.

Policy and Terms are deployment documents: in development they are read
from the server checkout next to this repo (`uadebate-server/legal`, or
`opendebate-server/legal` until the rename), in production from
`LEGAL_DIR`.

## Getting started

```sh
git submodule update --init --recursive
make setup        # cab and its engine, the engine's packages, Elixir deps, databases
make dev:up       # engine on :3100, cab on :4000, uadebate.com on :4001 (make dev does the same)
make test         # uadebate's tests (cab's run in opendebate-cab)
make test-all     # everything that runs without the stack
```

The standard targets (`setup build test test-all lint fmt clean`) are
local and never need the running stack. Targets named `dev:<x>` work on
the local stack:

| Command | Does |
|---|---|
| `make dev:up` / `make dev:down` / `make dev:restart` | start, stop, restart the engine, cab and uadebate.com |
| `make dev:status` / `make dev:logs` | what is running / follow the logs in `.run/` |
| `make dev:fresh DEV_USER=<your cab username>` | wipe the databases, load demo data |
| `make dev:e2e` | cab's session walkthrough against the running stack |
| `make dev:phone DEV_USER=<a cab username>` | uadebate's pages as an iPhone 15 |
| `make dev:backfill` | record lifecycle facts on older cab session rows |
| `make dev:bump-cab` | move the cab pin to opendebate-cab's latest release (`REF=<ref>` for another) |
| `make dev:image` | build the release image locally (Docker needed) |

The dev stack reads `.env` at the repo root (OAuth keys, engine
secret). The engine reads `cab/engine/.env`; without one `make dev:up`
starts it with development settings and the root `.env`'s
`ENGINE_JWT_SECRET`.

## uadebate.com

Public pages never read a session: they are the same for everyone.
Editors open `/manage` (the link is given, not shown anywhere) after
signing in on cab; it is a 404 for anyone without the content-manager
role. cab admins grant the role on `/manage/people`; for the first
setup, `mix uadebate.grant <username-or-email>`.

uadebate.com signs its own cookie with the same `SECRET_KEY_BASE` as
cab and links to cab at `CAB_URL`; with `SESSION_COOKIE_DOMAIN` (for
example `.uadebate.com`) on cab the sign-in is shared.

## Branches and releases

- `nightly` is the default branch and the only target for pull requests
  (squash-merged); CI (`test`, `lint`, `guard`, `docker`) must pass.
  Every night a workflow moves the cab pin to opendebate-cab's latest
  release tag and opens a pull request into `nightly` when it changed.
- `main` moves only on a release, by fast-forward to the release commit.
- Versions are the git tags `vX.Y.Z`. A release, from a clean `nightly`
  equal to `origin/nightly` whose CI is green:

  ```sh
  make release BUMP=patch|minor|major   # or VERSION=X.Y.Z
  make release BUMP=patch DRY_RUN=1     # preview the version and notes
  ```

  It shows the next version and the release notes (from the squash-merged
  pull request titles since the last tag) and asks you to type
  `uadebate:vX.Y.Z`. Then it writes the version into the `mix.exs` files,
  prepends the notes to `CHANGELOG.md`, commits
  `chore(release): uadebate vX.Y.Z` on `nightly` and pushes it, waits for
  CI on that commit, fast-forwards `main` to it, pushes the annotated tag
  and publishes the GitHub release. If a step fails after the commit,
  `make release RESUME=1` finishes it. The tag publishes the image
  `ghcr.io/ukrainian-debate-dev-community/uadebate:vX.Y.Z` (and
  `:sha-<commit>`); the server pins and deploys it.
- `make dev:image` builds the image locally (Docker needed).

The image runs the `full` release (cab on 4000, uadebate.com on 4001) and
answers `GET /healthz` on both ports. Before starting a new version run the
migrations:

```sh
bin/full eval "Cab.Release.migrate()"
bin/full eval "Uadebate.Release.migrate()"
```

## Production settings

cab's and uadebate.com's together:

| Variable | Needed | What |
|---|---|---|
| `DATABASE_URL` | yes | cab's database, `ecto://user:pass@host/db` |
| `UADEBATE_DATABASE_URL` | yes | uadebate.com's database |
| `SECRET_KEY_BASE` | yes | signs cookies; both sites use the same one |
| `PHX_HOST` | yes | cab's host, e.g. `cab.uadebate.com` |
| `UADEBATE_HOST` | yes | the public site's host, e.g. `uadebate.com` |
| `ENGINE_URL` | yes | the engine, e.g. `http://engine:3000` |
| `ENGINE_JWT_SECRET` | yes | shared with the engine's `JWT_SECRET`; the dev default is refused |
| `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET` | yes | sign-in with GitHub |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | yes | sign-in with Google |
| `UADEBATE_UPLOADS_DIR` | yes | folder for news cover images, served at `/uploads`; in the image `/app/uploads`, a persistent volume kept in the backups |
| `CAB_UPLOADS_DIR` | yes | folder for cab's club logos, served by cab at `/uploads`; in the image `/app/cab-uploads`, a persistent volume kept in the backups |
| `LEGAL_DIR` | yes | folder with `en/policy.md`, `en/terms.md` (and other languages); 404 without |
| `SESSION_COOKIE_DOMAIN` | for sharing | e.g. `.uadebate.com`, so uadebate.com/manage sees the cab sign-in |
| `CAB_URL` | no | cab's address as uadebate.com links it; defaults to `https://$PHX_HOST` |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` | for mail | without `SMTP_HOST` mail is kept in memory and not sent |
| `MAIL_FROM` | for mail | `Name <address>`, e.g. `cab <noreply@uadebate.com>` |
| `RATE_LIMIT_ENABLED` | no | cab's JSON API rate limit, `true` by default |
| `RATE_LIMIT_SIGNED_IN`, `RATE_LIMIT_ANONYMOUS` | no | requests per minute, 60 and 20 by default |
| `PHX_SERVER` | set by the image | starts the web servers |
| `PORT`, `UADEBATE_PORT` | no | 4000 and 4001 by default |
| `POOL_SIZE`, `UADEBATE_POOL_SIZE` | no | database pools, 10 and 5 by default |
| `ECTO_IPV6` | no | `true` to reach the databases over IPv6 |
| `DNS_CLUSTER_QUERY` | no | only for clustering several nodes |

## Copyright

Copyright (c) 2026 Opendebate Team. All rights reserved.

cab (`cab/`) is opendebate-cab, under its own MIT licence.
