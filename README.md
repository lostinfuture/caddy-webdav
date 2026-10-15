# `caddy-webdav` — Hardened Pre-built Caddy + WebDAV Image

[![Build and Publish Docker Image](https://github.com/lostinfuture/caddy-webdav/actions/workflows/build-docker.yml/badge.svg)](https://github.com/lostinfuture/caddy-webdav/actions/workflows/build-docker.yml)
[![Docker Image Version](https://img.shields.io/docker/v/lostinfuture/caddy-webdav?label=lostinfuture%2Fcaddy-webdav&style=flat-square)](https://hub.docker.com/r/lostinfuture/caddy-webdav/tags)
[![Docker Image Size](https://img.shields.io/docker/image-size/lostinfuture/caddy-webdav/latest?style=flat-square)](https://hub.docker.com/r/lostinfuture/caddy-webdav/tags)
[![Docker Pulls](https://img.shields.io/docker/pulls/lostinfuture/caddy-webdav?style=flat-square)](https://hub.docker.com/r/lostinfuture/caddy-webdav)

Pre-built, multi-arch (`linux/amd64`, `linux/arm64`, `linux/arm/v7`) [Caddy](https://github.com/caddyserver/caddy) Docker image bundled with the official [mholt/caddy-webdav](https://github.com/mholt/caddy-webdav) module.

Designed as an up-to-date, vulnerability-patched, drop-in replacement for [`juvenn/caddy-dav`](https://github.com/juvenn/caddy-dav):

- **Latest Caddy & Go toolchain** (`Caddy v2.11.7`, pure-Go static binary `CGO_ENABLED=0` with stripped debug symbols).
- **Zero-OS-Package `scratch` Runtime**: Ships only the static `/usr/bin/caddy` binary, TLS CA roots, and `/etc/mime.types` (`FROM scratch` — no `busybox`, `apk`, `curl`, or `openssl` attack surface) and rebuilds weekly via GitHub Actions.
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

## Run Container

> [!NOTE]
> Place your `Caddyfile` inside your host config directory (e.g. `/path/to/caddy/conf/Caddyfile`) so that mounting `/path/to/caddy/conf:/etc/caddy` exposes it at `/etc/caddy/Caddyfile` inside the container.

### Docker CLI

```bash
docker run -d \
  --name caddy-webdav \
  --restart unless-stopped \
  -p 80:80 \
  -v /path/to/caddy/conf:/etc/caddy \
  -v /path/to/caddy/data:/data \
  -v /path/to/media:/var/media \
  lostinfuture/caddy-webdav:latest
```

### Docker Compose

```yaml
services:
  caddy-webdav:
    image: lostinfuture/caddy-webdav:latest
    container_name: caddy-webdav
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - /path/to/caddy/conf:/etc/caddy
      - /path/to/caddy/data:/data
      - /path/to/media:/var/media
```

---

## Configuration Examples (`/etc/caddy/Caddyfile`)

Save one of the configurations below as `Caddyfile` in your mounted config directory (`/path/to/caddy/conf/Caddyfile` on the host -> `/etc/caddy/Caddyfile` in the container):

### 1. Minimal WebDAV Server (Drop-in Compatible)

```caddyfile
{
  order webdav before file_server
}

:80 {
  root * /var/media
  webdav
}
```

### 2. WebDAV + Browser Directory Listing

Route `GET` and `HEAD` requests to `file_server browse` while sending all WebDAV methods (`PROPFIND`, `OPTIONS`, `PUT`, `MKCOL`, `DELETE`, `MOVE`, `COPY`, `LOCK`, `UNLOCK`) to `webdav`:

```caddyfile
{
  order webdav before file_server
}

:80 {
  @get method GET HEAD
  root * /var/media
  route {
    file_server @get browse
    webdav
  }
}
```

### 3. Local LAN Video Streaming — Apple TV + Infuse Tuned (No Auth)

Optimized specifically for high-bitrate 4K HDR / Dolby Vision Remux streaming over local LAN to **Infuse** on Apple TV:

```caddyfile
{
  order webdav before file_server
  auto_https off

  servers {
    protocols h1 h2c
    timeouts {
      read_body   0
      read_header 15s
      write       0
      idle        10m
    }
  }
}

:80 {
  root * /var/media

  # Compress ONLY WebDAV PROPFIND XML responses (~85% smaller -> faster Infuse folder indexing)
  # while keeping GET video streams uncompressed for Linux kernel zero-copy sendfile(2) DMA
  @propfind method PROPFIND
  encode @propfind zstd gzip

  request_body {
    max_size 0
  }

  @get method GET HEAD

  route {
    file_server @get browse {
      hide .DS_Store ._* Thumbs.db desktop.ini .Spotlight-V100 .Trashes
    }
    webdav
  }
}
```

---

## Performance & Config Tweaks for Apple TV + Infuse

1. **Zero-Copy `sendfile(2)` Streaming (`@get method GET HEAD` + `file_server`)**:
   Routing `GET` and `HEAD` to Caddy's native `file_server` allows HTTP byte-range requests (`Range: bytes=...`) used by Infuse for seeking and streaming to use the Linux kernel's `sendfile(2)` syscall (DMA directly from filesystem page cache to the network socket without copying through Go userspace buffers).
2. **Scope Compression to `@propfind method PROPFIND`**:
   Applying `encode` globally wraps `http.ResponseWriter`, which can bypass `sendfile(2)` on `GET` requests. Scoping `encode @propfind zstd gzip` compresses verbose WebDAV `PROPFIND` XML directory listings by ~85% (making Infuse library scans fast) while keeping `GET` video streams 100% zero-copy.
3. **Use `:80` + `auto_https off` on Local LAN**:
   In Caddy 2, specifying a hostname like `media.local` without `http://` triggers Caddy's internal CA (`tls internal`) and strict `Host` header matching. Using `:80` with `auto_https off` serves plain HTTP on default port `80` whether Infuse connects via IP (`192.168.x.x`), `apple.local`, or `media.local`.
4. **Go Runtime Memory Cap (`GOMEMLIMIT=512MiB`)**:
   Baked into the image (`ENV GOMEMLIMIT=512MiB`) to keep Go's garbage collector bounded during concurrent 4K Remux transfers without needing extra `-e` flags.

---

## Credits

Re-packaged and hardened build of [Caddy](https://github.com/caddyserver/caddy) with [@mholt/caddy-webdav](https://github.com/mholt/caddy-webdav), inspired by [@juvenn/caddy-dav](https://github.com/juvenn/caddy-dav).
