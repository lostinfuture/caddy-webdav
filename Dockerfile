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
    GO_TOOLCHAIN_VER="$(wget -qO- https://proxy.golang.org/golang.org/toolchain/@v/list | grep -Eo '^v0\.0\.1-go[0-9]+\.[0-9]+\.[0-9]+\.linux-amd64$' | sed -E 's/^v0\.0\.1-(go[0-9]+\.[0-9]+\.[0-9]+)\.linux-amd64$/\1/' | sort -V | tail -n1)"; \
    printf '%s' "${GO_TOOLCHAIN_VER}" > /tmp/go-toolchain-ver; \
    export GOTOOLCHAIN="${GO_TOOLCHAIN_VER}+auto"; \
    X_NET_VER="$(go list -m -f '{{.Version}}' golang.org/x/net@latest)"; \
    X_CRYPTO_VER="$(go list -m -f '{{.Version}}' golang.org/x/crypto@latest)"; \
    echo "Using Go toolchain: $(go version) | Patching Go dependencies: golang.org/x/net@${X_NET_VER}, golang.org/x/crypto@${X_CRYPTO_VER} (stripping deprecated openpgp)"; \
    go mod download "golang.org/x/crypto@${X_CRYPTO_VER}"; \
    cp -R "$(go env GOMODCACHE)/golang.org/x/crypto@${X_CRYPTO_VER}" /tmp/x-crypto; \
    chmod -R u+w /tmp/x-crypto; \
    rm -rf /tmp/x-crypto/openpgp; \
    CGO_ENABLED=0 GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
        xcaddy build "v${CADDY_VERSION#v}" \
        --output /usr/bin/caddy \
        --with github.com/mholt/caddy-webdav@v0.0.0-20260127042217-fa2f366b0d75 \
        --replace "golang.org/x/net=golang.org/x/net@${X_NET_VER}" \
        --replace "golang.org/x/crypto=/tmp/x-crypto"; \
    rm -rf /tmp/x-crypto; \
    mkdir -p \
        /rootfs/config/caddy \
        /rootfs/data/caddy \
        /rootfs/etc/caddy \
        /rootfs/etc/ssl/certs \
        /rootfs/srv \
        /rootfs/tmp \
        /rootfs/usr/bin \
        /rootfs/var/media \
    ; \
    chmod 1777 /rootfs/config/caddy /rootfs/data/caddy /rootfs/tmp; \
    cp /etc/ssl/certs/ca-certificates.crt /rootfs/etc/ssl/certs/ca-certificates.crt; \
    cp /etc/mime.types /rootfs/etc/mime.types; \
    printf 'root:x:0:0:root:/root:/sbin/nologin\nnobody:x:65534:65534:nobody:/:/sbin/nologin\n' > /rootfs/etc/passwd; \
    printf 'root:x:0:\nnobody:x:65534:\n' > /rootfs/etc/group; \
    printf 'hosts: files dns\n' > /rootfs/etc/nsswitch.conf; \
    cp /usr/bin/caddy /rootfs/usr/bin/caddy; \
    chmod 0755 /rootfs/usr/bin/caddy; \
    setcap cap_net_bind_service=+ep /rootfs/usr/bin/caddy; \
    if [ "${BUILDPLATFORM}" = "${TARGETPLATFORM}" ]; then \
        /rootfs/usr/bin/caddy version; \
        /rootfs/usr/bin/caddy list-modules | grep -q "http.handlers.webdav"; \
    fi

# Default config is the Infuse library server. A mounted /etc/caddy replaces it.
COPY Caddyfile.example /rootfs/etc/caddy/Caddyfile
COPY healthcheck.go /tmp/healthcheck/main.go

# Native builds also start the server and request a folder listing plus a byte range.
# Cross-compiled builds only produce the binary; CI runs those under QEMU after publish.
RUN set -eu; \
    if [ "${TARGETARCH}" = "arm" ] && [ -n "${TARGETVARIANT}" ]; then \
        export GOARM="${TARGETVARIANT#v}"; \
    fi; \
    export GOTOOLCHAIN="$(cat /tmp/go-toolchain-ver)+auto"; \
    cd /tmp/healthcheck; \
    go mod init healthcheck; \
    CGO_ENABLED=0 GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
        go build -trimpath -ldflags '-s -w' -o /rootfs/usr/bin/healthcheck .; \
    if [ "${BUILDPLATFORM}" = "${TARGETPLATFORM}" ]; then \
        /rootfs/usr/bin/healthcheck version; \
        mkdir -p /tmp/caddy-smoke/config /tmp/caddy-smoke/data /var/media/Movies; \
        printf 'sample-video\n' > /var/media/Movies/demo.txt; \
        XDG_CONFIG_HOME=/tmp/caddy-smoke/config XDG_DATA_HOME=/tmp/caddy-smoke/data \
            /rootfs/usr/bin/caddy validate --config /rootfs/etc/caddy/Caddyfile --adapter caddyfile; \
        XDG_CONFIG_HOME=/tmp/caddy-smoke/config XDG_DATA_HOME=/tmp/caddy-smoke/data \
        ACCESS_LOG_OUTPUT=discard \
            /rootfs/usr/bin/caddy run --config /rootfs/etc/caddy/Caddyfile --adapter caddyfile & \
        pid=$!; \
        ok=0; \
        i=0; \
        while [ "$i" -lt 40 ]; do \
            if /rootfs/usr/bin/healthcheck && /rootfs/usr/bin/healthcheck range; then \
                ok=1; \
                break; \
            fi; \
            i=$((i + 1)); \
            sleep 0.25; \
        done; \
        kill "$pid" || true; \
        wait "$pid" || true; \
        [ "$ok" = 1 ]; \
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
ENV ACCESS_LOG_OUTPUT=discard
ENV ACCESS_LOG_FORMAT=json

LABEL org.opencontainers.image.title="caddy-webdav" \
      org.opencontainers.image.description="Local media streaming for Apple TV and Infuse. Pre-built Caddy image with the WebDAV plugin." \
      org.opencontainers.image.version="v${CADDY_VERSION#v}" \
      org.opencontainers.image.source="https://github.com/lostinfuture/caddy-webdav" \
      org.opencontainers.image.licenses="Apache-2.0"

EXPOSE 80
EXPOSE 443
EXPOSE 443/udp
EXPOSE 2019

WORKDIR /srv

# Root is deliberate. Movie folders on a NAS are often mode 750 and unreadable
# by nobody, so dropping privileges would make the library look empty.
# cap_net_bind_service on the binary still lets `--user nobody` bind port 80
# when the files are readable by that user.
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD ["/usr/bin/healthcheck"]

CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
