export TZ := UTC

.PHONY: unit clean

unit:
	bats tests/

clean:
	rm -rf workdir output
