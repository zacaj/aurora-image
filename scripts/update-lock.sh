#!/usr/bin/env bash
# Regenerate packages.lock from the upstream Aurora base image.
# Run this to approve new packages Aurora has added, then commit the result.
#
# Each line in packages.lock is annotated with:
#   - a dash prefix indicating dependency depth (top-level packages have no prefix)
#   - top-level packages get a trailing  # summary (size)  annotation
#   - dependency packages get a trailing  [parent1, parent2]  listing which
#     top-level packages require them (or [all] if more than half do)
#
# Pulls the upstream image if possible; falls back to reading from the live
# running system (minus layered packages) if disk space is insufficient.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="ghcr.io/ublue-os/aurora-dx-nvidia-open:stable"

NEW=$(comm -23 \
        <(podman run --rm "$IMAGE" \
            rpm -qa --queryformat '%{NAME}\n' | LC_ALL=C sort -u) \
        <(sed 's/^-*//; s/  [#[].*$//' packages.lock | LC_ALL=C sort))

# Python script that builds the RPM dependency graph and emits annotated output.
# Optional env var EXCLUDE_PKGS: newline-separated package names to remove from
# the analysis (used by the fallback path to strip rpm-ostree layered packages).
ANALYZE_PY=$(cat <<'PYEOF'
import subprocess, os
from collections import defaultdict, deque

def run(*cmd):
    return subprocess.run(list(cmd), capture_output=True, text=True).stdout

def parse_pkg_array(output):
    """Parse 'PKG:<name>\n<item>\n<item>\n...' blocks into a dict."""
    result = defaultdict(list)
    current = None
    for line in output.splitlines():
        if line.startswith('PKG:'):
            current = line[4:]
        elif current and line:
            result[current].append(line)
    return result

all_pkgs = set(run('rpm', '-qa', '--qf', '%{NAME}\n').strip().splitlines())
all_pkgs.discard('')

exclude = set(os.environ.get('EXCLUDE_PKGS', '').splitlines())
exclude.discard('')
all_pkgs -= exclude

# capability -> first package that provides it
provides_map = {}
for pkg, caps in parse_pkg_array(
        run('rpm', '-qa', '--qf', 'PKG:%{NAME}\n[%{PROVIDENAME}\n]')).items():
    for cap in caps:
        provides_map.setdefault(cap, pkg)

# forward[pkg]  = packages pkg directly depends on
# reverse[pkg]  = packages that directly depend on pkg
forward = defaultdict(set)
reverse = defaultdict(set)
for pkg, caps in parse_pkg_array(
        run('rpm', '-qa', '--qf', 'PKG:%{NAME}\n[%{REQUIRENAME}\n]')).items():
    if pkg not in all_pkgs:
        continue
    for cap in caps:
        dep = provides_map.get(cap)
        if dep and dep != pkg and dep in all_pkgs:
            forward[pkg].add(dep)
            reverse[dep].add(pkg)

# Top-level = installed packages that nothing else depends on
top_level = sorted(p for p in all_pkgs if not reverse[p])
n_top = len(top_level)

# BFS from top-level: assign minimum depth, accumulate which top-level
# packages can reach each node transitively.
depth = {}
parents = defaultdict(set)
queue = deque()
for pkg in top_level:
    depth[pkg] = 0
    parents[pkg].add(pkg)
    queue.append(pkg)

while queue:
    pkg = queue.popleft()
    for dep in forward[pkg]:
        if dep not in depth:
            depth[dep] = depth[pkg] + 1
            queue.append(dep)
        parents[dep] |= parents[pkg]

# Orphans (circular deps, rpmlib virtuals, etc.) land at depth 0
for pkg in all_pkgs:
    if pkg not in depth:
        depth[pkg] = 0

# Summary and installed size for top-level packages
def fmt_size(n):
    try:
        b = int(n)
    except (ValueError, TypeError):
        return '?'
    if b >= 1_000_000:
        return f'{b / 1_000_000:.1f} MB'
    if b >= 1_000:
        return f'{b // 1_000} KB'
    return f'{b} B'

pkg_info = {}
for line in run('rpm', '-qa', '--qf', '%{NAME}\t%{SUMMARY}\t%{SIZE}\n').splitlines():
    parts = line.split('\t', 2)
    if len(parts) == 3:
        pkg_info[parts[0]] = (parts[1], fmt_size(parts[2]))

lines = []
for pkg in sorted(all_pkgs):
    d = depth[pkg]
    if d == 0:
        summary, size = pkg_info.get(pkg, ('', ''))
        meta = f'  # {summary} ({size})' if summary else ''
        lines.append(pkg + meta)
    else:
        pkg_parents = sorted(parents[pkg])
        comment = '[all]' if len(pkg_parents) > n_top // 2 \
                  else '[' + ', '.join(pkg_parents) + ']'
        lines.append('-' * d + pkg + '  ' + comment)

print('\n'.join(lines))
PYEOF
)

if podman pull "$IMAGE" 2>/dev/null; then
    echo "Generating packages.lock from pulled image ..."
    echo "$ANALYZE_PY" | podman run --rm -i "$IMAGE" python3 - > "$REPO_ROOT/packages.lock"
    podman inspect "$IMAGE" --format '{{ index .Labels "org.opencontainers.image.version" }}' \
        > "$REPO_ROOT/upstream-version"
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
    EXCLUDE_PKGS="$LAYERED" python3 - <<< "$ANALYZE_PY" > "$REPO_ROOT/packages.lock"
fi

echo "Done ($(wc -l < "$REPO_ROOT/packages.lock") packages). Review the diff, then commit to approve:"
# Strip trailing annotations (# summary or [parents]) to show only package name changes
# Create a stripped version and diff against it
STRIPPED=$(mktemp)
trap "rm -f '$STRIPPED'" EXIT
sed -E 's/  # .*$//; s/  \[.*\]$//' "$REPO_ROOT/packages.lock" > "$STRIPPED"
# Check if stripped versions differ; only show diff if they do
if ! diff -q "$STRIPPED" "$REPO_ROOT/packages.lock" > /dev/null 2>&1; then
  diff -u "$STRIPPED" "$REPO_ROOT/packages.lock" | grep -E '^[-+]' | \
    sed 's/^[-+]/[[-+]/'

    echo "NEW: $NEW"
fi
