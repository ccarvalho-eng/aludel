ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.4.1
ARG DEBIAN_VERSION=bookworm-20260316-slim
ARG ESBUILD_VERSION=0.25.4
ARG TAILWIND_VERSION=4.1.7
ARG HEROICONS_TAG=v2.2.0

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# ---------------------------------------------------------------------------
# Stage 1: Build the aludel library and its assets
# (mirrors the project's root Dockerfile)
# ---------------------------------------------------------------------------
FROM ${BUILDER_IMAGE} AS library

RUN apt-get update -y && apt-get install -y --no-install-recommends build-essential curl git \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

ENV MIX_ENV="prod"

RUN mix local.hex --force && \
  mix local.rebar --force

WORKDIR /app

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib

COPY assets assets
RUN npm ci --prefix assets

ARG ESBUILD_VERSION
ARG TAILWIND_VERSION
ARG HEROICONS_TAG

RUN git clone --depth 1 --filter=blob:none --sparse \
  --branch ${HEROICONS_TAG} https://github.com/tailwindlabs/heroicons.git deps/heroicons && \
  cd deps/heroicons && git sparse-checkout set optimized

RUN ARCH=$(dpkg --print-architecture) && \
  if [ "$ARCH" = "arm64" ]; then \
    ESBUILD_ARCH="linux-arm64"; \
    TAILWIND_ARCH="linux-arm64"; \
  else \
    ESBUILD_ARCH="linux-x64"; \
    TAILWIND_ARCH="linux-x64"; \
  fi && \
  curl -fsSL "https://registry.npmjs.org/@esbuild/${ESBUILD_ARCH}/-/${ESBUILD_ARCH}-${ESBUILD_VERSION}.tgz" \
    | tar xz --strip-components=2 -C /usr/local/bin package/bin/esbuild && \
  chmod +x /usr/local/bin/esbuild && \
  curl -fsSL -o /usr/local/bin/tailwindcss \
    "https://github.com/tailwindlabs/tailwindcss/releases/download/v${TAILWIND_VERSION}/tailwindcss-${TAILWIND_ARCH}" && \
  chmod +x /usr/local/bin/tailwindcss

RUN tailwindcss \
  --input=assets/css/app.css \
  --output=priv/static/app.css \
  --minify

RUN esbuild assets/js/app.js --bundle --target=es2022 \
  --outdir=priv/static \
  --external:/fonts/* --external:/images/* \
  --minify

RUN mix compile

COPY config/runtime.exs config/

# ---------------------------------------------------------------------------
# Stage 2: Build the standalone app release on top of the compiled library
# ---------------------------------------------------------------------------
FROM library AS standalone-builder

WORKDIR /app/standalone

COPY standalone/mix.exs standalone/mix.lock* ./
COPY standalone/config config

RUN mix deps.get --only prod
RUN mix deps.compile

COPY standalone/lib lib

# Install aludel migrations into the standalone app's priv directory
# so they are included in the release
RUN mkdir -p priv/repo/migrations && mix aludel.install

RUN mix compile
COPY standalone/config/runtime.exs config/
RUN mix release

# ---------------------------------------------------------------------------
# Stage 3: Minimal runner image
# ---------------------------------------------------------------------------
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
  apt-get install -y --no-install-recommends ca-certificates libncurses5 libstdc++6 locales openssl imagemagick ghostscript \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

COPY --from=standalone-builder --chown=nobody:root /app/standalone/_build/prod/rel/aludel_dash ./

RUN chmod -R a-w,a+rX /app

USER nobody

ENV PHX_SERVER=true

CMD ["/app/bin/aludel_dash", "start"]
