# syntax=docker/dockerfile:1
# Faster multi-platform builds via Go cross-compilation on $BUILDPLATFORM:
# https://www.docker.com/blog/faster-multi-platform-builds-dockerfile-cross-compilation-guide/

ARG CADDY_VERSION=2.11.7
ARG BUILDPLATFORM
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

FROM --platform=$BUILDPLATFORM caddy:${CADDY_VERSION}-builder-alpine AS builder

ARG CADDY_VERSION
ARG BUILDPLATFORM
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

RUN set -eux; \
    echo "Building Caddy v${CADDY_VERSION#v} for ${TARGETPLATFORM} (${TARGETOS}/${TARGETARCH}${TARGETVARIANT}) on ${BUILDPLATFORM}"; \
    if [ "${TARGETARCH}" = "arm" ] && [ -n "${TARGETVARIANT}" ]; then \
        export GOARM="${TARGETVARIANT#v}"; \
    fi; \
    CGO_ENABLED=0 GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
        xcaddy build "v${CADDY_VERSION#v}" \
        --with github.com/mholt/caddy-webdav; \
    echo "Built binary at: $(readlink -f caddy)"

FROM caddy:${CADDY_VERSION}-alpine

ARG CADDY_VERSION

# Upgrade Alpine system packages to patch any OS-level CVEs released since base image build
RUN apk update \
    && apk upgrade --no-cache \
    && rm -rf /var/cache/apk/*

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# Ensure cap_net_bind_service is preserved after multi-stage COPY and verify binary + module
RUN set -eux; \
    setcap cap_net_bind_service=+ep /usr/bin/caddy; \
    chmod +x /usr/bin/caddy; \
    caddy version; \
    caddy list-modules | grep -q "http.handlers.webdav"

LABEL org.opencontainers.image.title="caddy-webdav" \
      org.opencontainers.image.description="Hardened pre-built Caddy image with WebDAV plugin (mholt/caddy-webdav)" \
      org.opencontainers.image.version="v${CADDY_VERSION#v}" \
      org.opencontainers.image.source="https://github.com/lostinfuture/caddy-webdav" \
      org.opencontainers.image.licenses="Apache-2.0"
