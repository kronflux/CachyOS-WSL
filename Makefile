export TZ := UTC

IMAGE_VERSION ?= $(shell date -u +%Y.%m.%d).0
ROOT := $(shell pwd)
# Build on a native filesystem (see build-image.sh); DrvFs (/mnt/c) breaks perms.
CACHYWSL_WORKDIR ?= /var/tmp/cachywsl
export CACHYWSL_WORKDIR

.PHONY: build unit lint clean

build:
	./scripts/build-image.sh $(IMAGE_VERSION)

unit:
	bats tests/

lint:
	shellcheck scripts/*.sh scripts/lib/*.sh rootfs/usr/lib/wsl/oobe.sh

clean:
	rm -rf workdir output "$(CACHYWSL_WORKDIR)"
