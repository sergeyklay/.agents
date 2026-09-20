import json

from fixtures.mcp_server import HISTORICAL_TOOLS
from harness import RuntimeCase, call
from roles import FULL_SERVERS, ROLES, WORKERS


class Capabilities(RuntimeCase):
    def test_workers_can_load_a_skill_outside_preload(self) -> None:
        for role in WORKERS:
            with self.subTest(role=role):
                result = self.runtime.run(
                    role, [call("skill", name="auxiliary-fixture")]
                )
                self.assert_completed(result, ["skill"])
                self.assertIn(
                    "AUXILIARY_SKILL_LOADED", result.tools[0]["state"]["output"]
                )

    def test_selected_servers_expose_historical_and_additional_tools(self) -> None:
        for server, roles in FULL_SERVERS.items():
            for role in roles:
                for tool in (HISTORICAL_TOOLS[server], "extraCapability"):
                    with self.subTest(role=role, server=server, tool=tool):
                        before = len(self.runtime.mcp_calls())
                        result = self.runtime.run(role, [call(f"{server}_{tool}")])
                        self.assert_completed(result, [f"{server}_{tool}"])
                        self.assertEqual(
                            self.runtime.mcp_calls()[before:],
                            [{"server": server, "tool": tool}],
                        )

    def test_unselected_servers_are_denied(self) -> None:
        for server, selected in FULL_SERVERS.items():
            for role in set(ROLES) - set(selected):
                with self.subTest(role=role, server=server):
                    before = self.runtime.mcp_calls()
                    self.assert_denied(
                        self.runtime.run(role, [call(f"{server}_extraCapability")])
                    )
                    self.assertEqual(self.runtime.mcp_calls(), before)

    def test_global_mcp_denies_survive_server_selection(self) -> None:
        for server, roles in FULL_SERVERS.items():
            for role in roles:
                with self.subTest(role=role, server=server):
                    before = self.runtime.mcp_calls()
                    self.assert_denied(
                        self.runtime.run(role, [call(f"{server}_globallyBlocked")])
                    )
                    self.assertEqual(self.runtime.mcp_calls(), before)

    def test_workers_resolve_a_definition_through_real_gopls(self) -> None:
        source = self.runtime.project / "main.go"
        for role in WORKERS:
            with self.subTest(role=role):
                result = self.runtime.run(
                    role,
                    [
                        call(
                            "lsp",
                            operation="goToDefinition",
                            filePath=str(source),
                            line=5,
                            character=25,
                        )
                    ],
                )
                self.assert_completed(result, ["lsp"])
                locations = json.loads(result.tools[0]["state"]["output"])
                self.assertEqual(locations[0]["uri"], source.as_uri())
                self.assertEqual(
                    locations[0]["range"]["start"], {"line": 2, "character": 5}
                )
