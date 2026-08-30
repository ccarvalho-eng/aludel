ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.4.1
ARG DEBIAN_VERSION=bookworm-20260316-slim
ARG ESBUILD_VERSION=0.25.4
ARG TAILWIND_VERSION=4.1.7
ARG HEROICONS_TAG=v2.2.0

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y --no-install-recommends build-essential curl git \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set build ENV
ENV MIX_ENV="prod"

# Install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# Prepare build directory
WORKDIR /app

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

RUN mkdir config

# Copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy priv and lib
COPY priv priv
COPY lib lib

# Copy assets and install JS dependencies
COPY assets assets
RUN npm ci --prefix assets

# Install standalone esbuild and tailwind CLI binaries.
# The esbuild and tailwind hex packages are dev-only deps, so we invoke
# the CLIs directly rather than using Mix tasks.
ARG ESBUILD_VERSION
ARG TAILWIND_VERSION
ARG HEROICONS_TAG

# Fetch heroicons SVGs (dev-only dep needed at CSS build time by the
# Tailwind heroicons plugin which reads from deps/heroicons/optimized/)
RUN git clone --depth 1 --filter=blob:none --sparse \
  --branch ${HEROICONS_TAG} https://github.com/tailwindlabs/heroicons.git deps/heroicons && \
  cd deps/heroicons && git sparse-checkout set optimized

# Detect architecture for downloading correct binaries
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

# Build CSS with tailwind
RUN tailwindcss \
  --input=assets/css/app.css \
  --output=priv/static/app.css \
  --minify

# Build JS with esbuild
RUN esbuild assets/js/app.js --bundle --target=es2022 \
  --outdir=priv/static \
  --external:/fonts/* --external:/images/* \
  --minify

# Compile the library
RUN mix compile

# Copy runtime config last (doesn't require recompilation)
COPY config/runtime.exs config/
