.PHONY: build check dmg install parity run source-size

build:
	./scripts/build-app.sh

check:
	./scripts/check-source-size.sh
	swift test
	node --test ProductCorpus/tests/scenarios.test.mjs

source-size:
	./scripts/check-source-size.sh

dmg:
	./scripts/build-dmg.sh

install:
	./scripts/install-local.sh

parity:
	./scripts/run-parity.sh

run:
	./scripts/build-app.sh
	open -n dist/Natter.app
