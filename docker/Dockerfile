# Build environment for the jammy podman packages.
#
# This image is intentionally Ubuntu 22.04 even when CI runs on a newer runner:
# the binaries must link against jammy's glibc (2.35) and jammy's library
# versions, so the build has to happen in a jammy userspace.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Build dependencies first, so editing the scripts below does not invalidate
# the (slow) apt layer.
COPY scripts/00-build-deps.sh /tmp/00-build-deps.sh
RUN chmod +x /tmp/00-build-deps.sh && /tmp/00-build-deps.sh

COPY scripts/ /src/scripts/
COPY packaging/ /src/packaging/
RUN chmod +x /src/scripts/*.sh

# Sources are fetched and built here; mount a host directory at /build/out to
# collect the resulting .debs.
WORKDIR /build

CMD ["/bin/bash", "-c", \
     "/src/scripts/10-build-conmon.sh && /src/scripts/20-build-podman.sh && /src/scripts/30-make-debs.sh"]
