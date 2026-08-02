.PHONY: build check dmg install parity run

build:
	./scripts/build-app.sh

check:
	swift test
	node --test ProductCorpus/tests/scenarios.test.mjs

dmg:
	./scripts/build-dmg.sh

install:
	./scripts/install-local.sh

parity:
	./scripts/run-parity.sh

run:
	./scripts/build-app.sh
	open -n dist/Natter.app
