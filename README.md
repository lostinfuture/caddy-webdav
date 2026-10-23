# caddy-webdav

[![Build and Publish Docker Image](https://github.com/lostinfuture/caddy-webdav/actions/workflows/build-docker.yml/badge.svg)](https://github.com/lostinfuture/caddy-webdav/actions/workflows/build-docker.yml)
[![Docker Image Version](https://img.shields.io/docker/v/lostinfuture/caddy-webdav?label=lostinfuture%2Fcaddy-webdav&style=flat-square)](https://hub.docker.com/r/lostinfuture/caddy-webdav/tags)
[![Docker Image Size](https://img.shields.io/docker/image-size/lostinfuture/caddy-webdav/latest?style=flat-square)](https://hub.docker.com/r/lostinfuture/caddy-webdav/tags)
[![Docker Pulls](https://img.shields.io/docker/pulls/lostinfuture/caddy-webdav?style=flat-square)](https://hub.docker.com/r/lostinfuture/caddy-webdav)

Local media streaming for **Apple TV + [Infuse](https://firecore.com/app/infuse)**. Point it at the folder where your movies and shows already live. Infuse browses that folder over your home network and plays the files directly.

Under the hood it is a pre-built [Caddy](https://caddyserver.com) image with the [WebDAV](https://github.com/mholt/caddy-webdav) plugin, ready for a PC, a Raspberry Pi, or a NAS (`linux/amd64`, `linux/arm64`, `linux/arm/v7`).

## Local media streaming

Your movies stay on a disk in the house. This container serves that disk to Infuse on the same network. Infuse does the posters, the metadata, and the playback. The server hands over folder listings and video bytes.

That is the whole product: a library Infuse can scan quickly, and a stream that still works when the file is a large 4K HDR or Dolby Vision remux.

The same address also works in Infuse on iPhone, iPad, and Mac. Apple TV is the setup this image is tuned for.

## Why this fits Infuse

Infuse plays the original file on the Apple TV. It asks the server two things:

- **What is in this folder?** WebDAV `PROPFIND` listings, which Infuse uses to build the library.
- **Give me this part of the file.** HTTP range requests, which Infuse uses to start, seek, and resume.

The config baked into the image (`Caddyfile.example` in the repo) is arranged around those two requests. Listings are compressed so a big library scans faster. Video is sent uncompressed, straight from disk, so seeking stays responsive and a long remux is not cut off by a timeout.

There is no transcoder, no library database, and no second copy of your files.

## Advantages

- **Direct play.** Infuse plays the file you stored. A high-bitrate remux stays a remux.
- **Seeking that feels local.** Play, scrub, and resume are ordinary HTTP range requests.
- **Faster library scans.** Folder listings are compressed. The video stream is left alone.
- **Long movies stay connected.** The write timeout is off, so a two-hour file is not dropped at a default limit.
- **One container.** A folder in, a WebDAV address out. Works on x86 and on common ARM boards and NAS devices.
- **Check it before you pick up the remote.** Open the same address in a laptop browser and you get a directory listing.
- **Stays current.** The image is rebuilt every Monday with the current Caddy release and patched Go libraries.
- **Small runtime.** The running container is the Caddy binary, CA certificates, and MIME types. No shell and no package manager.

## Before you start

- Docker, on a machine that can see your Apple TV.
- A folder of media. Names like `Movie Name (2024).mkv` are what Infuse matches against.
- Infuse, installed on the Apple TV.
- The Apple TV and the server on the same home network. A wired Apple TV is the comfortable choice for very high-bitrate remuxes.

The media folder is writable on purpose. When you delete a title in Infuse, Infuse removes the file over WebDAV. The same open share means anyone who can reach port 80 on this machine can browse, upload, or delete. Keep that port off your router’s port-forwarding list. Add the password below if guests use the Wi-Fi.

## Start the server

The image already includes the Infuse config. It serves whatever you mount at `/var/media`. No extra config file is required.

### Docker Compose

Edit the two paths in `docker-compose.yml`, then start it:

```yaml
services:
  caddy-webdav:
    image: lostinfuture/caddy-webdav:latest
    container_name: caddy-webdav
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - /path/to/caddy/data:/data
      - /path/to/your/movies:/var/media
```

```bash
docker compose up -d
```

Leave the media volume writable. Infuse uses that to delete a file when you remove it in the app. The same path accepts uploads from Finder, Cyberduck, or rclone.

### Docker CLI

```bash
docker run -d \
  --name caddy-webdav \
  --restart unless-stopped \
  -p 80:80 \
  -v /path/to/caddy/data:/data \
  -v /path/to/your/movies:/var/media \
  lostinfuture/caddy-webdav:latest
```

### Check it from a laptop

Open `http://<server-ip>/` in a browser. You should see your folders.

Find the server address on the machine running Docker (`hostname -I`) or in your router’s device list.

### Changing the config

Copy `Caddyfile.example` to a file named `Caddyfile`, edit that copy, and mount its directory over `/etc/caddy`. The mount replaces the built-in config. An empty directory hides the built-in file and the container will not start.

```yaml
- /path/to/caddy/conf:/etc/caddy
```

## Add it in Infuse on Apple TV

This server does not announce itself on the network. Infuse’s automatic share list will not show it. Add it by hand.

1. Open Infuse. The menu is **Add → Shares**, or **Settings → Add Files**, depending on the version.
2. Choose **WebDAV**. If you only see discovered devices, open **Other…** and pick WebDAV there.
3. Address: the server’s LAN IP, for example `192.168.1.20`. If the field wants a URL, use `http://192.168.1.20`.
4. Port: `80`. Leave the username and password empty. Leave the path empty to see the whole library, or set a folder such as `/Movies`.
5. Save. Infuse checks the connection.
6. Add at least one **favorite**. On Apple TV, highlight a folder (Movies, Shows, or the library root) and hold Select. Favorites are the folders Infuse puts on the home screen. Apple TV needs one before it will play anything.

Play a file and scrub forward. A quick start and a working seek means the server is doing its job. If a particular file will not play, that is an Infuse codec question. This server does not convert video.

The [Firecore guide](https://support.firecore.com/hc/en-us/articles/215090977-Streaming-From-a-Mac-PC-or-NAS) covers the same share flow on iPhone, iPad, and Mac.

### If something feels wrong

- **The browser listing is empty.** The media volume is mounted on the wrong host path, or it is empty. The container always looks at `/var/media`.
- **The container exits as soon as it starts.** A mount on `/etc/caddy` replaced the built-in config, and that directory has no file named `Caddyfile`.
- **Playback stutters on a large remux.** The Apple TV has to receive the full bitrate. Ethernet on the Apple TV is the reliable fix. The server is already sending the file as-is.
- **Play dies after a long pause.** Idle connections close after 10 minutes. Press play again. Infuse asks for a fresh range and continues.
- **Delete in Infuse does nothing.** The media volume is mounted read-only, or the host folder is not writable by the container. The Compose file leaves it writable.

## Optional password

On a home network where guests use the Wi-Fi, put a password on the share. Infuse has username and password fields for this.

Generate a hash:

```bash
docker run --rm lostinfuture/caddy-webdav:latest \
  caddy hash-password --plaintext 'a-real-password'
```

Bcrypt hashes contain `$`. A Compose file treats `$` as its own variable, and a `Caddyfile` treats `$` as the start of a placeholder. Put the hash in an environment variable, and double every `$` in the Compose file so Compose passes the hash through unchanged.

```yaml
environment:
  - INFUSE_PASSWORD_HASH=$$2a$$14$$paste-the-generated-hash-here
```

With `docker run`, single quotes are enough:

```bash
-e INFUSE_PASSWORD_HASH='$2a$14$paste-the-generated-hash-here'
```

Copy `Caddyfile.example` to `Caddyfile`, add this inside the `:80` block above `root`, and mount that directory on `/etc/caddy` as described in [Changing the config](#changing-the-config):

```caddyfile
basicauth {
	infuse {$INFUSE_PASSWORD_HASH}
}
```

Restart the container, then enter user `infuse` and that password in the Infuse share. Deletes from Infuse still work. The password only decides who is allowed to send them.

## Logs and memory

| Variable | Default | What to set |
| :--- | :--- | :--- |
| `ACCESS_LOG_OUTPUT` | `discard` | `stdout` while you are debugging a share. `file /data/access.log` keeps the lines on the data volume. Startup lines from Caddy itself still appear in `docker logs`. |
| `ACCESS_LOG_FORMAT` | `json` | `console` if you read `docker logs` yourself and want plain lines. |
| `GOMEMLIMIT` | `512MiB` | Soft memory target for the Go runtime while Infuse scans a large library. Raised only if scans are slow and the machine has RAM to spare. |

```bash
docker logs -f caddy-webdav
```

## Pull the image

Docker Hub:

```bash
docker pull lostinfuture/caddy-webdav:latest
docker pull lostinfuture/caddy-webdav:2.11.7
```

GitHub Container Registry:

```bash
docker pull ghcr.io/lostinfuture/caddy-webdav:latest
docker pull ghcr.io/lostinfuture/caddy-webdav:2.11.7
```

Monday builds publish `latest`, `2`, `2.11`, and the patch tag such as `2.11.7`. The patch tag names the Caddy release and is rebuilt when Go patches land, so pin the image digest when you want a frozen binary. The WebDAV plugin inside the image is pinned. The Go libraries are not, because those are the patches the weekly build exists to pick up.

## How the tuning works

That behavior comes from the config shipped at `/etc/caddy/Caddyfile`. `Caddyfile.example` is the same file. The short version:

- The site listens on `:80` with `auto_https off`, so Infuse can connect by IP or by a `.local` name. A bare hostname would make Caddy try to issue a certificate and then reject requests whose `Host` header does not match.
- `GET` and `HEAD` go to `file_server`. Those are play and seek. On Linux, Caddy can hand that response to the kernel’s `sendfile`, which keeps the video out of the Go process.
- `encode` applies only to `PROPFIND`. Those are the folder listings. Compressing the video too would pull the bytes back through userspace and give up `sendfile`.
- `read_body` and `write` timeouts are `0`. `idle` is `10m`.
- `request_body max_size 0` removes the upload cap for a writable library.
- The browser listing hides macOS and Windows clutter (`.DS_Store`, `._*`, `Thumbs.db`, and similar). Infuse uses WebDAV, and that handler still lists those files. They are small, and Infuse skips them.

`GOMEMLIMIT=512MiB` is set in the image. The Compose file repeats it so you can see and change it.

Publish port `80` only. Port `2019` on the image is Caddy’s admin API. Leave it unmapped.

## Credits

Pre-built, hardened packaging of [Caddy](https://github.com/caddyserver/caddy) with [@mholt/caddy-webdav](https://github.com/mholt/caddy-webdav). The paths and `webdav` syntax match [@juvenn/caddy-dav](https://github.com/juvenn/caddy-dav), so an existing config can move over by changing the image name.
