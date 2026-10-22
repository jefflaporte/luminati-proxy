# Optimized Docker image

`Dockerfile.optimized` (Debian) and `Dockerfile.optimized.alpine` (Alpine) are
alternate packaging options for the published Proxy Manager npm package. The
original Dockerfile and application source are unchanged. Like the original
Dockerfile, neither builds the local application source.

The build supports `linux/amd64` and `linux/arm64`. Both retain the web UI/HAR
viewer, SSL analysis, all four CLI aliases, root user, and the upstream default
command (`luminati --help`). A native browser is included by default and can be
omitted with `--no-chrome`.

| Distribution | Runtime | Browser when included |
| --- | --- | --- |
| `debian` (default) | Node Bookworm slim, glibc | Puppeteer's pinned Chrome on AMD64; Debian Chromium on ARM64. |
| `alpine` | Node Alpine, musl | Alpine Chromium on both architectures. |

The Alpine builder installs Python, Make, and G++ to compile native addons such
as `unix-dgram` against musl. It copies no Debian-built addons. The runtime loads
each native addon in a fresh Node process during the build, checking library
dependencies and the Node ABI before browser packages are installed. Isolating
the checks avoids registering legacy addons twice when node-gyp leaves
hard-linked copies at different paths. Compiler tools remain in the builder.
Bash and GNU utilities/process tools are retained for application shell commands,
including certificate generation.

The separate Chrome Headless Shell is omitted on both architectures. The
application's browser action launches full Chrome with `headless: false`; no
application call selects Puppeteer's `headless: 'shell'` mode. Full Chrome can
also run in its normal headless mode.

The pinned Puppeteer version maps Linux ARM64 browser downloads to AMD64 binaries.
Debian ARM64 therefore skips those downloads and uses `/usr/bin/chromium`.
Alpine skips browser downloads on both architectures because Chrome's downloads
target glibc; it uses `/usr/bin/chromium-browser` from Alpine's packages instead.
Both use Puppeteer's supported system-browser configuration without modifying
application code. Distribution browser versions can differ from Puppeteer's
pinned Chrome, so browser automation compatibility needs runtime validation.
SSL analysis/HAR capture is implemented separately in Node.

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
./scripts/build-image-optimized.sh arm64 debian --dry-run
./scripts/build-image-optimized.sh arm64 debian --check
./scripts/build-image-optimized.sh arm64 debian

# Or build the existing AMD64 variant:
./scripts/build-image-optimized.sh amd64 debian

# Omit Chrome and its GUI libraries, retaining SSL analysis and HAR:
./scripts/build-image-optimized.sh arm64 alpine --no-chrome

# Validate that variant without building:
./scripts/build-image-optimized.sh arm64 alpine --no-chrome --check
```

The architecture argument is required and selects `--platform linux/amd64` or
`--platform linux/arm64`. The distribution argument is optional and defaults to
`debian`, so existing commands such as `arm64 --no-chrome` still work. The script
selects the corresponding Dockerfile and its matching Dockerfile-specific ignore
file; only the public CA bundle is copied from the checkout.

Default tags for this checkout keep the distribution and browser variants apart:

| Distribution | Browser included | With `--no-chrome` |
| --- | --- | --- |
| Debian | `luminati-proxy:1.679.135-optimized` | `luminati-proxy:1.679.135-optimized-no-chrome` |
| Alpine | `luminati-proxy:1.679.135-optimized-alpine` | `luminati-proxy:1.679.135-optimized-alpine-no-chrome` |

Architecture is expressed through `--platform`, without an architecture suffix in
the tags. Separate local builds do not automatically combine the architectures
under a multi-platform manifest.
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
    ./scripts/build-image-optimized.sh arm64 alpine
```

Additional Buildx options can be passed after `--`, for example `-- --no-cache`.
Do not pass `--platform` there; the architecture argument controls the platform.
The script defaults to loading the image locally and never pushes by default.
Node and native addons target the selected architecture, including
when Docker uses emulation on a host with a different architecture. On Apple
Silicon, `arm64` runs natively while `amd64` needs emulation.

