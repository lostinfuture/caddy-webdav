# `caddy-webdav` — Hardened Pre-built Caddy + WebDAV Image

[![Build and Publish Docker Image](https://github.com/lostinfuture/caddy-webdav/actions/workflows/build-docker.yml/badge.svg)](https://github.com/lostinfuture/caddy-webdav/actions/workflows/build-docker.yml)
[![Docker Image Version](https://img.shields.io/docker/v/lostinfuture/caddy-webdav?label=lostinfuture%2Fcaddy-webdav&style=flat-square)](https://hub.docker.com/r/lostinfuture/caddy-webdav/tags)
[![Docker Image Size](https://img.shields.io/docker/image-size/lostinfuture/caddy-webdav/latest?style=flat-square)](https://hub.docker.com/r/lostinfuture/caddy-webdav/tags)
[![Docker Pulls](https://img.shields.io/docker/pulls/lostinfuture/caddy-webdav?style=flat-square)](https://hub.docker.com/r/lostinfuture/caddy-webdav)

Pre-built, multi-arch (`linux/amd64`, `linux/arm64`, `linux/arm/v7`) [Caddy](https://github.com/caddyserver/caddy) Docker image bundled with the official [mholt/caddy-webdav](https://github.com/mholt/caddy-webdav) module.

Designed as an up-to-date, vulnerability-patched, drop-in replacement for [`juvenn/caddy-dav`](https://github.com/juvenn/caddy-dav):

- **Latest Caddy & Go toolchain** (`Caddy v2.11.7`, pure-Go static binary `CGO_ENABLED=0` with stripped debug symbols).
- **Hardened Alpine runtime**: Runs `apk upgrade --no-cache` during build and rebuilds weekly via GitHub Actions to eliminate OS and Go stdlib CVEs.
- **100% Configuration Compatible**: Uses the exact same paths (`/etc/caddy/Caddyfile`, `/data`, `/config`) and `webdav` Caddyfile syntax.

## Pull Image

From **Docker Hub**:

```bash
docker pull lostinfuture/caddy-webdav:latest
docker pull lostinfuture/caddy-webdav:2.11.7
```

From **GitHub Container Registry (GHCR)**:

```bash
docker pull ghcr.io/lostinfuture/caddy-webdav:latest
docker pull ghcr.io/lostinfuture/caddy-webdav:2.11.7
```

---

## Usage

### 1. Minimal WebDAV Server (Drop-in Compatible)

Put the following in your `Caddyfile`:

```caddyfile
{
  order webdav before file_server
}

media.local:8080 {
  root * /var/media
  webdav
}
```

### 2. WebDAV + Browser Directory Listing

WebDAV returns XML on `PROPFIND`, which browsers don't render as a file explorer on `GET`. Route `GET` and `HEAD` requests to `file_server browse` while sending all WebDAV methods (`PROPFIND`, `OPTIONS`, `PUT`, `MKCOL`, `DELETE`, `MOVE`, `COPY`, `LOCK`, `UNLOCK`) to `webdav`:

```caddyfile
{
  order webdav before file_server
}

media.local:8080 {
  @get method GET HEAD
  root * /var/media
  route {
    file_server @get browse
    webdav
  }
}
```

### 3. Authenticated & Performance-Tuned Setup (Recommended)

> [!IMPORTANT]
> In Caddy **v2.8+**, the `basicauth` directive was renamed to `basic_auth`. If migrating from an older `Caddyfile`, update `basicauth` to `basic_auth`.

```caddyfile
{
  order webdav before file_server

  servers {
    timeouts {
      # Prevent large multi-GB WebDAV uploads/downloads from timing out
      read_body   0
      read_header 15s
      write       0
      idle        5m
    }
  }
}

media.local:8080 {
  root * /var/media

  # Compresses verbose WebDAV XML PROPFIND responses & HTML listings by ~85%
  # (Caddy automatically skips already-compressed media like .mp4, .jpg, .zip)
  encode zstd gzip

  request_body {
    max_size 0
  }

  @get method GET HEAD

  route {
    basic_auth {
      # Generate with: docker run --rm lostinfuture/caddy-webdav caddy hash-password --plaintext 'secret'
      admin $2a$12$......................................................
    }
    file_server @get browse {
      hide .DS_Store ._* Thumbs.db desktop.ini
    }
    webdav
  }
}
```

---

## Performance & Security Tweaks

1. **Include `HEAD` in `@get` Matcher (`@get method GET HEAD`)**:
   Older snippets only matched `@get method GET`, causing `HEAD` requests from browsers and media players to hit `webdav` instead of `file_server` and breaking download size/range preflights.
2. **Enable `encode zstd gzip`**:
   WebDAV `PROPFIND` responses on large folders generate verbose XML payloads. Enabling compression speeds up directory listing in clients that support `Accept-Encoding` (`rclone`, modern browsers, mobile clients) without affecting binary media streaming.
3. **Bcrypt Cost vs. `argon2id` for Stateless WebDAV Auth**:
   WebDAV sends `Authorization: Basic ...` on **every request**. Caddy caches verified credentials in memory, so standard `bcrypt` (cost `12`–`14`) or `argon2id` works well while protecting against brute-force attempts.
4. **Go Runtime Memory Cap (`GOMEMLIMIT`)**:
   On small devices (Raspberry Pi, NAS, micro-VPS), set `GOMEMLIMIT=256MiB` in your container environment to keep Go's garbage collector bounded during heavy WebDAV transfers.
5. **HTTP/3 (QUIC) UDP Buffers**:
   Increase container/host UDP buffers (`net.core.rmem_max=7500000`, `net.core.wmem_max=7500000`) so Caddy's QUIC stack achieves full throughput.

---

## Credits

Re-packaged and hardened build of [Caddy](https://github.com/caddyserver/caddy) with [@mholt/caddy-webdav](https://github.com/mholt/caddy-webdav), inspired by [@juvenn/caddy-dav](https://github.com/juvenn/caddy-dav).
