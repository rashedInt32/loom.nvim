# Run the test suite: clones mini.nvim (test framework) on first use.
.PHONY: test lint

deps/mini.nvim:
	mkdir -p deps
	git clone --depth 1 https://github.com/echasnovski/mini.nvim deps/mini.nvim

test: deps/mini.nvim
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "lua MiniTest.run()"

lint:
	stylua --check .
