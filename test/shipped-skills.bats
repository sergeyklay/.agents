# sync_skills copies .agents/skills wholesale into five host directories, so
# every file tracked under it lands on the machine of everyone who runs the
# installer. Engineering scaffolding belongs in test/, which ships nowhere.
load 'test_helper'

# git ls-files is the shipped surface and it reads the index, so a violating
# file has to be staged before this gate can see it (see AGENTS.md Gotchas).
# :(glob) makes ** span any number of directories, including none.
@test "no test scaffolding ships under .agents/skills" {
  run git -C "$ROOT" ls-files -- \
    ':(glob).agents/skills/**/test_*.py' ':(glob).agents/skills/**/testdata/**'
  [ "$status" -eq 0 ]
  [ -z "$output" ] ||
    fail "test scaffolding ships to five hosts; move it under test/: $output"
}
