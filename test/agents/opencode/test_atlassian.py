from harness import RuntimeCase, call
from roles import atlassian_tools


class Atlassian(RuntimeCase):
    def test_runtime_catalogs_match_claude_tool_lists(self) -> None:
        for role, methods in atlassian_tools(self.runtime.source).items():
            with self.subTest(role=role):
                plan = self.runtime.plan([])
                self.runtime.prompt(role, plan)
                request = next(
                    item
                    for item in self.runtime.provider.requests[plan]
                    if item.get("tools")
                )
                actual = sorted(
                    tool["function"]["name"]
                    for tool in request["tools"]
                    if tool["function"]["name"].startswith("atlassian_")
                )
                expected = sorted(f"atlassian_{name}" for name in methods)
                self.runtime.save(
                    f"{role}-catalog", {"expected": expected, "actual": actual}
                )
                self.assertEqual(actual, expected)

    def test_every_listed_method_reaches_the_mcp_server(self) -> None:
        for role, methods in atlassian_tools(self.runtime.source).items():
            for method in methods:
                with self.subTest(role=role, method=method):
                    before = len(self.runtime.mcp_calls())
                    tool = f"atlassian_{method}"
                    result = self.runtime.run(role, [call(tool)])
                    self.assert_completed(result, [tool])
                    self.assertEqual(
                        self.runtime.mcp_calls()[before:],
                        [{"server": "atlassian", "tool": method}],
                    )

    def test_unlisted_write_and_unknown_calls_never_reach_the_server(self) -> None:
        for role, methods in atlassian_tools(self.runtime.source).items():
            denied = ["extraCapability"]
            if "editJiraIssue" not in methods:
                denied.append("editJiraIssue")
            if not methods:
                denied.append("getJiraIssue")
            for method in denied:
                with self.subTest(role=role, method=method):
                    before = len(self.runtime.mcp_calls())
                    result = self.runtime.run(role, [call(f"atlassian_{method}")])
                    self.assertEqual(self.runtime.mcp_calls()[before:], [])
                    self.assert_denied(result)
