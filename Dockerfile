# Build openclaw from source to avoid npm packaging gaps.
FROM platformatic/node-caged:25 AS openclaw-build

ENV DEBIAN_FRONTEND=noninteractive
ENV BUN_INSTALL=/root/.bun
ENV PATH="${BUN_INSTALL}/bin:${PATH}"
ENV OPENCLAW_PREFER_PNPM=1

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

RUN curl -fsSL https://bun.sh/install | bash

WORKDIR /openclaw

ARG OPENCLAW_GIT_REF=v2026.3.8
RUN git clone --depth 1 --branch "${OPENCLAW_GIT_REF}" https://github.com/openclaw/openclaw.git .

RUN set -eux; \
  find ./extensions -name 'package.json' -type f | while read -r f; do \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*">=[^"]+"/"openclaw": "*"/g' "$f"; \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*"workspace:[^"]+"/"openclaw": "*"/g' "$f"; \
  done

RUN npm install -g pnpm@10.23.0

RUN pnpm install --no-frozen-lockfile
RUN pnpm build
RUN pnpm ui:install && pnpm ui:build


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

RUN npm install -g pnpm@10.23.0

COPY package.json ./
RUN npm install --omit=dev \
  && npm cache clean --force

COPY --from=openclaw-build /openclaw /openclaw

RUN printf '%s\n' \
  '#!/usr/bin/env bash' \
  'exec node /openclaw/dist/entry.js "$@"' \
  > /usr/local/bin/openclaw \
  && chmod +x /usr/local/bin/openclaw

COPY src ./src

RUN mkdir -p /data/npm /data/npm-cache /data/pnpm /data/pnpm-store

EXPOSE 8080
ENTRYPOINT ["tini", "--"]
CMD ["node", "src/server.js"]
