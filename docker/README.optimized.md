# Optimized Docker image

`Dockerfile.optimized` is an alternate packaging of the published Proxy Manager
npm package. The original Dockerfile and application source are unchanged.
Like the original Dockerfile, it does **not** build the local application source.

The build supports `linux/amd64` and `linux/arm64`. Both retain the web UI/HAR
viewer, SSL analysis, all four CLI aliases, root user, and the upstream default
command (`luminati --help`). A native browser is included by default and can be
omitted with `--no-chrome`.

| Architecture | Browser |
| --- | --- |
| `amd64` | Puppeteer's pinned Chrome download. |
| `arm64` | Debian's native Chromium package. |

The separate Chrome Headless Shell is omitted on both architectures. The
application's browser action launches full Chrome with `headless: false`; no
application call selects Puppeteer's `headless: 'shell'` mode. Full Chrome can
also run in its normal headless mode.

The pinned Puppeteer version maps Linux ARM64 browser downloads to AMD64 binaries.
ARM64 therefore skips those downloads and sets `PUPPETEER_EXECUTABLE_PATH` to
`/usr/bin/chromium`. This uses Puppeteer's supported system-browser configuration
without modifying application code. Debian's browser version can differ from
Puppeteer's pinned Chrome, so ARM64 browser automation compatibility needs runtime
validation. SSL analysis/HAR capture is implemented separately in Node.

The browser action launches Chrome inside the container and requires a working
graphical display, such as a forwarded X server. The image provides no display
server or browser streaming service.

With `--no-chrome`, neither Chrome/Chromium nor its GUI libraries are included.
Proxying, SSL analysis, and the HAR viewer remain available. The web UI's
**Browser** action cannot launch a browser in this variant. Runtime browser
downloads are disabled in both variants, so using that action does not silently
install Chrome into a browser-free container. The Puppeteer JavaScript package
remains installed because the application imports it at startup.

## Build

From the repository root, with Docker and Buildx installed:

```sh
./scripts/build-image-optimized.sh arm64 --dry-run
./scripts/build-image-optimized.sh arm64 --check
./scripts/build-image-optimized.sh arm64

# Or build the existing AMD64 variant:
./scripts/build-image-optimized.sh amd64

# Omit Chrome and its GUI libraries, retaining SSL analysis and HAR:
./scripts/build-image-optimized.sh arm64 --no-chrome

# Validate that variant without building:
./scripts/build-image-optimized.sh arm64 --no-chrome --check
```

The architecture argument is required and selects `--platform linux/amd64` or
`--platform linux/arm64`. Both use the default tag
`luminati-proxy:1.679.135-optimized` for this checkout. With `--no-chrome`, the tag
is `luminati-proxy:1.679.135-optimized-no-chrome`, keeping the two feature variants
separate. Architecture is expressed through `--platform`, without an architecture
suffix in either tag. Separate local builds do not automatically combine the
architectures under a multi-platform manifest.
Use different `IMAGE_TAG` values when keeping comparison builds side by side.
For a future registry release, publish a multi-platform manifest under the
shared tag so Docker can select the appropriate architecture when pulling.

`--dry-run` only prints the command. `--check` asks BuildKit to validate
the Dockerfile without executing build instructions or producing an image; it
may fetch Dockerfile frontend and base-image metadata.

The script reads the application version from `package.json.version` and the
exact Node version from the original Dockerfile's `FROM node:<version>-bookworm`
line. The package's supported Node ranges are not used as image version pins.
An unrecognized or ambiguous Node pin causes an error requesting an explicit
override. Versions and the output tag can be overridden explicitly:

```sh
LPM_VERSION=1.679.135 NODE_VERSION=24.13.0 IMAGE_TAG=luminati-proxy:comparison-arm64 \
    ./scripts/build-image-optimized.sh arm64
```

Additional Buildx options can be passed after `--`, for example `-- --no-cache`.
Do not pass `--platform` there; the architecture argument controls the platform.
The script defaults to loading the image locally and never pushes by default.
Node and native addons are built for the selected target architecture, including
when Docker uses emulation on a host with a different architecture. On Apple
Silicon, `arm64` runs natively while `amd64` needs emulation.

For direct `docker buildx` use, supply both `--build-arg LPM_VERSION=<version>`
and `--build-arg NODE_VERSION=<version>` and select the platform with
`--platform linux/arm64` or `--platform linux/amd64`. The alternate Dockerfile
intentionally has no application or Node version defaults; the script supplies
them from the existing upstream files.

