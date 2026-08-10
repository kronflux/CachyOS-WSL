export TZ := UTC

.PHONY: unit

unit:
	bats tests/
