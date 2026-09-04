#!/usr/bin/env python3
# Copyright 2026 Serghei Iakovlev
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import json
import sqlite3
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path

SKILL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_ROOT / "scripts"))

import audit_claude_code  # noqa: E402
import audit_opencode  # noqa: E402
import audit_usage  # noqa: E402


class OpenCodeAuditTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.database = Path(self.tempdir.name) / "opencode.db"
        connection = sqlite3.connect(self.database)
        connection.executescript(
            """
            CREATE TABLE session (
              id TEXT PRIMARY KEY,
              parent_id TEXT,
              directory TEXT NOT NULL,
              version TEXT NOT NULL,
              time_created INTEGER NOT NULL,
              time_updated INTEGER NOT NULL,
              agent TEXT,
              model TEXT,
              cost REAL NOT NULL,
              tokens_input INTEGER NOT NULL,
              tokens_output INTEGER NOT NULL,
              tokens_reasoning INTEGER NOT NULL,
              tokens_cache_read INTEGER NOT NULL,
              tokens_cache_write INTEGER NOT NULL
            );
            CREATE TABLE message (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              data TEXT NOT NULL
            );
            CREATE TABLE part (
              id TEXT PRIMARY KEY,
              message_id TEXT NOT NULL,
              session_id TEXT NOT NULL,
              data TEXT NOT NULL
            );
            """
        )
        self._insert_session(
            connection,
            "root",
            None,
            (15, 5, 1, 5, 4, 0.3),
            created=1_000,
            updated=5_000,
        )
        self._insert_session(
            connection,
            "child",
            "root",
            (7, 2, 0, 1, 0, 0.05),
            created=2_000,
            updated=4_000,
        )
        self._insert_message(connection, "root-user", "root", "user")
        self._insert_message(connection, "root-assistant", "root", "assistant")
        self._insert_message(connection, "child-assistant", "child", "assistant")
        self._insert_step(connection, "root-step-1", "root", (10, 2, 1, 3, 4, 0.1))
        self._insert_step(connection, "root-step-2", "root", (5, 3, 0, 2, 0, 0.2))
        self._insert_step(connection, "child-step", "child", (7, 2, 0, 1, 0, 0.05))
        self._insert_tool(connection, "root-read", "root", "read", "completed")
        self._insert_tool(connection, "root-edit", "root", "edit", "error")
        self._insert_tool(
            connection,
            "root-task",
            "root",
            "task",
            "completed",
            metadata={"sessionId": "child", "parentSessionId": "root"},
        )
        connection.commit()
        connection.close()

    def _insert_session(
        self,
        connection: sqlite3.Connection,
        session_id: str,
        parent_id: str | None,
        usage: tuple[int, int, int, int, int, float],
        *,
        created: int,
        updated: int,
    ) -> None:
        input_tokens, output, reasoning, cache_read, cache_write, cost = usage
        connection.execute(
            """
            INSERT INTO session VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                session_id,
                parent_id,
                "/workspace",
                "1.18.26",
                created,
                updated,
                "build",
                json.dumps({"id": "test-model", "providerID": "test"}),
                cost,
                input_tokens,
                output,
                reasoning,
                cache_read,
                cache_write,
            ),
        )

    def _insert_message(
        self,
        connection: sqlite3.Connection,
        message_id: str,
        session_id: str,
        role: str,
    ) -> None:
        connection.execute(
            "INSERT INTO message VALUES (?, ?, ?)",
            (message_id, session_id, json.dumps({"role": role})),
        )

    def _insert_step(
        self,
        connection: sqlite3.Connection,
        part_id: str,
        session_id: str,
        usage: tuple[int, int, int, int, int, float],
    ) -> None:
        input_tokens, output, reasoning, cache_read, cache_write, cost = usage
        data = {
            "type": "step-finish",
            "tokens": {
                "input": input_tokens,
                "output": output,
                "reasoning": reasoning,
                "cache": {"read": cache_read, "write": cache_write},
            },
            "cost": cost,
        }
        connection.execute(
            "INSERT INTO part VALUES (?, ?, ?, ?)",
            (part_id, f"{session_id}-assistant", session_id, json.dumps(data)),
        )

    def _insert_tool(
        self,
        connection: sqlite3.Connection,
        part_id: str,
        session_id: str,
        tool: str,
        status: str,
        *,
        metadata: dict[str, object] | None = None,
    ) -> None:
        state: dict[str, object] = {"status": status, "input": {}}
        if status == "error":
            state["error"] = "fixture failure"
        if metadata is not None:
            state["metadata"] = metadata
        data = {"type": "tool", "tool": tool, "state": state}
        connection.execute(
            "INSERT INTO part VALUES (?, ?, ?, ?)",
            (part_id, f"{session_id}-assistant", session_id, json.dumps(data)),
        )

    def test_audits_root_and_descendant_without_double_counting(self) -> None:
        report = audit_opencode.audit_database(self.database, "root", "1.18.27")

        totals = report["totals"]
        self.assertEqual(totals["sessions"], 2)
        self.assertEqual(totals["descendants"], 1)
        self.assertEqual(totals["usage"]["input"], 22)
        self.assertEqual(totals["usage"]["output"], 7)
        self.assertEqual(totals["usage"]["cache_write"], 4)
        self.assertEqual(totals["tool_calls"], 3)
        self.assertEqual(totals["tool_errors"], 1)
        self.assertTrue(report["validation"]["all_usage_reconciled"])
        self.assertTrue(
            report["validation"]["tree_reconciliation"]["matches_spawn_records"]
        )
        self.assertTrue(report["validation"]["exact_ready"])
        self.assertNotIn("sessions", report)

    def test_reports_a_summary_detail_mismatch(self) -> None:
        connection = sqlite3.connect(self.database)
        connection.execute("UPDATE session SET tokens_output = 99 WHERE id = 'root'")
        connection.commit()
        connection.close()

        report = audit_opencode.audit_database(
            self.database, "root", "1.18.27", include_sessions=True
        )

        self.assertFalse(report["validation"]["all_usage_reconciled"])
        sessions = report.get("sessions")
        assert sessions is not None
        root = sessions[0]
        self.assertEqual(
            root["reconciliation"]["mismatches"]["output"],
            {"session": 99, "detail": 5},
        )
        with redirect_stdout(StringIO()):
            exit_code = audit_opencode.main(["root", "--db", str(self.database)])
        self.assertEqual(exit_code, 1)

    def test_missing_spawned_child_blocks_exact_result(self) -> None:
        connection = sqlite3.connect(self.database)
        connection.execute("DELETE FROM session WHERE id = 'child'")
        connection.commit()
        connection.close()

        report = audit_opencode.audit_database(self.database, "root", "1.18.27")

        tree = report["validation"]["tree_reconciliation"]
        self.assertFalse(tree["matches_spawn_records"])
        self.assertEqual(tree["missing_session_ids"], ["child"])
        self.assertFalse(report["validation"]["exact_ready"])

    def test_rejects_fractional_token_counters(self) -> None:
        connection = sqlite3.connect(self.database)
        connection.execute("UPDATE session SET tokens_input = 1.5 WHERE id = 'root'")
        connection.commit()
        connection.close()

        with self.assertRaisesRegex(audit_opencode.AuditError, "must be an integer"):
            audit_opencode.audit_database(self.database, "root", "1.18.27")

    def test_unsupported_version_blocks_exact_result(self) -> None:
        report = audit_opencode.audit_database(self.database, "root", "1.19.0")

        self.assertFalse(report["validation"]["versions_supported"])
        self.assertFalse(report["validation"]["exact_ready"])

    def test_rejects_an_unknown_session(self) -> None:
        with self.assertRaisesRegex(audit_opencode.AuditError, "session not found"):
            audit_opencode.audit_database(self.database, "missing", "1.18.27")


class StreamUsageAuditTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.log = Path(self.tempdir.name) / "events.jsonl"

    def _write(self, records: list[dict[str, object]]) -> None:
        self.log.write_text(
            "".join(json.dumps(record) + "\n" for record in records),
            encoding="utf-8",
        )

    def test_keeps_string_and_nonstring_ids_as_distinct_groups(self) -> None:
        self._write(
            [
                {
                    "message": {
                        "id": "1",
                        "usage": {"input": 10, "output": 1},
                        "stop": "end",
                    }
                },
                {
                    "message": {
                        "id": 1,
                        "usage": {"input": 5, "output": 2},
                        "stop": "end",
                    }
                },
            ]
        )

        report, failed = audit_usage.aggregate(
            [self.log], "message.id", "message.usage", "message.stop"
        )

        self.assertFalse(failed)
        self.assertEqual(report["totals"]["by_message_max"]["input"], 15)
        self.assertEqual(report["files"][0]["messages"], 2)

    def test_reduces_verified_cumulative_snapshots(self) -> None:
        self._write(
            [
                {"message": {"id": "m1", "usage": {"input": 10, "output": 1}}},
                {
                    "message": {
                        "id": "m1",
                        "usage": {"input": 10, "output": 3},
                        "stop": "end",
                    }
                },
            ]
        )

        report, failed = audit_usage.aggregate(
            [self.log], "message.id", "message.usage", "message.stop"
        )

        self.assertFalse(failed)
        self.assertTrue(report["verified"])
        self.assertEqual(report["totals"]["by_message_max"], {"input": 10, "output": 3})
        self.assertEqual(
            report["totals"]["by_naive_record_sum"], {"input": 20, "output": 4}
        )

    def test_fails_when_terminal_evidence_is_missing(self) -> None:
        self._write([{"message": {"id": "m1", "usage": {"input": 10, "output": 1}}}])

        report, failed = audit_usage.aggregate(
            [self.log], "message.id", "message.usage", "message.stop"
        )

        self.assertTrue(failed)
        self.assertFalse(report["verified"])
        terminal_check = report["terminal_check"]
        assert terminal_check is not None
        self.assertEqual(terminal_check["groups_without_terminal_record"], 1)

    def test_rejects_false_as_an_implicit_terminal_marker(self) -> None:
        self._write(
            [
                {
                    "message": {
                        "id": "m1",
                        "usage": {"input": 10, "output": 1},
                        "done": False,
                    }
                }
            ]
        )

        report, failed = audit_usage.aggregate(
            [self.log], "message.id", "message.usage", "message.done"
        )

        self.assertTrue(failed)
        self.assertFalse(report["verified"])

    def test_accepts_an_explicit_boolean_terminal_value(self) -> None:
        self._write(
            [
                {
                    "message": {
                        "id": "m1",
                        "usage": {"input": 10, "output": 1},
                        "done": False,
                    }
                },
                {
                    "message": {
                        "id": "m1",
                        "usage": {"input": 10, "output": 3},
                        "done": True,
                    }
                },
            ]
        )

        report, failed = audit_usage.aggregate(
            [self.log],
            "message.id",
            "message.usage",
            "message.done",
            stop_value=True,
        )

        self.assertFalse(failed)
        self.assertTrue(report["verified"])

    def test_boolean_terminal_does_not_match_numeric_one(self) -> None:
        self._write(
            [
                {
                    "message": {
                        "id": "m1",
                        "usage": {"input": 10, "output": 3},
                        "done": 1,
                    }
                }
            ]
        )

        report, failed = audit_usage.aggregate(
            [self.log],
            "message.id",
            "message.usage",
            "message.done",
            stop_value=True,
        )

        self.assertTrue(failed)
        self.assertFalse(report["verified"])

    def test_rejects_a_terminal_marker_before_the_final_usage_record(self) -> None:
        self._write(
            [
                {
                    "message": {
                        "id": "m1",
                        "usage": {"input": 10, "output": 1},
                        "stop": "end",
                    }
                },
                {"message": {"id": "m1", "usage": {"input": 10, "output": 3}}},
            ]
        )

        report, failed = audit_usage.aggregate(
            [self.log], "message.id", "message.usage", "message.stop"
        )

        self.assertTrue(failed)
        terminal_check = report["terminal_check"]
        assert terminal_check is not None
        self.assertEqual(terminal_check["groups_with_invalid_terminal_marker"], 1)

    def test_probe_sees_terminal_fields_that_are_absent_until_the_end(self) -> None:
        self._write(
            [
                {"message": {"id": "m1", "usage": {"input": 10, "output": 1}}},
                {
                    "message": {
                        "id": "m1",
                        "usage": {"input": 10, "output": 3},
                        "stop": "end",
                    }
                },
            ]
        )

        report = audit_usage.probe([self.log], 400)

        candidates = {
            candidate["path"]: candidate
            for candidate in report["terminal_marker_candidates"]
        }
        self.assertEqual(candidates["message.stop"]["absent_on"], 1)

    def test_projects_numeric_fields_from_a_mixed_usage_object(self) -> None:
        self._write(
            [
                {
                    "message": {
                        "id": "m1",
                        "usage": {
                            "input": 10,
                            "output": 3,
                            "service_tier": "standard",
                        },
                        "stop": "end",
                    }
                }
            ]
        )

        probe = audit_usage.probe([self.log], 400)
        usage = next(
            item
            for item in probe["usage_candidates"]
            if item["path"] == "message.usage"
        )
        self.assertEqual(usage["other_fields"], ["service_tier"])
        report, failed = audit_usage.aggregate(
            [self.log],
            "message.id",
            "message.usage",
            "message.stop",
            usage_fields=["input", "output"],
        )
        self.assertFalse(failed)
        self.assertEqual(report["totals"]["by_message_max"]["output"], 3)

    def test_probe_accepts_a_single_numeric_usage_field(self) -> None:
        self._write(
            [
                {
                    "message": {
                        "id": "m1",
                        "usage": {"total_tokens": 13},
                        "stop": "end",
                    }
                }
            ]
        )

        report = audit_usage.probe([self.log], 400)

        self.assertTrue(report["usable"])
        self.assertTrue(
            any(
                candidate["path"] == "message.usage"
                for candidate in report["usage_candidates"]
            )
        )

    def test_rejects_malformed_jsonl_instead_of_silently_skipping_it(self) -> None:
        self.log.write_text('{"message":\n', encoding="utf-8")

        with self.assertRaisesRegex(audit_usage.LoadError, "cannot parse"):
            audit_usage.aggregate(
                [self.log], "message.id", "message.usage", "message.stop"
            )

    def test_rejects_a_usage_record_without_its_grouping_key(self) -> None:
        self._write([{"message": {"usage": {"input": 10, "output": 1}}}])

        with self.assertRaisesRegex(audit_usage.LoadError, "has no id"):
            audit_usage.aggregate(
                [self.log], "message.id", "message.usage", "message.stop"
            )

    def test_rejects_partially_numeric_usage_objects(self) -> None:
        self._write(
            [
                {
                    "message": {
                        "id": "m1",
                        "usage": {"input": 10, "cache": {"read": 2}},
                        "stop": "end",
                    }
                }
            ]
        )

        with self.assertRaisesRegex(
            audit_usage.LoadError, "missing or invalid numeric fields: cache"
        ):
            audit_usage.aggregate(
                [self.log], "message.id", "message.usage", "message.stop"
            )

    def test_probe_fails_closed_on_an_empty_array(self) -> None:
        self.log.write_text("[]\n", encoding="utf-8")

        with redirect_stdout(StringIO()):
            exit_code = audit_usage.main(["--probe", str(self.log)])

        self.assertEqual(exit_code, 1)

    def test_rejects_non_object_records(self) -> None:
        self.log.write_text('"not an event"\n', encoding="utf-8")

        with self.assertRaisesRegex(audit_usage.LoadError, "record is not an object"):
            audit_usage.probe([self.log], 400)


class ClaudeCodeAuditTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.root = Path(self.tempdir.name) / "session.jsonl"

    def _message(
        self,
        index: int,
        output_tokens: int,
        *,
        tool: bool = True,
    ) -> list[dict[str, object]]:
        content: list[dict[str, object]] = []
        if tool:
            content.append(
                {
                    "type": "tool_use",
                    "id": f"t{index}",
                    "name": "Read",
                    "input": {"file_path": f"/repo/file{index % 2}.go"},
                }
            )
        else:
            content.append({"type": "text", "text": "done"})
        records: list[dict[str, object]] = [
            {
                "type": "assistant",
                "message": {
                    "id": f"msg_{index}",
                    "role": "assistant",
                    "stop_reason": "tool_use" if tool else "end_turn",
                    "usage": {
                        "input_tokens": 2,
                        "cache_creation_input_tokens": 10,
                        "cache_read_input_tokens": 100 * index,
                        "output_tokens": output_tokens,
                    },
                    "content": content,
                },
            }
        ]
        if tool:
            records.append(
                {
                    "type": "user",
                    "message": {
                        "role": "user",
                        "content": [
                            {
                                "type": "tool_result",
                                "tool_use_id": f"t{index}",
                                "content": "ok",
                            }
                        ],
                    },
                }
            )
        return records

    def _write(self, path: Path, records: list[dict[str, object]]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "".join(json.dumps(record) + "\n" for record in records),
            encoding="utf-8",
        )

    def _child(self, name: str, meta: dict[str, object], outputs: int) -> None:
        subagents = self.root.parent / self.root.stem / "subagents"
        transcript = subagents / f"agent-{name}.jsonl"
        records: list[dict[str, object]] = []
        for index in range(3):
            records.extend(self._message(index + outputs, 400 + index))
        self._write(transcript, records)
        (subagents / f"agent-{name}.meta.json").write_text(
            json.dumps(meta), encoding="utf-8"
        )

    def test_splits_forked_children_from_spawned_children(self) -> None:
        self._write(self.root, self._message(0, 500))
        self._child("aaa", {"agentType": "composer"}, 10)
        self._child(
            "bbb",
            {"agentType": "architect", "toolUseId": "toolu_1", "spawnDepth": 1},
            20,
        )

        report, code = audit_claude_code.audit(self.root, with_counters=False)

        modes = {node["agent_id"]: node["delegation"] for node in report["agents"]}
        self.assertEqual(modes["agent-aaa"], "fork")
        self.assertEqual(modes["agent-bbb"], "spawn")
        self.assertEqual(modes[self.root.stem], "root")
        self.assertIn("fork", report["totals_by_delegation"])
        self.assertIn("spawn", report["totals_by_delegation"])
        self.assertEqual(code, 0)

    def test_counters_check_flags_a_frozen_output_snapshot(self) -> None:
        records: list[dict[str, object]] = []
        for index in range(10):
            records.extend(self._message(index, 1))
        self._write(self.root, records)

        report, code = audit_claude_code.audit(self.root, with_counters=True)

        counters = report["counters"]
        assert counters is not None
        self.assertTrue(counters["frozen_snapshot_suspected"])
        self.assertEqual(counters["tool_call_messages_at_or_below_ceiling"], 10)
        self.assertEqual(code, 1)

    def test_counters_check_stays_silent_on_a_healthy_transcript(self) -> None:
        records: list[dict[str, object]] = []
        for index in range(10):
            records.extend(self._message(index, 300 + index * 11))
        self._write(self.root, records)

        report, code = audit_claude_code.audit(self.root, with_counters=True)

        counters = report["counters"]
        assert counters is not None
        self.assertFalse(counters["frozen_snapshot_suspected"])
        self.assertEqual(counters["tool_call_messages_at_or_below_ceiling"], 0)
        self.assertEqual(code, 0)

    def test_reduces_repeated_records_of_one_message_by_maximum(self) -> None:
        first = self._message(0, 5)
        repeat = json.loads(json.dumps(first[0]))
        message = repeat["message"]
        message["usage"]["output_tokens"] = 900
        self._write(self.root, [first[0], repeat, first[1]])

        report, _ = audit_claude_code.audit(self.root, with_counters=False)

        node = report["agents"][0]
        self.assertEqual(node["messages"], 1)
        self.assertEqual(node["usage"]["output_tokens"], 900)

    def test_reports_unmatched_tool_use_as_a_snapshot(self) -> None:
        record = self._message(0, 500)[0]
        self._write(self.root, [record])

        report, _ = audit_claude_code.audit(self.root, with_counters=False)

        self.assertEqual(report["status"], "snapshot")
        self.assertEqual(report["reconciliation"]["unmatched_tool_use"], 1)

    def test_counts_repeat_reads_of_one_target(self) -> None:
        records: list[dict[str, object]] = []
        for index in range(4):
            records.extend(self._message(index, 300 + index))
        self._write(self.root, records)

        report, _ = audit_claude_code.audit(self.root, with_counters=False)

        self.assertEqual(report["agents"][0]["repeat_reads"], 2)

    def test_missing_root_transcript_raises(self) -> None:
        with self.assertRaisesRegex(audit_claude_code.AuditError, "not found"):
            audit_claude_code.audit(self.root, with_counters=False)


if __name__ == "__main__":
    unittest.main()
