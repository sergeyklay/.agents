from harness import RuntimeCase, call
from roles import ORCHESTRATORS, REQUIRED_SKILLS


class Workflow(RuntimeCase):
    def test_required_skills_remain_in_prompt_and_load_before_work(self) -> None:
        for role, skills in REQUIRED_SKILLS.items():
            for skill in skills:
                with self.subTest(role=role, skill=skill):
                    self.assertIn(skill, self.runtime.agents[role]["prompt"])
                    marker = self.runtime.project / f"{role}-{skill}.txt"
                    result = self.runtime.run(
                        role,
                        [
                            call("skill", name=skill),
                            call("write", filePath=str(marker), content="after-skill"),
                        ],
                        "other-fixture",
                    )
                    self.assert_completed(result, ["skill", "write"])
                    self.assertIn(
                        f'<skill_content name="{skill}">',
                        result.tools[0]["state"]["output"],
                    )
                    self.assertEqual(marker.read_text(), "after-skill")

    def test_nested_delegation_preserves_todo_and_worker_capabilities(self) -> None:
        for orchestrator in ORCHESTRATORS:
            with self.subTest(orchestrator=orchestrator):
                marker = self.runtime.project / f"{orchestrator}-delegated"
                worker = self.runtime.plan(
                    [
                        call("skill", name="writing-specs"),
                        call(
                            "bash",
                            command=f"printf delegated > '{marker}'",
                            description="Write delegated marker",
                        ),
                    ]
                )
                manager = self.runtime.plan(
                    [
                        call(
                            "todowrite",
                            todos=[
                                {
                                    "content": "Delegate",
                                    "status": "completed",
                                    "priority": "high",
                                }
                            ],
                        ),
                        call(
                            "task",
                            subagent_type="architect",
                            description="Real worker",
                            prompt=f"PROBE:{worker}",
                        ),
                    ]
                )
                result = self.runtime.run(
                    "build",
                    [
                        call(
                            "task",
                            subagent_type=orchestrator,
                            description="Real manager",
                            prompt=f"PROBE:{manager}",
                        )
                    ],
                )
                self.assert_completed(result, ["task"])
                children = self.runtime.api(f"/session/{result.session}/children")
                self.assertEqual(len(children), 1)
                grandchildren = self.runtime.api(
                    f"/session/{children[0]['id']}/children"
                )
                self.assertEqual(len(grandchildren), 1)
                self.assertEqual(marker.read_text(), "delegated")
                self.runtime.save(
                    f"{orchestrator}-descendants",
                    {"children": children, "grandchildren": grandchildren},
                )

    def test_depth_ceiling_still_blocks_a_third_level(self) -> None:
        unreachable = self.runtime.plan([])
        grandchild = self.runtime.plan(
            [
                call(
                    "task",
                    subagent_type="architect",
                    description="Too deep",
                    prompt=f"PROBE:{unreachable}",
                )
            ]
        )
        child = self.runtime.plan(
            [
                call(
                    "task",
                    subagent_type="sleuth",
                    description="Second level",
                    prompt=f"PROBE:{grandchild}",
                )
            ]
        )
        result = self.runtime.run(
            "build",
            [
                call(
                    "task",
                    subagent_type="composer",
                    description="First level",
                    prompt=f"PROBE:{child}",
                )
            ],
        )
        children = self.runtime.api(f"/session/{result.session}/children")
        grandchildren = self.runtime.api(f"/session/{children[0]['id']}/children")
        messages = self.runtime.api(f"/session/{grandchildren[0]['id']}/message")
        self.runtime.save("depth-limit-grandchild", messages)
        tools = [
            part
            for message in messages
            for part in message["parts"]
            if part["type"] == "tool"
        ]
        self.assertEqual(tools[0]["state"]["status"], "error")
        self.assertIn("Subagent depth limit reached (2)", tools[0]["state"]["error"])
        self.assertEqual(self.runtime.provider.requests[unreachable], [])
