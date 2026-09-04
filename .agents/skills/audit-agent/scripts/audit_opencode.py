#!/usr/bin/env python3
# Copyright 2026 Serghei Iakovlev
# SPDX-License-Identifier: Apache-2.0
"""Audit one OpenCode session tree from a consistent read-only DB snapshot.

The report contains structural metadata, usage totals, and tool/message counts.
It never emits prompts, text parts, tool inputs, or tool outputs.

Exit: 0 supported versions plus usage and spawn-tree reconciliation passed,
1 evidence is incomplete, mismatched, or unsupported, 2 usage/schema/database
error.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sqlite3
import subprocess
import sys
from collections import Counter, deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, TypedDict, cast
from urllib.parse import quote

SESSION_FIELDS = (
    "id",
    "parent_id",
    "directory",
    "version",
    "time_created",
    "time_updated",
    "agent",
    "model",
    "cost",
    "tokens_input",
    "tokens_output",
    "tokens_reasoning",
    "tokens_cache_read",
    "tokens_cache_write",
)
REQUIRED_COLUMNS = {
    "session": set(SESSION_FIELDS),
    "message": {"id", "session_id", "data"},
    "part": {"id", "message_id", "session_id", "data"},
}
USAGE_FIELDS = ("input", "output", "reasoning", "cache_read", "cache_write", "cost")
SUPPORTED_MAJOR_MINOR = {(1, 18)}


class UsageReport(TypedDict):
    input: int | float
    output: int | float
    reasoning: int | float
    cache_read: int | float
    cache_write: int | float
    cost: int | float


class SessionTime(TypedDict):
    created_ms: int
    updated_ms: int
    created_utc: str
    updated_utc: str
    session_span_ms: int


class SessionCounts(TypedDict):
    messages: dict[str, int]
    model_steps: int
    tool_calls: int
    tool_errors: int


class SessionDetails(TypedDict):
    parts: int
    part_types: dict[str, int]
    tool_names: dict[str, int]
    tool_statuses: dict[str, int]


class ReconciliationReport(TypedDict):
    step_finish_records: int
    matches_session_totals: bool
    detail_usage: UsageReport
    mismatches: dict[str, dict[str, int | float] | str]


class SessionReportRequired(TypedDict):
    depth: int
    id: str
    parent_id: str | None
    directory: str
    agent: str
    model: object
    recorded_version: str
    time: SessionTime
    usage: UsageReport
    counts: SessionCounts
    reconciliation: ReconciliationReport


class SessionReport(SessionReportRequired, total=False):
    details: SessionDetails


class AgentBucket(TypedDict):
    sessions: int
    usage: dict[str, float]


class AgentTotals(TypedDict):
    sessions: int
    usage: UsageReport


class TreeSpan(TypedDict):
    created_ms: int
    updated_ms: int
    elapsed_ms: int


class TotalsReport(TypedDict):
    sessions: int
    descendants: int
    usage: UsageReport
    by_agent: dict[str, AgentTotals]
    messages: dict[str, int]
    model_steps: int
    tool_calls: int
    tool_errors: int
    tool_names: dict[str, int]
    tool_statuses: dict[str, int]
    tree_span: TreeSpan


class VersionsReport(TypedDict):
    installed: str | None
    recorded: list[str]
    supported_major_minor: list[str]
    installed_supported: bool
    unsupported_recorded: list[str]
    all_supported: bool


class ScopeReport(TypedDict):
    sessions: int
    descendants: int
    session_ids: list[str]


class SchemaCheck(TypedDict):
    columns_verified: int
    required_columns: int


class TreeReconciliation(TypedDict):
    matches_spawn_records: bool
    spawn_links_checked: int
    missing_session_ids: list[str]
    parent_mismatches: list[dict[str, str | None]]
    unresolved_calls: list[dict[str, str]]


class ValidationReport(TypedDict):
    all_usage_reconciled: bool
    usage_mismatch_session_ids: list[str]
    tree_reconciliation: TreeReconciliation
    versions_supported: bool
    exact_ready: bool
    sessions_checked: int
    consistent_snapshot: bool


class OpenCodeReportRequired(TypedDict):
    mode: str
    source: str
    database: str
    root_session_id: str
    snapshot_utc: str
    versions: VersionsReport
    scope: ScopeReport
    schema: dict[str, list[str]] | dict[str, SchemaCheck]
    totals: TotalsReport
    validation: ValidationReport


class OpenCodeReport(OpenCodeReportRequired, total=False):
    sessions: list[SessionReport]


class AuditError(Exception):
    pass


def _plain(value: float) -> int | float:
    return int(value) if value.is_integer() else value


def _number(value: object, label: str, *, integral: bool = False) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise AuditError(f"{label} is not numeric")
    number = float(value)
    if not math.isfinite(number) or number < 0:
        raise AuditError(f"{label} must be finite and non-negative")
    if integral and not number.is_integer():
        raise AuditError(f"{label} must be an integer")
    return number


def _json_object(value: object, label: str) -> dict[str, object]:
    if isinstance(value, dict):
        return cast(dict[str, object], value)
    if not isinstance(value, str):
        raise AuditError(f"{label} is not a JSON object")
    try:
        parsed: object = json.loads(value)
    except json.JSONDecodeError as exc:
        raise AuditError(f"cannot parse {label}: {exc}") from exc
    if not isinstance(parsed, dict):
        raise AuditError(f"{label} is not a JSON object")
    return cast(dict[str, object], parsed)


def _optional_json(value: object) -> object:
    if not isinstance(value, str):
        return value
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return value


def _zero_usage() -> dict[str, float]:
    return {field: 0.0 for field in USAGE_FIELDS}


def _add_usage(target: dict[str, float], source: dict[str, float]) -> None:
    for field in USAGE_FIELDS:
        target[field] += source[field]


def _display_usage(usage: dict[str, float]) -> UsageReport:
    return cast(UsageReport, {field: _plain(usage[field]) for field in USAGE_FIELDS})


def _utc(milliseconds: int) -> str:
    try:
        return datetime.fromtimestamp(milliseconds / 1000, tz=timezone.utc).isoformat()
    except (OSError, OverflowError, ValueError) as exc:
        raise AuditError(
            f"timestamp is outside the supported range: {milliseconds}"
        ) from exc


def _major_minor(version: str | None) -> tuple[int, int] | None:
    if version is None:
        return None
    match = re.match(r"^v?(\d+)\.(\d+)", version)
    if match is None:
        return None
    return int(match.group(1)), int(match.group(2))


def _resolve_database(explicit: Path | None) -> Path:
    if explicit is not None:
        try:
            return explicit.expanduser().resolve(strict=True)
        except OSError as exc:
            raise AuditError(f"cannot resolve database {explicit}: {exc}") from exc

    try:
        result = subprocess.run(
            ["opencode", "db", "path"],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        raise AuditError("opencode is not installed; pass --db explicitly") from exc
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or exc.stdout.strip() or f"exit {exc.returncode}"
        raise AuditError(f"opencode db path failed: {detail}") from exc

    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if not lines:
        raise AuditError("opencode db path returned no path")
    try:
        return Path(lines[-1]).expanduser().resolve(strict=True)
    except OSError as exc:
        raise AuditError(
            f"cannot resolve database reported by opencode: {exc}"
        ) from exc


def _opencode_version() -> str | None:
    try:
        result = subprocess.run(
            ["opencode", "--version"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None
    return result.stdout.strip() or None


def _table_columns(connection: sqlite3.Connection, table: str) -> set[str]:
    rows = connection.execute(f"PRAGMA table_info({table})").fetchall()
    return {cast(str, row["name"]) for row in rows}


def _validate_schema(connection: sqlite3.Connection) -> dict[str, list[str]]:
    observed: dict[str, list[str]] = {}
    for table, required in REQUIRED_COLUMNS.items():
        columns = _table_columns(connection, table)
        missing = sorted(required - columns)
        if missing:
            raise AuditError(f"{table} schema is missing columns: {', '.join(missing)}")
        observed[table] = sorted(columns)
    return observed


def _session_query() -> str:
    return f"SELECT {', '.join(SESSION_FIELDS)} FROM session"


def _session_tree(
    connection: sqlite3.Connection, root_session_id: str
) -> list[tuple[int, sqlite3.Row]]:
    root = connection.execute(
        _session_query() + " WHERE id = ?", (root_session_id,)
    ).fetchone()
    if root is None:
        raise AuditError(f"session not found: {root_session_id}")

    result: list[tuple[int, sqlite3.Row]] = []
    queue: deque[tuple[int, sqlite3.Row]] = deque([(0, root)])
    seen: set[str] = set()
    while queue:
        depth, row = queue.popleft()
        session_id = cast(str, row["id"])
        if session_id in seen:
            raise AuditError(f"cycle or duplicate session in parent tree: {session_id}")
        seen.add(session_id)
        result.append((depth, row))
        children = connection.execute(
            _session_query() + " WHERE parent_id = ? ORDER BY time_created ASC, id ASC",
            (session_id,),
        ).fetchall()
        queue.extend((depth + 1, child) for child in children)
    return result


def _session_usage(row: sqlite3.Row) -> dict[str, float]:
    return {
        "input": _number(row["tokens_input"], "session.tokens_input", integral=True),
        "output": _number(row["tokens_output"], "session.tokens_output", integral=True),
        "reasoning": _number(
            row["tokens_reasoning"], "session.tokens_reasoning", integral=True
        ),
        "cache_read": _number(
            row["tokens_cache_read"], "session.tokens_cache_read", integral=True
        ),
        "cache_write": _number(
            row["tokens_cache_write"], "session.tokens_cache_write", integral=True
        ),
        "cost": _number(row["cost"], "session.cost"),
    }


def _part_evidence(connection: sqlite3.Connection, session_id: str) -> dict[str, Any]:
    part_types: Counter[str] = Counter()
    tool_names: Counter[str] = Counter()
    tool_statuses: Counter[str] = Counter()
    tool_errors = 0
    step_finish_records = 0
    detail_usage = _zero_usage()
    spawn_links: list[dict[str, str]] = []
    unresolved_spawns: list[dict[str, str]] = []

    rows = connection.execute(
        "SELECT id, data FROM part WHERE session_id = ?", (session_id,)
    ).fetchall()
    for row in rows:
        part = _json_object(row["data"], f"part {row['id']}.data")
        part_type = part.get("type")
        if not isinstance(part_type, str):
            raise AuditError(f"part {row['id']} has no string type")
        part_types[part_type] += 1

        if part_type == "step-finish":
            tokens = _json_object(part.get("tokens"), f"part {row['id']}.tokens")
            cache = _json_object(tokens.get("cache"), f"part {row['id']}.tokens.cache")
            usage = {
                "input": _number(
                    tokens.get("input"),
                    f"part {row['id']}.tokens.input",
                    integral=True,
                ),
                "output": _number(
                    tokens.get("output"),
                    f"part {row['id']}.tokens.output",
                    integral=True,
                ),
                "reasoning": _number(
                    tokens.get("reasoning"),
                    f"part {row['id']}.tokens.reasoning",
                    integral=True,
                ),
                "cache_read": _number(
                    cache.get("read"),
                    f"part {row['id']}.tokens.cache.read",
                    integral=True,
                ),
                "cache_write": _number(
                    cache.get("write"),
                    f"part {row['id']}.tokens.cache.write",
                    integral=True,
                ),
                "cost": _number(part.get("cost"), f"part {row['id']}.cost"),
            }
            _add_usage(detail_usage, usage)
            step_finish_records += 1

        if part_type == "tool":
            tool = part.get("tool")
            tool_name = tool if isinstance(tool, str) else "<missing>"
            state = _json_object(part.get("state"), f"part {row['id']}.state")
            status = state.get("status")
            status_name = status if isinstance(status, str) else "<missing>"
            tool_names[tool_name] += 1
            tool_statuses[status_name] += 1
            if status_name == "error" or state.get("error") not in (None, ""):
                tool_errors += 1

            metadata_value = state.get("metadata")
            if metadata_value is None:
                metadata: dict[str, object] = {}
            elif isinstance(metadata_value, dict):
                metadata = cast(dict[str, object], metadata_value)
            else:
                raise AuditError(f"part {row['id']}.state.metadata is not an object")
            child_value = metadata.get("sessionId")
            parent_value = metadata.get("parentSessionId")
            if child_value is not None and not isinstance(child_value, str):
                raise AuditError(f"part {row['id']} metadata.sessionId is not a string")
            if parent_value is not None and not isinstance(parent_value, str):
                raise AuditError(
                    f"part {row['id']} metadata.parentSessionId is not a string"
                )
            call_value = part.get("callID")
            call_id = (
                call_value if isinstance(call_value, str) else cast(str, row["id"])
            )
            if tool_name == "task" and isinstance(child_value, str):
                spawn_links.append(
                    {
                        "source_session_id": session_id,
                        "child_session_id": child_value,
                        "parent_session_id": (
                            parent_value
                            if isinstance(parent_value, str)
                            else session_id
                        ),
                        "tool": tool_name,
                        "status": status_name,
                        "call_id": call_id,
                    }
                )
            if tool_name == "task" and (
                status_name not in {"completed", "error"}
                or (status_name == "completed" and not isinstance(child_value, str))
            ):
                unresolved_spawns.append(
                    {
                        "source_session_id": session_id,
                        "call_id": call_id,
                        "status": status_name,
                    }
                )

    return {
        "parts": len(rows),
        "part_types": dict(sorted(part_types.items())),
        "model_steps": step_finish_records,
        "detail_usage": detail_usage,
        "tool_calls": sum(tool_names.values()),
        "tool_errors": tool_errors,
        "tool_names": dict(sorted(tool_names.items())),
        "tool_statuses": dict(sorted(tool_statuses.items())),
        "spawn_links": spawn_links,
        "unresolved_spawns": unresolved_spawns,
    }


def _message_counts(connection: sqlite3.Connection, session_id: str) -> Counter[str]:
    roles: Counter[str] = Counter()
    rows = connection.execute(
        "SELECT id, data FROM message WHERE session_id = ?", (session_id,)
    ).fetchall()
    for row in rows:
        message = _json_object(row["data"], f"message {row['id']}.data")
        role = message.get("role")
        roles[role if isinstance(role, str) else "<missing>"] += 1
    return roles


def _reconcile(
    session_usage: dict[str, float], detail_usage: dict[str, float], steps: int
) -> ReconciliationReport:
    if steps == 0:
        return {
            "step_finish_records": 0,
            "matches_session_totals": False,
            "detail_usage": _display_usage(detail_usage),
            "mismatches": {"detail": "no step-finish records"},
        }

    mismatches: dict[str, dict[str, int | float] | str] = {}
    for field in USAGE_FIELDS:
        summary = session_usage[field]
        detail = detail_usage[field]
        equal = (
            math.isclose(summary, detail, rel_tol=1e-9, abs_tol=1e-9)
            if field == "cost"
            else summary == detail
        )
        if not equal:
            mismatches[field] = {"session": _plain(summary), "detail": _plain(detail)}
    return {
        "step_finish_records": steps,
        "matches_session_totals": not mismatches,
        "detail_usage": _display_usage(detail_usage),
        "mismatches": mismatches,
    }


def audit_database(
    database: Path,
    root_session_id: str,
    opencode_version: str | None = None,
    *,
    include_sessions: bool = False,
    details: bool = False,
) -> OpenCodeReport:
    uri = f"file:{quote(str(database), safe='/')}?mode=ro"
    try:
        connection = sqlite3.connect(uri, uri=True)
    except sqlite3.Error as exc:
        raise AuditError(f"cannot open database read-only: {exc}") from exc
    connection.row_factory = sqlite3.Row

    try:
        connection.execute("BEGIN")
        snapshot_utc = datetime.now(tz=timezone.utc).isoformat()
        schema = _validate_schema(connection)
        tree = _session_tree(connection, root_session_id)

        sessions: list[SessionReport] = []
        total_usage = _zero_usage()
        total_messages: Counter[str] = Counter()
        total_tool_names: Counter[str] = Counter()
        total_tool_statuses: Counter[str] = Counter()
        total_model_steps = 0
        total_tool_errors = 0
        by_agent: dict[str, AgentBucket] = {}
        created_values: list[int] = []
        updated_values: list[int] = []
        spawn_links: list[dict[str, str]] = []
        unresolved_spawns: list[dict[str, str]] = []
        recorded_versions: set[str] = set()

        for depth, row in tree:
            session_id = cast(str, row["id"])
            usage = _session_usage(row)
            evidence = _part_evidence(connection, session_id)
            roles = _message_counts(connection, session_id)
            reconciliation = _reconcile(
                usage,
                cast(dict[str, float], evidence["detail_usage"]),
                cast(int, evidence["model_steps"]),
            )
            created = int(
                _number(row["time_created"], "session.time_created", integral=True)
            )
            updated = int(
                _number(row["time_updated"], "session.time_updated", integral=True)
            )
            created_values.append(created)
            updated_values.append(updated)
            recorded_value = row["version"]
            recorded_version = (
                recorded_value if isinstance(recorded_value, str) else "<unknown>"
            )
            recorded_versions.add(recorded_version)

            agent_value = row["agent"]
            agent = agent_value if isinstance(agent_value, str) else "<unknown>"
            agent_bucket = by_agent.setdefault(
                agent, AgentBucket(sessions=0, usage=_zero_usage())
            )
            agent_bucket["sessions"] += 1
            _add_usage(agent_bucket["usage"], usage)

            _add_usage(total_usage, usage)
            total_messages.update(roles)
            total_tool_names.update(cast(dict[str, int], evidence["tool_names"]))
            total_tool_statuses.update(cast(dict[str, int], evidence["tool_statuses"]))
            total_model_steps += cast(int, evidence["model_steps"])
            total_tool_errors += cast(int, evidence["tool_errors"])
            spawn_links.extend(cast(list[dict[str, str]], evidence["spawn_links"]))
            unresolved_spawns.extend(
                cast(list[dict[str, str]], evidence["unresolved_spawns"])
            )

            if not details and reconciliation["matches_session_totals"]:
                reconciliation.pop("detail_usage")
            session_report: SessionReport = {
                "depth": depth,
                "id": session_id,
                "parent_id": cast("str | None", row["parent_id"]),
                "directory": cast(str, row["directory"]),
                "agent": agent,
                "model": _optional_json(row["model"]),
                "recorded_version": recorded_version,
                "time": {
                    "created_ms": created,
                    "updated_ms": updated,
                    "created_utc": _utc(created),
                    "updated_utc": _utc(updated),
                    "session_span_ms": updated - created,
                },
                "usage": _display_usage(usage),
                "counts": {
                    "messages": dict(sorted(roles.items())),
                    "model_steps": evidence["model_steps"],
                    "tool_calls": evidence["tool_calls"],
                    "tool_errors": evidence["tool_errors"],
                },
                "reconciliation": reconciliation,
            }
            if details:
                session_report["details"] = {
                    "parts": evidence["parts"],
                    "part_types": evidence["part_types"],
                    "tool_names": evidence["tool_names"],
                    "tool_statuses": evidence["tool_statuses"],
                }
            sessions.append(session_report)

        all_reconciled = all(
            session["reconciliation"]["matches_session_totals"] for session in sessions
        )
        parent_by_session = {
            session["id"]: session["parent_id"] for session in sessions
        }
        missing_spawn_sessions: set[str] = set()
        parent_mismatches: list[dict[str, str | None]] = []
        for link in spawn_links:
            child_id = link["child_session_id"]
            child_row = connection.execute(
                "SELECT parent_id FROM session WHERE id = ?", (child_id,)
            ).fetchone()
            if child_row is None:
                missing_spawn_sessions.add(child_id)
                continue
            actual_parent = cast("str | None", child_row["parent_id"])
            expected_parent = link["parent_session_id"]
            if (
                child_id not in parent_by_session
                or actual_parent != expected_parent
                or expected_parent != link["source_session_id"]
            ):
                parent_mismatches.append(
                    {
                        "child_session_id": child_id,
                        "source_session_id": link["source_session_id"],
                        "metadata_parent_session_id": expected_parent,
                        "actual_parent_session_id": actual_parent,
                    }
                )
        tree_reconciled = not (
            missing_spawn_sessions or parent_mismatches or unresolved_spawns
        )
        unsupported_recorded_versions = sorted(
            version
            for version in recorded_versions
            if _major_minor(version) not in SUPPORTED_MAJOR_MINOR
        )
        installed_version_supported = (
            _major_minor(opencode_version) in SUPPORTED_MAJOR_MINOR
        )
        versions_supported = (
            installed_version_supported and not unsupported_recorded_versions
        )
        exact_ready = all_reconciled and tree_reconciled and versions_supported
        usage_mismatches = [
            session["id"]
            for session in sessions
            if not session["reconciliation"]["matches_session_totals"]
        ]
        displayed_by_agent: dict[str, AgentTotals] = {
            agent: AgentTotals(
                sessions=bucket["sessions"],
                usage=_display_usage(bucket["usage"]),
            )
            for agent, bucket in sorted(by_agent.items())
        }
        compact_schema: dict[str, SchemaCheck] = {
            table: SchemaCheck(
                columns_verified=len(columns),
                required_columns=len(REQUIRED_COLUMNS[table]),
            )
            for table, columns in schema.items()
        }
        report: OpenCodeReport = {
            "mode": "opencode",
            "source": "sqlite-read-transaction",
            "database": str(database),
            "root_session_id": root_session_id,
            "snapshot_utc": snapshot_utc,
            "versions": {
                "installed": opencode_version,
                "recorded": sorted(recorded_versions),
                "supported_major_minor": [
                    f"{major}.{minor}" for major, minor in sorted(SUPPORTED_MAJOR_MINOR)
                ],
                "installed_supported": installed_version_supported,
                "unsupported_recorded": unsupported_recorded_versions,
                "all_supported": versions_supported,
            },
            "scope": {
                "sessions": len(sessions),
                "descendants": len(sessions) - 1,
                "session_ids": [session["id"] for session in sessions],
            },
            "schema": schema if details else compact_schema,
            "totals": {
                "sessions": len(sessions),
                "descendants": len(sessions) - 1,
                "usage": _display_usage(total_usage),
                "by_agent": displayed_by_agent,
                "messages": dict(sorted(total_messages.items())),
                "model_steps": total_model_steps,
                "tool_calls": sum(total_tool_names.values()),
                "tool_errors": total_tool_errors,
                "tool_names": dict(sorted(total_tool_names.items())),
                "tool_statuses": dict(sorted(total_tool_statuses.items())),
                "tree_span": {
                    "created_ms": min(created_values),
                    "updated_ms": max(updated_values),
                    "elapsed_ms": max(updated_values) - min(created_values),
                },
            },
            "validation": {
                "all_usage_reconciled": all_reconciled,
                "usage_mismatch_session_ids": usage_mismatches,
                "tree_reconciliation": {
                    "matches_spawn_records": tree_reconciled,
                    "spawn_links_checked": len(spawn_links),
                    "missing_session_ids": sorted(missing_spawn_sessions),
                    "parent_mismatches": parent_mismatches,
                    "unresolved_calls": unresolved_spawns,
                },
                "versions_supported": versions_supported,
                "exact_ready": exact_ready,
                "sessions_checked": len(sessions),
                "consistent_snapshot": True,
            },
        }
        if include_sessions or details:
            report["sessions"] = sessions
        return report
    except sqlite3.Error as exc:
        raise AuditError(f"database query failed: {exc}") from exc
    finally:
        connection.close()


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="audit_opencode.py",
        description="Audit an OpenCode root session and all descendants read-only.",
    )
    parser.add_argument("session_id", help="Root OpenCode session id.")
    parser.add_argument(
        "--db",
        type=Path,
        help="OpenCode SQLite database path; defaults to `opencode db path`.",
    )
    parser.add_argument(
        "--sessions",
        action="store_true",
        help="Include per-session usage, timing, and reconciliation records.",
    )
    parser.add_argument(
        "--details",
        action="store_true",
        help="Include sessions, schema columns, and per-session part/tool breakdowns.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        database = _resolve_database(cast("Path | None", args.db))
        report = audit_database(
            database,
            cast(str, args.session_id),
            opencode_version=_opencode_version(),
            include_sessions=cast(bool, args.sessions),
            details=cast(bool, args.details),
        )
    except AuditError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    print(json.dumps(report, indent=2, sort_keys=False))
    return 0 if report["validation"]["exact_ready"] else 1


if __name__ == "__main__":
    sys.exit(main())
