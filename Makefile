# Copyright (c) 2026 MicroCore Tech
# SPDX-License-Identifier: MIT

BATS ?= bats

.PHONY: test
test: ## Run the test suite
	$(BATS) test
