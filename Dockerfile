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
    X_NET_VER="$(go list -m -f '{{.Version}}' golang.org/x/net@latest)"; \
    X_CRYPTO_VER="$(go list -m -f '{{.Version}}' golang.org/x/crypto@latest)"; \
    echo "Patching Go dependencies: golang.org/x/net@${X_NET_VER}, golang.org/x/crypto@${X_CRYPTO_VER}"; \
    CGO_ENABLED=0 GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
        xcaddy build "v${CADDY_VERSION#v}" \
        --with github.com/mholt/caddy-webdav \
        --replace "golang.org/x/net=golang.org/x/net@${X_NET_VER}" \
        --replace "golang.org/x/crypto=golang.org/x/crypto@${X_CRYPTO_VER}"; \
    echo "Built binary at: $(readlink -f caddy)"

# Build clean runtime image directly from alpine:3.23 instead of caddy:alpine
# so the unpatched stock /usr/bin/caddy layer is not retained in image history
FROM alpine:3.23

ARG CADDY_VERSION=2.11.7

RUN set -eux; \
    apk update; \
    apk upgrade --no-cache; \
    apk add --no-cache \
        ca-certificates \
        curl \
        libcap \
        mailcap \
    ; \
    rm -rf /var/cache/apk/*; \
    mkdir -p \
        /config/caddy \
        /data/caddy \
        /etc/caddy \
        /usr/share/caddy \
    ; \
    chmod 1777 /config/caddy /data/caddy; \
    wget -O /etc/caddy/Caddyfile "https://github.com/caddyserver/dist/raw/33ae08ff08d168572df2956ed14fbc4949880d94/config/Caddyfile"; \
    wget -O /usr/share/caddy/index.html "https://github.com/caddyserver/dist/raw/33ae08ff08d168572df2956ed14fbc4949880d94/welcome/index.html"

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

RUN set -eux; \
    setcap cap_net_bind_service=+ep /usr/bin/caddy; \
    chmod +x /usr/bin/caddy; \
    caddy version; \
    caddy list-modules | grep -q "http.handlers.webdav"

# See https://caddyserver.com/docs/conventions#file-locations for details
ENV CADDY_VERSION=v${CADDY_VERSION#v}
ENV XDG_CONFIG_HOME=/config
ENV XDG_DATA_HOME=/data

LABEL org.opencontainers.image.title="caddy-webdav" \
      org.opencontainers.image.description="Hardened pre-built Caddy image with WebDAV plugin (mholt/caddy-webdav)" \
      org.opencontainers.image.version="v${CADDY_VERSION#v}" \
      org.opencontainers.image.source="https://github.com/lostinfuture/caddy-webdav" \
      org.opencontainers.image.licenses="Apache-2.0"

EXPOSE 80
EXPOSE 443
EXPOSE 443/udp
EXPOSE 2019

WORKDIR /srv

CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
