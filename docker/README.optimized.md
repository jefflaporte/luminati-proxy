# Optimized Docker image

`Dockerfile.optimized` is an alternate packaging of the published Proxy Manager
npm package. The original Dockerfile and application source are unchanged.
Like the original Dockerfile, it does **not** build the local application source.

The build supports `linux/amd64` and `linux/arm64`. Both retain a native browser,
the web UI/HAR viewer, SSL analysis, all four CLI aliases, root user, and the
upstream default command (`luminati --help`).

| Architecture | Browser |
| --- | --- |
| `amd64` | Puppeteer's pinned Chrome and Chrome Headless Shell downloads, as before. |
| `arm64` | Debian's native Chromium and Chromium Headless Shell packages. |

Both browser variants are retained for compatibility. Whether the separate
Headless Shell can be omitted has not been assessed.

The pinned Puppeteer version maps Linux ARM64 browser downloads to AMD64 binaries.
ARM64 therefore skips those downloads and sets `PUPPETEER_EXECUTABLE_PATH` to
`/usr/bin/chromium`. This uses Puppeteer's supported system-browser configuration
without modifying application code. Debian's browser version can differ from
Puppeteer's pinned Chrome, so ARM64 browser automation compatibility needs runtime
validation. SSL analysis/HAR capture is implemented separately in Node.

## Build

From the repository root, with Docker and Buildx installed:

```sh
./scripts/build-image-optimized.sh arm64 --dry-run
./scripts/build-image-optimized.sh arm64 --check
./scripts/build-image-optimized.sh arm64

# Or build the existing AMD64 variant:
./scripts/build-image-optimized.sh amd64
```

The architecture argument is required and selects `--platform linux/amd64` or
`--platform linux/arm64`. Both use the default tag
`luminati-proxy:1.679.135-optimized` for this checkout. Separate local builds do
not automatically combine the architectures under a multi-platform manifest.
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

Top-level versions are pinned; the upstream npm package has no committed lockfile
here, so transitive npm dependencies and Debian packages can still change.

## Size changes

Reported local image sizes for Proxy Manager 1.679.135:

| Image | Local size | Reduction from the published image |
| --- | --- | --- |
| Published upstream, AMD64 | 4.81 GB | — |
| Optimized, AMD64 | 1.78 GB | About 63% |
| Optimized, ARM64 | 1.96 GB | About 59% |

These figures describe local image storage; registry download sizes differ.

- A full Node builder compiles native dependencies, while the final image uses
  `node:24.13.0-bookworm-slim` and browser/runtime libraries.
- The application is installed once with production dependencies. Compilers,
  Node build headers, the builder's npm cache, and its npm upgrade stay out of
  the final image.
- AMD64 retains both Puppeteer browser downloads in `/opt/puppeteer`, outside the
  `/root` directory used by existing configuration volumes. ARM64 installs its
  two native Chromium packages in the runtime stage instead.
- APT metadata is removed in the same layer that installs the runtime packages,
  and recommended packages are not installed.
- The extra Google Chrome `.deb` download/install/delete steps are omitted.
  The inspected published image had no installed `google-chrome-stable` package;
  its browser payload came from the two Puppeteer downloads retained here.

The build checks for bundled UI assets, the selected Puppeteer executable, and
unresolved shared libraries in Chrome and native addons. Runtime compatibility
still needs validation after a real build.

## Existing TLS settings

This first packaging change preserves the inspected published image's additional
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
