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
    apk add --no-cache ca-certificates libcap mailcap; \
    echo "Building Caddy v${CADDY_VERSION#v} for ${TARGETPLATFORM} (${TARGETOS}/${TARGETARCH}${TARGETVARIANT}) on ${BUILDPLATFORM}"; \
    if [ "${TARGETARCH}" = "arm" ] && [ -n "${TARGETVARIANT}" ]; then \
        export GOARM="${TARGETVARIANT#v}"; \
    fi; \
    X_NET_VER="$(go list -m -f '{{.Version}}' golang.org/x/net@latest)"; \
    X_CRYPTO_VER="$(go list -m -f '{{.Version}}' golang.org/x/crypto@latest)"; \
    echo "Patching Go dependencies: golang.org/x/net@${X_NET_VER}, golang.org/x/crypto@${X_CRYPTO_VER}"; \
    CGO_ENABLED=0 GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
        xcaddy build "v${CADDY_VERSION#v}" \
        --output /usr/bin/caddy \
        --with github.com/mholt/caddy-webdav \
        --replace "golang.org/x/net=golang.org/x/net@${X_NET_VER}" \
        --replace "golang.org/x/crypto=golang.org/x/crypto@${X_CRYPTO_VER}"; \
    mkdir -p \
        /rootfs/config/caddy \
        /rootfs/data/caddy \
        /rootfs/etc/caddy \
        /rootfs/etc/ssl/certs \
        /rootfs/srv \
        /rootfs/tmp \
        /rootfs/usr/bin \
        /rootfs/usr/share/caddy \
    ; \
    chmod 1777 /rootfs/config/caddy /rootfs/data/caddy /rootfs/tmp; \
    cp /etc/ssl/certs/ca-certificates.crt /rootfs/etc/ssl/certs/ca-certificates.crt; \
    cp /etc/mime.types /rootfs/etc/mime.types; \
    printf 'root:x:0:0:root:/root:/sbin/nologin\nnobody:x:65534:65534:nobody:/:/sbin/nologin\n' > /rootfs/etc/passwd; \
    printf 'root:x:0:\nnobody:x:65534:\n' > /rootfs/etc/group; \
    printf 'hosts: files dns\n' > /rootfs/etc/nsswitch.conf; \
    wget -O /rootfs/etc/caddy/Caddyfile "https://github.com/caddyserver/dist/raw/33ae08ff08d168572df2956ed14fbc4949880d94/config/Caddyfile"; \
    wget -O /rootfs/usr/share/caddy/index.html "https://github.com/caddyserver/dist/raw/33ae08ff08d168572df2956ed14fbc4949880d94/welcome/index.html"; \
    cp /usr/bin/caddy /rootfs/usr/bin/caddy; \
    chmod 0755 /rootfs/usr/bin/caddy; \
    setcap cap_net_bind_service=+ep /rootfs/usr/bin/caddy; \
    if [ "${BUILDPLATFORM}" = "${TARGETPLATFORM}" ]; then \
        /rootfs/usr/bin/caddy version; \
        /rootfs/usr/bin/caddy list-modules | grep -q "http.handlers.webdav"; \
    fi

# Minimal scratch runtime: contains only the static Caddy binary, TLS CA roots,
# MIME types, and default config/data directories (0 OS packages -> 0 OS CVEs)
FROM scratch

ARG CADDY_VERSION=2.11.7

COPY --from=builder /rootfs /

# See https://caddyserver.com/docs/conventions#file-locations for details
ENV PATH=/usr/bin:/bin
ENV CADDY_VERSION=v${CADDY_VERSION#v}
ENV XDG_CONFIG_HOME=/config
ENV XDG_DATA_HOME=/data
ENV GOMEMLIMIT=512MiB
ENV ACCESS_LOG_OUTPUT=stdout
ENV ACCESS_LOG_FORMAT=console

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
