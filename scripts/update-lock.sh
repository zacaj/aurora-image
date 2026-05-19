#!/usr/bin/env bash
# Regenerate packages.lock from the upstream Aurora base image.
# Run this to approve new packages Aurora has added, then commit the result.
#
# Pulls the upstream image if possible; falls back to reading from the live
# running system (minus layered packages) if disk space is insufficient.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="ghcr.io/ublue-os/aurora-dx-nvidia-open:stable"

if podman pull "$IMAGE" 2>/dev/null; then
    echo "Generating packages.lock from pulled image ..."
    podman run --rm "$IMAGE" rpm -qa --queryformat '%{NAME}\n' | sort > "$REPO_ROOT/packages.lock"
else
    echo "Could not pull image (disk space?). Falling back to live system minus layered packages ..."
    LAYERED=$(rpm-ostree status --json | python3 -c "
import sys, json, re
d = json.load(sys.stdin)['deployments'][0]
pkgs = set()
for field in ('packages', 'requested-packages', 'requested-local-packages'):
    for p in d.get(field, []):
        pkgs.add(re.sub(r'-\d.*', '', p))
print('\n'.join(sorted(pkgs)))
")
    comm -23 \
        <(rpm -qa --queryformat '%{NAME}\n' | sort) \
        <(echo "$LAYERED" | sort) \
        > "$REPO_ROOT/packages.lock"
fi

echo "Done ($(wc -l < "$REPO_ROOT/packages.lock") packages). Review the diff, then commit to approve:"
git -C "$REPO_ROOT" diff packages.lock
