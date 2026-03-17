# Build openclaw from source to avoid npm packaging gaps.
FROM platformatic/node-caged:25 AS openclaw-build

ENV DEBIAN_FRONTEND=noninteractive
ENV BUN_INSTALL=/root/.bun
ENV PATH="${BUN_INSTALL}/bin:${PATH}"
ENV OPENCLAW_PREFER_PNPM=1

# Build dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    unzip \
    python3 \
    make \
    g++ \
  && rm -rf /var/lib/apt/lists/*

# Install Bun for the openclaw build
RUN curl -fsSL https://bun.sh/install | bash

WORKDIR /openclaw

# Pin to a known-good ref. Override at build time if needed.
ARG OPENCLAW_GIT_REF=v2026.3.8
RUN git clone --depth 1 --branch "${OPENCLAW_GIT_REF}" https://github.com/openclaw/openclaw.git .

# Relax extension package version requirements that may reference unpublished versions.
RUN set -eux; \
  find ./extensions -name 'package.json' -type f | while read -r f; do \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*">=[^"]+"/"openclaw": "*"/g' "$f"; \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*"workspace:[^"]+"/"openclaw": "*"/g' "$f"; \
  done

# Avoid corepack; install pnpm directly
RUN npm install -g pnpm@10.23.0

RUN pnpm install --no-frozen-lockfile
RUN pnpm build
RUN pnpm ui:install && pnpm ui:build


# Runtime image
FROM platformatic/node-caged:25

ENV NODE_ENV=production
ENV NPM_CONFIG_PREFIX=/data/npm
ENV NPM_CONFIG_CACHE=/data/npm-cache
ENV PNPM_HOME=/data/pnpm
ENV PNPM_STORE_DIR=/data/pnpm-store
ENV PATH="/data/npm/bin:/data/pnpm:${PATH}"

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    tini \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install pnpm directly instead of using corepack
RUN npm install -g pnpm@10.23.0

# Wrapper deps
COPY package.json ./
RUN npm install --omit=dev \
  && npm cache clean --force

# Copy built openclaw
COPY --from=openclaw-build /openclaw /openclaw

# Provide an openclaw executable
RUN printf '%s\n' \
  '#!/usr/bin/env bash' \
  'exec node /openclaw/dist/entry.js "$@"' \
  > /usr/local/bin/openclaw \
  && chmod +x /usr/local/bin/openclaw

COPY src ./src

# Create writable runtime directories up front
RUN mkdir -p /data/npm /data/npm-cache /data/pnpm /data/pnpm-store

RUN useradd --create-home --shell /usr/sbin/nologin appuser \
  && chown -R appuser:appuser /app /openclaw /data
USER appuser

EXPOSE 8080
ENTRYPOINT ["tini", "--"]
CMD ["node", "src/server.js"]
