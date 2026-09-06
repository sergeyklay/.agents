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
BATS       ?= bats

RUFF_VERSION         ?= latest
BASEDPYRIGHT_VERSION ?= 1.39.10

# The model test/gemini-policy.bats calls when a credential is available.  The
# Gemini CLI does not validate a model identifier locally - only the API does,
# and only for a request that carries a valid key - so a pinned identifier rots
# silently until something calls it.  What decides this pin is therefore how
# long it survives, not its price: the canary sends one word, and every
# Flash-Lite is "Free of charge" on the free tier.
#
# Two Google surfaces disagree about the 2.5 family.  Cloud's lifecycle table
# retires gemini-2.5-pro, -flash and -flash-lite on October 20, 2026, while the
# Developer API still reports "No shutdown date announced" for them; the two
# have agreed exactly wherever both published a date.  This pin sidesteps the
# dispute.  gemini-3.5-flash-lite is stable, released July 21, 2026, carries no
# announced shutdown on the Developer API surface, and sits in Cloud's "at
# least 12 months after release" table as "July 21, 2027 or later".  It is the
# newest Flash-Lite; 3.6, 3.7 and 3.8 ship none.  It is not the cheapest -
# $0.30/$2.50 per 1M tokens paid, against $0.10/$0.40 for 2.5 Flash-Lite.
#
#   https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/model-versions
#   https://ai.google.dev/gemini-api/docs/deprecations
#
# Not a "-latest" alias: no gemini-flash-lite-latest exists, and such an alias
# is "hot-swapped with every new release", which is not a pin.
#
# Exported because the bats suite reads it from the environment, not from make.
GEMINI_MODEL ?= gemini-3.5-flash-lite
export GEMINI_MODEL

# ruff's --output-format: "github" emits GitHub Actions inline annotations and
# is selected automatically when the CI variable is set (most CI/CD platforms
# export it); "full" keeps locally readable output.
RUFF_OUTPUT_FORMAT ?= $(if $(CI),github,full)

# ── Agent Skill validation ─────────────────────────────────────────────────────

SKILL_VALIDATOR      := .agents/skills/make-skill/scripts/validate_skill.py
SKILL_VALIDATOR_TEST := .agents/skills/make-skill/scripts/test_validate_skill.py

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