For direct `docker buildx` use, supply both `--build-arg LPM_VERSION=<version>`
and `--build-arg NODE_VERSION=<version>` and select the platform with
`--platform linux/arm64` or `--platform linux/amd64`. Select the distribution with
`--file Dockerfile.optimized` or `--file Dockerfile.optimized.alpine`. Neither
alternate Dockerfile has application or Node version defaults; the script
supplies them from the existing upstream files.

Both Dockerfiles default to `WITH_CHROME=true`. For a direct browser-free build,
also pass `--build-arg WITH_CHROME=false`. BuildKit skips the browser-only stages
entirely, so their packages do not enter the browser-free image's layers.

Top-level versions are pinned; the upstream npm package has no committed lockfile
here, so transitive npm dependencies and Debian/Alpine packages can still change.

## Size changes

Reported local image sizes for Proxy Manager 1.679.135:

| Image | Local size | Reduction from the published image |
| --- | --- | --- |
| Published upstream, AMD64 | 4.81 GB | — |
| Initial optimized build, AMD64 | 1.78 GB | About 63% |
| Initial optimized build, ARM64 | 1.96 GB | About 59% |
| Current optimized Debian build, ARM64, `--no-chrome` | 666.5 MB | About 86% |
| Current optimized Alpine build, ARM64, `--no-chrome` | 556 MB | About 88% |

These figures describe local image storage; registry download sizes differ.
The initial optimized builds predate the removal of Headless Shell and the legacy
GConf/AppIndicator/GTK2 packages. Current browser-enabled sizes have not yet been
measured. The Alpine browser-free image is about 110.5 MB (16.6%) smaller than
the equivalent Debian image.

- Debian uses a full Node builder and a `node:24.13.0-bookworm-slim` runtime.
  Alpine uses `node:24.13.0-alpine` for both stages, with compiler packages added
  only to the builder.
- The application is installed once with production dependencies. Compilers,
  the node-gyp cache, the builder's npm cache, and its npm upgrade are not copied
  into the final image.
- Debian AMD64 retains only Puppeteer's full Chrome download in `/opt/puppeteer`,
  outside the `/root` directory used by existing configuration volumes. Its separate
  Headless Shell download is disabled. ARM64 installs Chromium without the
  `chromium-headless-shell` package. Alpine uses its native Chromium package on
  both architectures, also without the separate Headless Shell.
- The legacy `gconf-service` and `libappindicator1` packages are omitted, avoiding
  their GConf/GTK2 dependency chain while retaining the GTK3 libraries used by
  current Chrome.
- With `--no-chrome`, browser downloads, Chromium installation, fonts, and the
  browser GUI library stages are all omitted.
- APT metadata is removed in the same layer that installs the runtime packages,
  and recommended packages are not installed. Alpine uses `apk add --no-cache`.
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

The Alpine ARM64 browser-free image has been built and launched locally, passing
the native addon checks during the build. Its runtime package list, system CA
bundle, Node extra CA loading, and OpenSSL configuration were also checked in a
disposable Node Alpine base container. Alpine AMD64 and browser-enabled builds,
plus end-to-end application checks, remain outstanding.

## Existing TLS settings

This packaging preserves the inspected published image's additional
trust bundle and `UnsafeLegacyRenegotiation` OpenSSL setting. Changing those is a
separate compatibility decision. They are configured explicitly here because
they are absent from the upstream public Dockerfile.

Alpine generates CA links with a `ca-cert-` prefix. Its Dockerfile also creates
the existing `/etc/ssl/certs/prisma_brightdata_ca.pem` path explicitly, retaining
the same `NODE_EXTRA_CA_CERTS` value and both certificates.

`update-ca-certificates` can warn that this bundle does not contain exactly one
certificate. [OpenSSL's directory index](https://docs.openssl.org/3.0/man1/openssl-rehash/)
requires one certificate per file, so it skips hash links for this bundle.
Both certificates were verified in the built Alpine image's system CA bundle and
Node's active trust store. Clients configured to use only the hashed CA directory
would need the certificates installed as separate files.

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
