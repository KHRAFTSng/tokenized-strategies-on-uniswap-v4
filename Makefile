SHELL := /bin/bash

.PHONY: bootstrap test coverage build demo-local demo-testnet demo-yield demo-secondary demo-all verify-deps verify-commits export-abis frontend

bootstrap:
	bash scripts/bootstrap.sh

test:
	forge test

coverage:
	forge coverage

build:
	forge build

frontend:
	npm --workspace frontend run build

demo-local:
	bash scripts/demo_local.sh

demo-testnet:
	bash scripts/demo_testnet.sh

demo-yield:
	bash scripts/demo_yield.sh

demo-secondary:
	bash scripts/demo_secondary.sh

demo-all:
	bash scripts/demo_all.sh

verify-deps:
	bash scripts/verify_deps.sh

verify-commits:
	bash scripts/verify_commits.sh 78

export-abis:
	bash scripts/export_abis.sh
