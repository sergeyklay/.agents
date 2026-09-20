from harness import RuntimeCase, call
from roles import ORCHESTRATORS, ROLES, WORKERS


class Permissions(RuntimeCase):
    def test_orchestrators_cannot_execute_shell(self) -> None:
        for role in ORCHESTRATORS:
            with self.subTest(role=role):
                marker = self.runtime.project / f"{role}-shell-marker"
                result = self.runtime.run(
                    role,
                    [
                        call(
                            "bash",
                            command=f"printf actual-shell-executed > '{marker}'",
                            description="Write scratch marker",
                        )
                    ],
                )
                value = marker.read_text() if marker.exists() else "absent"
                print(f"SHELL_CONTROL role={role} marker={value}", flush=True)
                self.assertFalse(marker.exists(), f"{role} executed forbidden bash")
                self.assert_denied(result)

    def test_orchestrators_delegate_skills_and_code_intelligence(self) -> None:
        for role in ORCHESTRATORS:
            for operation in [
                call("skill", name="auxiliary-fixture"),
                call(
                    "lsp",
                    operation="goToDefinition",
                    filePath=str(self.runtime.project / "main.go"),
                    line=5,
                    character=25,
                ),
            ]:
                with self.subTest(role=role, tool=operation["tool"]):
                    self.assert_denied(self.runtime.run(role, [operation]))

    def test_global_skill_deny_is_preserved(self) -> None:
        for role in WORKERS:
            with self.subTest(role=role):
                self.assert_denied(
                    self.runtime.run(role, [call("skill", name="scan-security")])
                )

    def test_global_dotenv_rules_and_ordinary_reads(self) -> None:
        for name, text in (
            (".env", "synthetic-secret"),
            (".env.example", "example"),
            ("ordinary.txt", "ordinary"),
        ):
            file = self.runtime.project / name
            file.write_text(text)
            for role in ROLES:
                with self.subTest(role=role, file=name):
                    result = self.runtime.run(role, [call("read", filePath=str(file))])
                    if name == ".env":
                        self.assert_denied(result)
                        self.assertNotIn(text, str(result.tools))
                    else:
                        self.assert_completed(result, ["read"])
                        self.assertIn(text, result.tools[0]["state"]["output"])

    def test_writes_follow_role_for_both_model_toolsets(self) -> None:
        for role in ROLES:
            for tool, model in (
                ("apply_patch", "gpt-fixture"),
                ("write", "other-fixture"),
            ):
                with self.subTest(role=role, tool=tool):
                    target = self.runtime.project / f"{role}-{tool}.txt"
                    operation = (
                        call("write", filePath=str(target), content="authorized\n")
                        if tool == "write"
                        else call(
                            "apply_patch",
                            patchText=f"*** Begin Patch\n*** Add File: {target}\n+authorized\n*** End Patch",
                        )
                    )
                    result = self.runtime.run(role, [operation], model)
                    if role in ORCHESTRATORS:
                        self.assert_denied(result)
                        self.assertFalse(target.exists())
                    else:
                        self.assert_completed(result, [tool])
                        self.assertEqual(target.read_text(), "authorized\n")

    def test_code_workers_keep_shell_access(self) -> None:
        for role in WORKERS:
            if role == "arch-review":
                continue
            with self.subTest(role=role):
                result = self.runtime.run(
                    role,
                    [
                        call(
                            "bash",
                            command="printf shell-allowed",
                            description="Read safe marker",
                        )
                    ],
                )
                self.assert_completed(result, ["bash"])
                self.assertIn("shell-allowed", result.tools[0]["state"]["output"])
