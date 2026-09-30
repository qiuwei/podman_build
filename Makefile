# Local convenience wrapper around the same scripts CI runs.
#
# Requires a working container runtime (docker or podman).
IMAGE := podman-build-jammy
CURDIR := $(shell pwd)

.PHONY: help image deb shell clean

help:
	@echo "make deb    - build the .deb packages into ./out (needs docker or podman)"
	@echo "make shell  - drop into the build container with ./out mounted"
	@echo "make clean  - remove ./out"

image:
	docker build -f docker/Dockerfile -t $(IMAGE) .

deb: image
	mkdir -p out
	# --root-owner-group is used by dpkg-deb; the container runs as root anyway.
	docker run --rm -v $(CURDIR)/out:/build/out $(IMAGE)

shell: image
	mkdir -p out
	docker run --rm -it -v $(CURDIR)/out:/build/out $(IMAGE) /bin/bash

clean:
	rm -rf out
