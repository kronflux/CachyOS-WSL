export TZ := UTC

TIER ?= v3
IMAGE_VERSION ?= $(shell date -u +%Y.%m.%d).0
ROOT := $(shell pwd)
# Build on a native filesystem (see build-image.sh); DrvFs (/mnt/c) breaks perms.
CACHYWSL_WORKDIR ?= /var/tmp/cachywsl
export CACHYWSL_WORKDIR

.PHONY: build test validate unit lint clean

build:
	./scripts/build-image.sh $(TIER) $(IMAGE_VERSION)

test:
	./scripts/test-image.sh $(TIER)

validate:
	./scripts/validate-rootfs.sh $(CACHYWSL_WORKDIR)/build-$(TIER)

unit:
	bats tests/

lint:
	shellcheck scripts/*.sh scripts/lib/*.sh rootfs/usr/lib/wsl/oobe.sh

clean:
	rm -rf workdir output "$(CACHYWSL_WORKDIR)"
