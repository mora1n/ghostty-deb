# Ghostty for Debian 13

This repository builds unofficial Debian 13 packages for [Ghostty](https://ghostty.org/)
and publishes them as free GitHub Release assets.

The package pipeline follows Ghostty's downstream packaging guidance: it uses
the versioned upstream source tarball, verifies its Minisign signature, reads
the required Zig version from that source, and downloads the matching compiler
from ziglang.org with SHA-256 verification. GTK, fontconfig, and gtk4-layer-shell
use Debian's system libraries; other dependencies use Zig's source builds.

## Supported targets

- Debian 13 (Trixie)
- `amd64`
- `arm64`

The packages are built on native GitHub-hosted runners for both architectures.
Ubuntu, Debian 12, Debian unstable, and other distributions are outside the
supported target for the first release.

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
sha256sum -c SHA256SUMS
```

## Automation

The upstream checker runs hourly and compares stable `vX.Y.Z` tags in
`ghostty-org/ghostty` with the releases already published here. A new stable
version starts one build for each architecture. The release is created only
after both packages pass metadata, dependency, lint, and clean Debian 13
installation checks.

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
