# aurora-custom

Custom Aurora DX NVIDIA image with additional packages and configurations optimized for development.

## Features

This custom image extends `ghcr.io/ublue-os/aurora-dx-nvidia-open:stable` with:

- **RPMFusion repos** (free & nonfree) — for additional multimedia and software packages
- **keyd** — keyboard remapping daemon for custom key bindings
- **Development tools** — btrfs-assistant, gparted, snapper for filesystem management
- **Desktop environment extras** — kwin-x11, plasma-workspace-x11 (X11 session support)
- **Virtualization** — waydroid for Android app support
- **Terminal & utilities** — ptyxis, x11vnc, xpra, xorgxrdp-glamor

## Building

The image is built automatically on every push via GitHub Actions using [BlueBuild](https://github.com/blue-build/cli).

Built images are published to `ghcr.io/zacaj/aurora-custom:latest`.

## Switching to the Custom Image

If you're running Aurora and want to switch to this custom image:

```bash
# Rebase to the custom image
sudo rpm-ostree rebase ostree-remote-registry:ghcr.io/zacaj/aurora-custom:latest

# Reboot to apply changes
sudo systemctl reboot
```

### Reverting to Aurora

If you need to go back to standard Aurora:

```bash
# Rebase back to Aurora
sudo rpm-ostree rebase ostree-remote-registry:ghcr.io/ublue-os/aurora-dx-nvidia-open:stable

# Reboot
sudo systemctl reboot
```

## Customization

Edit `recipes/recipe.yml` to customize the image:

- `repos:` — Add additional package repositories (RPMFusion, COPRs, etc.)
- `install:` — Add or remove packages to install
- `modules:` — Add other BlueBuild module types (script, files, systemd, etc.)

After changes, commit and push to trigger a new build.

## Build Status

See [GitHub Actions](https://github.com/zacaj/aurora-image/actions) for build logs and status.
