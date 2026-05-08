# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM docker.io/library/elixir:1.15-otp-26-alpine AS builder

# build-base: C compiler for NIFs
# git: required by some Mix deps fetched from GitHub (heroicons)
# curl: used by esbuild/tailwind installers
RUN apk add --no-cache build-base git curl

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Fetch deps first so this layer is cached independently of source changes
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy all config (compile-time + runtime)
COPY config config/

# Copy source + assets
COPY lib lib/
COPY priv priv/
COPY assets assets/

RUN mix compile

# esbuild and tailwind are standalone binaries downloaded by Mix — no npm needed
RUN mix assets.deploy

RUN mix release

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS runner

# ncurses-libs: required by BEAM
# openssl/ca-certificates: TLS + cert validation
RUN apk add --no-cache ncurses-libs openssl ca-certificates

WORKDIR /app

RUN adduser -D -u 1000 eos

COPY --from=builder --chown=eos:eos /app/_build/prod/rel/eos ./

USER eos

EXPOSE 4000

ENV HOME=/app
ENV PHX_SERVER=true

CMD ["bin/eos", "start"]
