# Makefile - quality gates for .agents.
#
# Run "make" or "make help" to see all targets and configurable variables.
# Requires GNU make >= 3.81.  Recipes are POSIX sh and work on macOS and Linux.

include default.mk

# ── Validation ─────────────────────────────────────────────────────────────────

##@ Validation

.PHONY: validate
validate: ## Validate every tracked Agent Skill
	@tmp=$$(mktemp "$${TMPDIR:-/tmp}/skills.XXXXXX") || exit 1; \
	trap 'rm -f "$$tmp"' 0; \
	git ls-files -- '.agents/skills/*/SKILL.md' > "$$tmp"; \
	if [ ! -s "$$tmp" ]; then \
		printf '$(RED)No tracked Agent Skills found$(RESET)\n' >&2; \
		exit 1; \
	fi; \
	failed=0; \
	while IFS= read -r skill; do \
		printf '$(BOLD)%s$(RESET)\n' "$$skill"; \
		$(UV) run --no-project python $(SKILL_VALIDATOR) \
			--warnings-as-errors "$$(dirname "$$skill")" || failed=1; \
	done < "$$tmp"; \
	exit $$failed

.PHONY: typecheck
typecheck: ## Type-check every tracked Python script with basedpyright
	@scripts=$$(git ls-files -- '*.py'); \
	if [ -z "$$scripts" ]; then \
		printf '$(RED)No tracked Python scripts found$(RESET)\n' >&2; \
		exit 1; \
	fi; \
	$(UVX) basedpyright@$(BASEDPYRIGHT_VERSION) --version; \
	git ls-files -z -- '*.py' | xargs -0 \
		$(UVX) basedpyright@$(BASEDPYRIGHT_VERSION) --stats

# ── Lint ───────────────────────────────────────────────────────────────────────

##@ Lint

.PHONY: lint
lint: ## Ruff check + format check on every tracked Python script
	@scripts=$$(git ls-files -- '*.py'); \
	if [ -z "$$scripts" ]; then exit 0; fi; \
	$(UVX) ruff@$(RUFF_VERSION) --version; \
	git ls-files -z -- '*.py' | xargs -0 \
		$(UVX) ruff@$(RUFF_VERSION) check --output-format=$(RUFF_OUTPUT_FORMAT) -- && \
	git ls-files -z -- '*.py' | xargs -0 \
		$(UVX) ruff@$(RUFF_VERSION) format --check --output-format=$(RUFF_OUTPUT_FORMAT) --

.PHONY: fmt
fmt: ## Rewrite Python formatting with ruff (companion to "make lint")
	@scripts=$$(git ls-files -- '*.py'); \
	if [ -z "$$scripts" ]; then exit 0; fi; \
	git ls-files -z -- '*.py' | xargs -0 $(UVX) ruff@$(RUFF_VERSION) format --

.PHONY: lint-shell
lint-shell: ## Run shellcheck on every tracked shell script
	@scripts=$$(git ls-files -- '*.sh'); \
	if [ -z "$$scripts" ]; then exit 0; fi; \
	printf '%s\n' "$$scripts"; \
	git ls-files -z -- '*.sh' | xargs -0 \
		$(SHELLCHECK) --shell=sh --external-sources --

.PHONY: fmt-shell
fmt-shell: ## Fail if any tracked shell script needs shfmt reformatting
	@scripts=$$(git ls-files -- '*.sh'); \
	if [ -z "$$scripts" ]; then exit 0; fi; \
	$(SHFMT) --version; \
	git ls-files -z -- '*.sh' | xargs -0 $(SHFMT) -d --

# ── Gates ──────────────────────────────────────────────────────────────────────

##@ Gates

.PHONY: check
check: validate typecheck lint lint-shell fmt-shell install-test ## Run every CI gate from ci.yml locally

.PHONY: install-test
install-test: ## Exercise scripts/install.sh against isolated fake homes
	sh scripts/install_test.sh

# ── Utilities ──────────────────────────────────────────────────────────────────

##@ Utilities

.PHONY: help
help: ## Show this help message and exit
ifdef _COLORS_OK
	@printf '\n'
	@printf '$(CYAN)   █████╗  ██████╗ ███████╗███╗   ██╗████████╗███████╗$(RESET)\n'
	@printf '$(CYAN)  ██╔══██╗██╔════╝ ██╔════╝████╗  ██║╚══██╔══╝██╔════╝$(RESET)\n'
	@printf '$(CYAN)  ███████║██║  ███╗█████╗  ██╔██╗ ██║   ██║   ███████╗$(RESET)\n'
	@printf '$(CYAN)  ██╔══██║██║   ██║██╔══╝  ██║╚██╗██║   ██║   ╚════██║$(RESET)\n'
	@printf '$(CYAN)  ██║  ██║╚██████╔╝███████╗██║ ╚████║   ██║   ███████║$(RESET)\n'
	@printf '$(CYAN)  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝$(RESET)\n'
else
	@printf '\n  AGENTS\n'
endif
	@printf '  $(DIM)Canonical agent rules and skills, shipped to every host$(RESET)\n\n'
	@printf '$(BOLD)Usage$(RESET)\n'
	@printf '  make $(CYAN)<target>$(RESET) [$(CYAN)VAR=value$(RESET) ...]\n'
	@awk -v bold='$(BOLD)' -v cmd='$(BOLD)$(YELLOW)' -v reset='$(RESET)' \
		'BEGIN { FS = ":.*##" } \
		/^##@/  { printf "\n%s%s%s\n", bold, substr($$0, 5), reset } \
		/^[a-zA-Z0-9_][a-zA-Z0-9_-]*:.*## / \
		        { printf "  %s%-24s%s %s\n", cmd, $$1, reset, $$2 }' \
		$(MAKEFILE_LIST)
	@printf '\n$(BOLD)Variables$(RESET)\n'
	@printf '  $(CYAN)%-24s$(RESET) %s\n' \
		'RUFF_VERSION'         ' ruff version uvx resolves (default: latest)' \
		'RUFF_OUTPUT_FORMAT'   ' ruff --output-format (github under CI, full locally)' \
		'BASEDPYRIGHT_VERSION' ' basedpyright version uvx resolves (default: 1.39.10)' \
		'UV / UVX'              ' uv wrappers used for every Python tool' \
		'SHELLCHECK'           ' shellcheck binary for lint-shell' \
		'SHFMT'                ' shfmt binary for fmt-shell (asdf shim, see .tool-versions)' \
		'NO_COLOR'             ' Disable color output (https://no-color.org/)'
	@printf '\n'
