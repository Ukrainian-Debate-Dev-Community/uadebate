# The uadebate image: the `full` release (cab and core from the cab
# submodule, dfu, uadebate) in one container. cab listens on 4000,
# uadebate.com on 4001. Policy and Terms are not baked
# in: the server mounts its legal/ folder and points LEGAL_DIR at it.

ARG ELIXIR_IMAGE=hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20261005-slim
ARG RUNTIME_IMAGE=debian:bookworm-20261005-slim

# ---- build -------------------------------------------------------------
FROM ${ELIXIR_IMAGE} AS build

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential git ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

# dependencies first, so code changes reuse this layer
COPY mix.exs mix.lock ./
COPY cab/apps/core/mix.exs cab/apps/core/mix.exs
COPY cab/apps/cab/mix.exs cab/apps/cab/mix.exs
COPY apps/dfu/mix.exs apps/dfu/mix.exs
COPY apps/uadebate/mix.exs apps/uadebate/mix.exs
COPY cab/config/config.exs cab/config/prod.exs cab/config/
COPY config/config.exs config/prod.exs config/
RUN mix deps.get --only prod && mix deps.compile

COPY cab/apps cab/apps
COPY apps apps
COPY config/runtime.exs config/
RUN mix compile

# Tailwind's binary, fetched with curl: the tailwind package's own
# download (Erlang httpc) refuses GitHub's release redirects
# (header_too_long). It lands where the package looks for it, so
# tailwind.install finds it in place; the version is cab's config.exs's.
ARG TARGETARCH
RUN TW=$(sed -n '/^config :tailwind,/,/^$/s/.*version: "\([0-9.]*\)".*/\1/p' cab/config/config.exs) \
 && case "${TARGETARCH:-amd64}" in arm64) T=linux-arm64 ;; *) T=linux-x64 ;; esac \
 && test -n "$TW" \
 && mkdir -p _build \
 && curl -fsSL --retry 3 -o "_build/tailwind-$T-$TW" \
      "https://github.com/tailwindlabs/tailwindcss/releases/download/v$TW/tailwindcss-$T" \
 && chmod +x "_build/tailwind-$T-$TW"

# cab's assets need the compiled app (colocated hooks), then digesting.
# Built from this umbrella: cab's own assets.deploy alias would use the
# submodule's build and deps folders. phx.digest runs in one app, as from
# the umbrella root it would run once per app.
RUN mix tailwind.install --if-missing && mix esbuild.install --if-missing \
 && mix tailwind cab --minify && mix esbuild cab --minify \
 && cd apps/uadebate \
 && mix phx.digest ../../cab/apps/cab/priv/static -o ../../cab/apps/cab/priv/static

RUN mix release full

# ---- run ---------------------------------------------------------------
FROM ${RUNTIME_IMAGE}

RUN apt-get update \
 && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --home-dir /app opendebate

WORKDIR /app
ENV LANG=C.UTF-8 PHX_SERVER=true MIX_ENV=prod

COPY --from=build --chown=opendebate:opendebate /app/_build/prod/rel/full ./
USER opendebate
# uadebate.com's news images (UADEBATE_UPLOADS_DIR) and cab's club logos
# (CAB_UPLOADS_DIR); a volume mounted here starts out owned by the app user
RUN mkdir /app/uploads /app/cab-uploads

EXPOSE 4000 4001
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -fsS http://localhost:4000/healthz || exit 1

CMD ["/app/bin/full", "start"]
