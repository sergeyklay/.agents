TOP := $(dir $(lastword $(MAKEFILE_LIST)))

.DEFAULT_GOAL := help

UV         ?= uv
UVX        ?= uvx
SHELLCHECK ?= shellcheck
SHFMT      ?= shfmt
BATS       ?= bats

RUFF_VERSION         ?= latest
BASEDPYRIGHT_VERSION ?= 1.39.10

GEMINI_MODEL ?= gemini-3.5-flash-lite
export GEMINI_MODEL

RUFF_OUTPUT_FORMAT ?= $(if $(CI),github,full)

SKILL_VALIDATOR      := .agents/skills/make-skill/scripts/validate_skill.py
SKILL_VALIDATOR_TEST := .agents/skills/make-skill/scripts/test_validate_skill.py

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
