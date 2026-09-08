# The PR-template hook is the only asset --hooks installs that decides
# anything, and no other suite covers hooks.
load 'test_helper'

TEMPLATE_PATH=.claude/skills/create-pr/assets/pull_request_template.md

# The hook reads its headings out of the installed skill, so the skill has to
# be on disk beside it.
install_hook() {
  run install_into --hooks --skills --settings --claude
  [ "$status" -eq 0 ]
  assert_file "$TEST_HOME/.claude/hooks/require_pr_template.sh"
}

run_hook() {
  jq -n --arg command "$1" '{tool_name: "Bash", tool_input: {command: $command}}' |
    "$TEST_HOME/.claude/hooks/require_pr_template.sh"
}

@test "a body carrying the template headings is allowed" {
  install_hook
  assert_file "$TEST_HOME/$TEMPLATE_PATH"
  body=$(cat "$TEST_HOME/$TEMPLATE_PATH")
  for call in 'gh pr create --title x' 'gh pr edit 86'; do
    run run_hook "$call --body '$body'"
    [ "$status" -eq 0 ] || fail "expected the hook to allow: $call"$'\n'"$output"
  done
}

# Reading the expected heading back out of the template keeps the assertion
# from drifting when the template changes.
@test "a body missing the template headings is refused" {
  install_hook
  heading=$(grep -m1 '^#' "$TEST_HOME/$TEMPLATE_PATH")
  for call in 'gh pr create --title x' 'gh pr edit 86'; do
    run run_hook "$call --body 'Implementation Details: rewrote the parser.'"
    [ "$status" -eq 2 ] || fail "expected the hook to refuse: $call"$'\n'"$output"
    assert_contains "$output" "$heading"
    assert_contains "$output" "$TEMPLATE_PATH"
  done
}

@test "a gh call that sets no body is left alone" {
  install_hook
  for call in 'gh pr edit 86 --add-label x' 'gh pr view 86' 'gh pr list' \
    'gh pr create --draft' 'git commit -m "no body here"'; do
    run run_hook "$call"
    [ "$status" -eq 0 ] || fail "expected the hook to allow: $call"$'\n'"$output"
  done
}

@test "Claude settings run the hook ahead of every Bash call" {
  install_hook
  jq -e '
    .hooks.PreToolUse[] | select(.matcher == "Bash")
    | .hooks[] | select(.command | endswith("require_pr_template.sh"))
  ' "$TEST_HOME/.claude/settings.json" >/dev/null
}
