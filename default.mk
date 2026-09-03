# default.mk - project variables, tool detection, and output formatting.
#
# Included by the root Makefile.  Every variable is defined with ?= so any of
# them can be overridden on the command line or in the environment:
#
#   make typecheck BASEDPYRIGHT_VERSION=1.40.0
#   make lint-shell SHELLCHECK=/opt/homebrew/bin/shellcheck
#
# Requires GNU make >= 3.81 (the version shipped with macOS Xcode CLT).

# The directory that contains this file, which is also the repository root.
TOP := $(dir $(lastword $(MAKEFILE_LIST)))

.DEFAULT_GOAL := help

# ── Toolchain ──────────────────────────────────────────────────────────────────
#
# The CI workflow runs every Python check through uv/uvx so no local Python
# environment has to be set up first; the Makefile uses the same commands to
# guarantee that a local "make check" and the CI pipeline behave identically.

UV         ?= uv
UVX        ?= uvx
SHELLCHECK ?= shellcheck
SHFMT      ?= shfmt

RUFF_VERSION         ?= latest
BASEDPYRIGHT_VERSION ?= 1.39.10

# ruff's --output-format: "github" emits GitHub Actions inline annotations and
# is selected automatically when the CI variable is set (most CI/CD platforms
# export it); "full" keeps locally readable output.
RUFF_OUTPUT_FORMAT ?= $(if $(CI),github,full)

# ── Agent Skill validation ─────────────────────────────────────────────────────

SKILL_VALIDATOR := .agents/skills/make-skill/scripts/validate_skill.py

# ── Color / formatting ─────────────────────────────────────────────────────────
#
# Honors three opt-out signals:
#   NO_COLOR  - set to any value to disable (https://no-color.org/)
#   CI        - set to any value (most CI/CD platforms set this automatically)
#   TERM=dumb - indicates a terminal with no escape-sequence support
#
# When all conditions are satisfied, colors are enabled by embedding the real
# ESC byte (0x1B) once via printf rather than using \033 literals throughout -
# this keeps every downstream variable self-contained and portable across both
# GNU awk and BSD awk (macOS).
#
# _COLORS_OK is the single gate: downstream code checks only this variable.

_COLORS_OK :=
ifeq  ($(NO_COLOR),)
ifeq  ($(CI),)
ifneq ($(TERM),)
ifneq ($(TERM),dumb)
  _COLORS_OK := yes
endif
endif
endif
endif

ifeq ($(_COLORS_OK),yes)
  _ESC   := $(shell printf '\033')
  BOLD   := $(_ESC)[1m
  DIM    := $(_ESC)[2m
  RED    := $(_ESC)[31m
  GREEN  := $(_ESC)[32m
  YELLOW := $(_ESC)[33m
  CYAN   := $(_ESC)[36m
  RESET  := $(_ESC)[0m
else
  _ESC   :=
  BOLD   :=
  DIM    :=
  RED    :=
  GREEN  :=
  YELLOW :=
  CYAN   :=
  RESET  :=
endif
