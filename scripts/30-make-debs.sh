#!/bin/bash
# Assemble the staged trees into .deb packages.
#
# Deliberately does NOT use debhelper/dh-golang. Ubuntu's own libpod packaging
# depends on ~80 vendored `golang-github-*` source packages that exist only in
# Debian/noble, because Debian requires offline builds from packaged sources.
# We build from upstream go.mod instead, so a plain `dpkg-deb --build` over a
# staged tree is simpler and has no such dependency.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${WORKDIR:-/build}"
export PODMAN_VERSION="${PODMAN_VERSION:-4.9.3}"
export CONMON_VERSION="${CONMON_VERSION:-2.2.1}"
DEB_REVISION="${DEB_REVISION:-1}"
SUITE="${SUITE:-jammy}"
OUTDIR="${OUTDIR:-${WORKDIR}/out}"
MAINTAINER="${MAINTAINER:-HPC Infrastructure <root@localhost>}"

CONMON_STAGE="${CONMON_STAGE:-${WORKDIR}/stage-conmon}"
PODMAN_STAGE="${PODMAN_STAGE:-${WORKDIR}/stage-podman}"
DOCKER_STAGE="${DOCKER_STAGE:-${WORKDIR}/stage-podman-docker}"

# Debian version strings. The `~jammy1` suffix sorts below the bare revision,
# which is the convention for backports and keeps us below any future official
# jammy package of the same upstream version.
podman_debver="${PODMAN_VERSION}-${DEB_REVISION}~${SUITE}1"
conmon_debver="${CONMON_VERSION}-${DEB_REVISION}~${SUITE}1"

mkdir -p "$OUTDIR"
rm -f "$OUTDIR"/*.deb

# ---------------------------------------------------------------- helpers ----

render_control() {
    # render_control <control.in> <dest> <debver> <upstreamver>
    local src="$1" dest="$2" debver="$3" upstream="$4"
    sed -e "s|@VERSION@|${debver}|g" \
        -e "s|@UPSTREAM_VERSION@|${upstream}|g" \
        -e "s|@MAINTAINER@|${MAINTAINER}|g" \
        "$src" >"$dest"
    # control files must be world-readable, not executable
    chmod 0644 "$dest"
}

# Every file we install under /etc must be declared as a conffile, otherwise apt
# will happily overwrite local edits (and, worse, dpkg will not prompt).
write_conffiles() {
    local stage="$1"
    local conffiles="$stage/DEBIAN/conffiles"
    : >"$conffiles"
    if [ -d "$stage/etc" ]; then
        (cd "$stage" && find etc -type f | sed 's|^|/|' | sort) >>"$conffiles"
    fi
    chmod 0644 "$conffiles"
}

build_deb() {
    # build_deb <stage> <package> <debver>
    local stage="$1" pkg="$2" debver="$3"
    local out="${OUTDIR}/${pkg}_${debver}_amd64.deb"
    dpkg-deb --build --root-owner-group "$stage" "$out" >/dev/null
    echo "  built $(basename "$out")"
}

# --------------------------------------------------------------- conmon -----

echo "== packaging conmon ${CONMON_VERSION} =="
rm -rf "$CONMON_STAGE/DEBIAN"
mkdir -p "$CONMON_STAGE/DEBIAN"
render_control "$HERE/packaging/conmon/control.in" \
    "$CONMON_STAGE/DEBIAN/control" "$conmon_debver" "$CONMON_VERSION"
write_conffiles "$CONMON_STAGE"
build_deb "$CONMON_STAGE" conmon "$conmon_debver"

# --------------------------------------------------------------- podman -----

echo "== packaging podman ${PODMAN_VERSION} =="

# Vendor the container configs. jammy's golang-github-containers-common is
# 0.44.4 (podman 3.x era) and cannot be depended on for podman 4.9.3, which
# wants >= 0.57.4.
install -d -m 0755 "$PODMAN_STAGE/usr/share/containers"
install -m 0644 "$HERE/packaging/configs/containers.conf" \
    "$PODMAN_STAGE/usr/share/containers/containers.conf"
install -m 0644 "$HERE/packaging/configs/registries.conf" \
    "$PODMAN_STAGE/usr/share/containers/registries.conf"
install -m 0644 "$HERE/packaging/configs/policy.json" \
    "$PODMAN_STAGE/usr/share/containers/policy.json"

rm -rf "$PODMAN_STAGE/DEBIAN"
mkdir -p "$PODMAN_STAGE/DEBIAN"
render_control "$HERE/packaging/podman/control.in" \
    "$PODMAN_STAGE/DEBIAN/control" "$podman_debver" "$PODMAN_VERSION"
write_conffiles "$PODMAN_STAGE"
build_deb "$PODMAN_STAGE" podman "$podman_debver"

# --------------------------------------------------------- podman-docker ----

if [ -d "$DOCKER_STAGE" ] && [ -n "$(find "$DOCKER_STAGE" -type f -o -type l | head -1)" ]; then
    echo "== packaging podman-docker =="
    rm -rf "$DOCKER_STAGE/DEBIAN"
    mkdir -p "$DOCKER_STAGE/DEBIAN"
    render_control "$HERE/packaging/podman-docker/control.in" \
        "$DOCKER_STAGE/DEBIAN/control" "$podman_debver" "$PODMAN_VERSION"
    write_conffiles "$DOCKER_STAGE"
    build_deb "$DOCKER_STAGE" podman-docker "$podman_debver"
else
    echo "!! no podman-docker staging tree found at ${DOCKER_STAGE}, skipping"
fi

# ------------------------------------------------------------ verify --------

echo
echo "== built packages =="
ls -la "$OUTDIR"/*.deb

echo
echo "== verifying each deb is well-formed and self-consistent =="
for deb in "$OUTDIR"/*.deb; do
    echo "-- $(basename "$deb")"
    dpkg-deb --info "$deb" | sed -n '1,12p' | sed 's|^|   |'
done

# Fail loudly if the podman package links a library we forgot to depend on.
echo
echo "== checking podman's shared-library dependencies are declared =="
podman_deps="$(dpkg-deb -f "$OUTDIR/podman_${podman_debver}_amd64.deb" Depends | tr ',' '\n' | sed 's/^ *//;s/ *(.*//')"
needed="$(objdump -p "$PODMAN_STAGE/usr/bin/podman" | awk '/NEEDED/{print $2}' | sort)"
echo "   linked:  $(echo "$needed" | tr '\n' ' ')"
missing=0
for lib in $needed; do
    case "$lib" in
        libc.so.6|libpthread.so.0|librt.so.1|libdl.so.2|libm.so.6|libresolv.so.2) continue ;;
    esac
    # map soname -> debian package name via the build container's dpkg
    owner="$(dpkg -S "*/${lib}" 2>/dev/null | cut -d: -f1 | head -1)"
    if [ -n "$owner" ] && ! echo "$podman_deps" | grep -qxF "$owner"; then
        echo "   MISSING DEPENDS: ${lib} is provided by '${owner}'" >&2
        missing=1
    fi
done
if [ "$missing" -ne 0 ]; then
    echo "error: podman links libraries absent from its Depends field" >&2
    exit 1
fi
echo "   ok: all linked libraries are covered by Depends"

echo
echo "Packages are in ${OUTDIR}"
