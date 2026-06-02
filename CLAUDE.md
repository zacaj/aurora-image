# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A custom Fedora Silverblue/Aurora container image built with [BlueBuild](https://github.com/blue-build/cli). It extends `ghcr.io/ublue-os/aurora-dx-nvidia-open:stable` with additional packages, vendor RPMs, and shell customizations. The image is published to `ghcr.io/zacaj/aurora-custom:latest` via GitHub Actions on every push to `main`.

## Build

```bash
# Build the image locally (requires bluebuild CLI)
bluebuild build recipes/recipe.yml

# Or use the wrapper script
./build.sh
```

Normally you just push to `main` and CI builds it. Local builds are only needed to test recipe changes before committing.

## Package Lock Workflow

`packages.lock` is an allowlist of all packages present in the upstream Aurora image. CI fails if the upstream image gains new packages not in this file — forcing explicit approval.

```bash
# After upstream Aurora adds packages (or to unblock a failing CI build):
scripts/update-lock.sh
git add packages.lock && git commit -m "approve new upstream packages"
```

The lock file annotates each package with depth (dependency level), size, and which top-level packages require it.

## Architecture

All customization lives in `recipes/recipe.yml` as an ordered list of BlueBuild modules:

1. **`rpm-ostree` module** — Adds repos (RPMFusion, COPR keyd), installs packages, removes packages. This is the main place to add/remove system packages.

2. **`script` modules** — Ordered shell snippets that run during image build:
   - Installs vendor RPMs (RustDesk, RealVNC) pinned to specific versions — update version vars when new releases ship
   - Wraps `nvidia-container-runtime-hook` so the image works on non-NVIDIA hardware
   - Removes konsole5 and sets ptyxis as default terminal via `/etc/xdg/mimeapps.list`
   - Installs Claude Desktop via external install script
   - Removes Aurora branding wallpapers/backgrounds

## Versioning

Images are versioned as `{upstream-version}.{git-commit-count}` — e.g. `44.20260602.1.42`.

The upstream version prefix (`44.20260602.1`) comes from `ghcr.io/ublue-os/aurora-dx-nvidia-open:stable`'s `org.opencontainers.image.version` label. The commit count suffix is monotonically increasing, so `rpm-ostree status` shows a unique, sortable version for every build even when the upstream base doesn't change.

This is stamped into the recipe at CI build time via `yq` before `blue-build/github-action` runs; the recipe on disk is never committed with the version set.

## Key Constraints

- **Atomic OS**: The root filesystem is read-only at runtime. Packages must be baked into the image — users can't `dnf install` after booting.
- **No runtime tests**: There's no test suite. Verify changes by building the image (locally or via CI) and rebasing to it.
- **Vendor RPM versions** are hardcoded in `recipe.yml` (RustDesk `RUSTDESK_VER`, RealVNC `REALVNC_VER`) — update these manually when new versions are released.
- Commented-out `remove:` entries in the rpm-ostree module are intentionally left as documentation of available removals.

## Deploying to the Running System

```bash
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/zacaj/aurora-custom:latest --uninstall rustdesk --uninstall realvnc-vnc-viewer
sudo systemctl reboot
```
