# setlist: see README.md
.DEFAULT_GOAL := help
SHELL := /bin/sh

ZSH_FILES := setlist.plugin.zsh bin/add-to-setlist tests/pty.zsh
SH_FILES := install.sh uninstall.sh
WF := macos/Add to setlist.workflow/Contents

.PHONY: help check test install uninstall
help: ## list the targets
	@grep -E '^[a-z-]+:.*## ' Makefile | awk 'BEGIN { FS = ":.*## " } { printf "  %-10s %s\n", $$1, $$2 }'

check: ## parse the zsh files, lint the installers, validate the Quick Action
	@for f in $(ZSH_FILES); do zsh -n "$$f" || exit 1; done
	@shellcheck -s sh $(SH_FILES)
	@if command -v plutil >/dev/null; then plutil -lint -s "$(WF)/Info.plist" "$(WF)/document.wflow"; fi
	@echo "check ok"

test: ## run the bats suite
	@bats tests/

install: ## install the macOS Quick Action; on Linux, print the hotkey command
	@./install.sh

uninstall: ## remove the macOS Quick Action
	@./uninstall.sh