The Dockerfile defaults to `WITH_CHROME=true`. For a direct browser-free build,
also pass `--build-arg WITH_CHROME=false`. BuildKit skips the browser-only stages
entirely, so their packages do not enter the browser-free image's layers.

Top-level versions are pinned; the upstream npm package has no committed lockfile
here, so transitive npm dependencies and Debian packages can still change.

## Size changes

Reported local image sizes for Proxy Manager 1.679.135:

| Image | Local size | Reduction from the published image |
| --- | --- | --- |
| Published upstream, AMD64 | 4.81 GB | — |
| Initial optimized build, AMD64 | 1.78 GB | About 63% |
| Initial optimized build, ARM64 | 1.96 GB | About 59% |
| Current optimized build, ARM64, `--no-chrome` | 666.5 MB | About 86% |

These figures describe local image storage; registry download sizes differ.
The initial optimized builds predate the removal of Headless Shell and the legacy
GConf/AppIndicator/GTK2 packages. Current browser-enabled sizes have not yet been
measured.

- A full Node builder compiles native dependencies, while the final image uses
  `node:24.13.0-bookworm-slim` and browser/runtime libraries.
- The application is installed once with production dependencies. Compilers,
  Node build headers, the builder's npm cache, and its npm upgrade stay out of
  the final image.
- AMD64 retains only Puppeteer's full Chrome download in `/opt/puppeteer`, outside
  the `/root` directory used by existing configuration volumes. Its separate
  Headless Shell download is disabled. ARM64 installs Chromium without the
  `chromium-headless-shell` package.
- The legacy `gconf-service` and `libappindicator1` packages are omitted, avoiding
  their GConf/GTK2 dependency chain while retaining the GTK3 libraries used by
  current Chrome.
- With `--no-chrome`, browser downloads, Chromium installation, fonts, and the
  browser GUI library stages are all omitted.
- APT metadata is removed in the same layer that installs the runtime packages,
  and recommended packages are not installed.
- The extra Google Chrome `.deb` download/install/delete steps are omitted.
  The inspected published image had no installed `google-chrome-stable` package;
  its browser payload came from Puppeteer downloads.

The build checks for bundled UI assets and unresolved shared libraries in native
addons. Browser-enabled builds also check the Puppeteer executable and its shared
libraries. Browser-free builds check that the browser cache is empty and no system
Chromium executable is present.

The built ARM64 browser-free image passed a CLI startup check; Chromium and the
GTK2/GTK3/GConf/AppIndicator packages were confirmed absent. A disposable ARM64
container also launched full Chromium and rendered HTML after Headless Shell and
the legacy packages were removed. End-to-end proxying, SSL analysis, and HAR checks
remain outstanding.

## Existing TLS settings

This packaging preserves the inspected published image's additional
trust bundle and `UnsafeLegacyRenegotiation` OpenSSL setting. Changing those is a
separate compatibility decision. They are configured explicitly here because
they are absent from the upstream public Dockerfile.

`prisma_brightdata_ca.crt` was extracted without modification from:

```text
luminati/luminati-proxy@sha256:2cddb2cd8f6a93179f554c479377aa76ebcc142f7aa682444a9e4016e4e403cc
/usr/local/share/ca-certificates/prisma_brightdata_ca.crt
```

Its SHA-256 is:

```text
8a9be5bf413836528dd14eaa27c8b9e61e0cc9e379da64a77c0623a37746aba9
```

The bundle contains two public CA certificates and no private key. The renewed
certificate expires July 1, 2030; the older certificate expired August 3, 2025.
Proxy Manager's separate signing CA/key and custom CA support remain part of the
application package. Preserve your existing configuration volume and any custom
`lpm.crt` / `lpm.key` when comparing runtime behavior.

## After building

Use the same arguments, port mappings, and configuration volumes as the original
image. Change only the image name for an initial comparison. For example:

```sh
docker run --rm --platform linux/arm64 \
    luminati-proxy:1.679.135-optimized proxy-manager --version
docker image ls luminati-proxy
```

Before switching a deployment, compare HTTP proxying, HTTPS CONNECT, SSL analysis,
HAR request and response bodies, configuration persistence, and the browser
features you use. Those runtime checks have not been performed by writing these
files or by running `--dry-run` / `--check`.
