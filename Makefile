NVIM_BIN    ?= nvim
PLENARY     ?= $(HOME)/.local/share/nvim/site/pack/test/start/plenary.nvim
PLENARY_URL  = https://github.com/nvim-lua/plenary.nvim

.PHONY: test deps fmt check-fmt

## Install test dependencies (plenary.nvim) if not already present.
deps:
	@if [ ! -d "$(PLENARY)" ]; then \
		echo "Cloning plenary.nvim → $(PLENARY)"; \
		mkdir -p "$(dir $(PLENARY))"; \
		git clone --depth 1 $(PLENARY_URL) "$(PLENARY)"; \
	else \
		echo "plenary.nvim already present at $(PLENARY)"; \
	fi

## Format all Lua source files in-place using StyLua.
fmt:
	stylua lua/ plugin/ spec/

## Check formatting without modifying files (non-zero exit if changes needed).
check-fmt:
	stylua --check lua/ plugin/ spec/

## Run the full test suite inside a headless Neovim.
test: deps
	$(NVIM_BIN) \
		--headless \
		--noplugin \
		-u spec/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_directory('spec/', { minimal_init = 'spec/minimal_init.lua' })"
