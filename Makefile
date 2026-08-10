export TZ := UTC

IMAGE_VERSION ?= $(shell date -u +%Y.%m.%d).0
ROOT := $(shell pwd)
# Build on a native filesystem (see build-image.sh); DrvFs (/mnt/c) breaks perms.
CACHYWSL_WORKDIR ?= /var/tmp/cachywsl
export CACHYWSL_WORKDIR

.PHONY: build test validate unit lint clean

build:
	./scripts/build-image.sh $(IMAGE_VERSION)

test:
	./scripts/test-image.sh

validate:
	./scripts/validate-rootfs.sh $(CACHYWSL_WORKDIR)/build

unit:
	bats tests/

lint:
	shellcheck scripts/*.sh scripts/lib/*.sh rootfs/usr/lib/wsl/first-setup.sh rootfs/usr/lib/wsl/optimize-repos

# Removes only what the build creates inside CACHYWSL_WORKDIR, never the directory itself.
clean:
	rm -rf workdir output "$(CACHYWSL_WORKDIR)/build" "$(CACHYWSL_WORKDIR)/pacman.conf"
