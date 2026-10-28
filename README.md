# Ghostty for Debian

This repository builds unofficial Debian packages for [Ghostty](https://ghostty.org/)
and publishes them as free GitHub Release assets.

Like `dariogriffo/ghostty-debian`, the package pipeline builds from the official
Ghostty GitHub release tag. It requires GitHub's signature verification to pass
for that tag, downloads source at the exact referenced commit, and records the
tag object, commit, and archive SHA-256 in the build metadata. Unsigned or
unverified tags fail the build.

The pipeline reads the required Zig version from the source and downloads the
matching compiler from ziglang.org with SHA-256 verification. GTK, fontconfig,
gtk4-layer-shell, FreeType, libpng, and zlib use Debian's system libraries;
other dependencies use Zig's source builds. Blueprint 0.20.4 is installed into
the temporary build directory from its pinned GNOME source commit with SHA-256
verification. Debian 13's packaged compiler is too old for Ghostty 1.4's Git source.
GitHub's automatic `GITHUB_TOKEN` supplies API access; no additional repository
secrets or external APT credentials are needed.

## Supported targets

| Debian suite | Branch | Architectures |
| --- | --- | --- |
| 13 (trixie) | stable | amd64, arm64 |
| forky | testing | amd64, arm64 |
| sid | unstable | amd64, arm64 |

Each architecture is built once on Debian 13 using a native GitHub-hosted runner.
The same package must pass installation checks in clean containers for all three
suites before publication. The build baseline is not an operating-system lock.

Debian 12 (bookworm) is not supported: its official repositories provide glibc
2.36 and GTK 4.8, while the current amd64 package requires glibc >= 2.38 and
GTK >= 4.15.4. Ubuntu and other distributions have not been verified.

## Install from a release

Open the [Releases](https://github.com/mora1n/ghostty-deb/releases) page and
download the package matching your architecture:

```sh
sudo apt install ./ghostty_<version>-1_amd64.deb
```

For ARM64, replace `amd64` with `arm64`. `apt` resolves the Debian runtime
dependencies after downloading the local package.

Verify the downloaded package before installation:

```sh
sha256sum --ignore-missing -c SHA256SUMS
```

## Automation

The upstream checker runs hourly and compares stable `vX.Y.Z` tags in
`ghostty-org/ghostty` with the releases already published here. A new stable
version starts one build for each architecture. The release is created only
after both packages pass metadata, dependency, lint, and clean installation
checks on trixie, forky, and sid.

The `Verify published Debian packages` workflow can also check an existing
release. It downloads the matching package and `SHA256SUMS` directly from the
release, checks its checksum and metadata, installs it, runs `ghostty --version`,
checks dynamic dependencies, and validates the desktop file on all six
suite/architecture combinations. It does not create artifacts or caches.

Each release uses the matching `vX.Y.Z` Git tag, pointing to the packaging
commit used by that workflow. The workflow creates the tag before publishing
and verifies that it exists. Rebuilding an existing release replaces its assets
without moving its tag.

GitHub Actions artifacts are temporary handoff files. This repository does not
use Actions caches, does not create a GitHub Gist, and deletes the current run's
artifacts after the workflow finishes. Release assets remain available for
download.

## Project boundary

This is an unofficial downstream packaging project. Ghostty source code,
branding, and licensing remain owned by the Ghostty project. Issues about
Ghostty itself belong in the upstream repository.
