import json
import time
from concurrent.futures import ThreadPoolExecutor

from harness import Json, RuntimeCase, call


class GlobalGuards(RuntimeCase):
    def test_external_directory_still_requires_permission(self) -> None:
        fixture = self.runtime.home / "external.txt"
        fixture.write_text("external-sentinel")
        with ThreadPoolExecutor(max_workers=1) as executor:
            pending = executor.submit(
                self.runtime.run, "composer", [call("read", filePath=str(fixture))]
            )
            requests: list[Json] = []
            deadline = time.monotonic() + 15
            while not pending.done() and time.monotonic() < deadline:
                requests = self.runtime.api("/permission")
                if requests:
                    break
                time.sleep(0.1)
            for request in requests:
                self.runtime.api(
                    f"/permission/{request['id']}/reply", {"reply": "reject"}
                )
            result = pending.result(timeout=20)
        self.runtime.save("external-directory-requests", requests)
        self.assertEqual(
            [request["permission"] for request in requests], ["external_directory"]
        )
        self.assertEqual(result.tools[0]["state"]["status"], "error")
        self.assertIn("rejected permission", result.tools[0]["state"]["error"])

    def test_doom_loop_still_terminates_repeated_calls(self) -> None:
        fixture = self.runtime.project / "repeat.txt"
        fixture.write_text("ordinary")
        plan = self.runtime.plan([])
        self.runtime.provider.plan(
            plan, [[call("read", filePath=str(fixture)) for _ in range(4)]]
        )
        result = self.runtime.prompt("composer", plan)
        self.assertIn("doom_loop", json.dumps(result.error))
