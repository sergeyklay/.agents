#!/usr/bin/env python3
# Copyright 2026 Serghei Iakovlev
# SPDX-License-Identifier: Apache-2.0
"""Audit one Claude Code session tree from its JSONL transcripts.

Reconstructs the run described in references/claude-code.md: the root
transcript, every child under <session-id>/subagents/, and the delegation
edges recorded in the sibling *.meta.json files. Usage is reduced per
(file, message id) by maximum, which is the documented reduction for this
layout.

Two things this reports that a plain usage sum does not. Children are split
into spawned and forked populations, because a fork carries no spawning
tool-call id and does not behave like a spawn. And --counters tests whether
output_tokens is trustworthy at all, rather than assuming a passing
maximum-versus-terminal comparison settled it.

Nothing is written and no session store is modified.

Exit: 0 evidence reconciled, 1 evidence missing or disagreeing, 2 usage
error or session unavailable.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Optional, TypedDict

USAGE_FIELDS = (
    "input_tokens",
    "cache_creation_input_tokens",
    "cache_read_input_tokens",
    "output_tokens",
)
FROZEN_SNAPSHOT_CEILING = 20
FROZEN_SNAPSHOT_SHARE = 0.25
READ_TOOLS = ("Read", "NotebookRead")


class AgentNode(TypedDict):
    """One transcript in the run, root or child."""

    agent_id: str
    agent_type: str
    description: str
    parent_agent_id: Optional[str]
    spawn_depth: Optional[int]
    delegation: str
    messages: int
    usage: dict[str, int]
    tool_calls: int
    tools: dict[str, int]
    repeat_reads: int
    path: str


class CounterCheck(TypedDict):
    """Verdict on whether output_tokens can be believed."""

    messages: int
    tool_call_messages_at_or_below_ceiling: int
    share: float
    varying_within_message_id: int
    frozen_snapshot_suspected: bool


class Reconciliation(TypedDict):
    """Second path over independently stored records."""

    tool_use_blocks: int
    tool_result_blocks: int
    unmatched_tool_use: int
    transcripts_without_usage: list[str]


class Report(TypedDict):
    """Full audit result."""

    status: str
    root_session_id: str
    project: str
    transcripts: int
    agents: list[AgentNode]
    totals_by_agent_type: dict[str, dict[str, int]]
    totals_by_delegation: dict[str, dict[str, int]]
    duplicate_reads_across_agents: list[dict[str, object]]
    reconciliation: Reconciliation
    counters: Optional[CounterCheck]


class AuditError(Exception):
    """Raised when the requested session cannot be audited."""


def _records(path: Path) -> list[dict[str, object]]:
    """Return every JSON object in a JSONL transcript, skipping bad lines."""
    out: list[dict[str, object]] = []
    try:
        text = path.read_text(errors="replace")
    except OSError as exc:
        raise AuditError(f"cannot read {path}: {exc}") from exc
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            parsed: object = json.loads(line)
        except ValueError:
            continue
        if isinstance(parsed, dict):
            out.append(parsed)
    return out


def _message(record: dict[str, object]) -> Optional[dict[str, object]]:
    """Return the message object of a record, when it carries one."""
    message = record.get("message")
    return message if isinstance(message, dict) else None


def _blocks(message: dict[str, object]) -> list[dict[str, object]]:
    """Return the content blocks of a message, when content is a list."""
    content = message.get("content")
    if not isinstance(content, list):
        return []
    return [block for block in content if isinstance(block, dict)]


def _int(value: object) -> int:
    """Coerce a JSON number to int, treating anything else as zero."""
    return value if isinstance(value, int) and not isinstance(value, bool) else 0


def _target(name: str, tool_input: dict[str, object]) -> str:
    """Return a stable identity for what a tool call acted on."""
    for key in ("file_path", "notebook_path", "path"):
        value = tool_input.get(key)
        if isinstance(value, str):
            return value
    for key in ("command", "pattern", "skill", "url"):
        value = tool_input.get(key)
        if isinstance(value, str):
            return value[:200]
    return ""


def _usage_by_message(records: list[dict[str, object]]) -> dict[str, dict[str, int]]:
    """Reduce usage per message id by maximum, per this adapter's contract."""
    seen: dict[str, dict[str, int]] = {}
    for record in records:
        message = _message(record)
        if message is None:
            continue
        usage = message.get("usage")
        message_id = message.get("id")
        if not isinstance(usage, dict) or not isinstance(message_id, str):
            continue
        current = seen.setdefault(message_id, dict.fromkeys(USAGE_FIELDS, 0))
        for field in USAGE_FIELDS:
            current[field] = max(current[field], _int(usage.get(field)))
    return seen


def _tool_calls(records: list[dict[str, object]]) -> list[tuple[str, str]]:
    """Return (tool name, target) for every tool_use block, in order."""
    calls: list[tuple[str, str]] = []
    for record in records:
        message = _message(record)
        if message is None:
            continue
        for block in _blocks(message):
            if block.get("type") != "tool_use":
                continue
            name = block.get("name")
            tool_input = block.get("input")
            calls.append(
                (
                    name if isinstance(name, str) else "?",
                    _target(
                        name if isinstance(name, str) else "?",
                        tool_input if isinstance(tool_input, dict) else {},
                    ),
                )
            )
    return calls


def _block_ids(records: list[dict[str, object]], kind: str, key: str) -> set[str]:
    """Collect the ids of every content block of one type."""
    found: set[str] = set()
    for record in records:
        message = _message(record)
        if message is None:
            continue
        for block in _blocks(message):
            if block.get("type") != kind:
                continue
            value = block.get(key)
            if isinstance(value, str):
                found.add(value)
    return found


def _meta(transcript: Path) -> dict[str, object]:
    """Read the *.meta.json sibling of a child transcript."""
    sidecar = transcript.with_suffix(".meta.json")
    if not sidecar.exists():
        return {}
    try:
        parsed: object = json.loads(sidecar.read_text(errors="replace"))
    except (OSError, ValueError):
        return {}
    return parsed if isinstance(parsed, dict) else {}


def _node(transcript: Path, meta: dict[str, object], is_root: bool) -> AgentNode:
    """Build one node of the delegation forest from a transcript."""
    records = _records(transcript)
    usage_by_message = _usage_by_message(records)
    totals = dict.fromkeys(USAGE_FIELDS, 0)
    for usage in usage_by_message.values():
        for field in USAGE_FIELDS:
            totals[field] += usage[field]
    calls = _tool_calls(records)
    reads = Counter(
        target for name, target in calls if name in READ_TOOLS and target
    )
    agent_type = meta.get("agentType")
    description = meta.get("description")
    parent = meta.get("parentAgentId")
    depth = meta.get("spawnDepth")
    if is_root:
        delegation = "root"
    elif "toolUseId" in meta:
        delegation = "spawn"
    else:
        delegation = "fork"
    return AgentNode(
        agent_id=transcript.stem,
        agent_type="ROOT" if is_root else (
            agent_type if isinstance(agent_type, str) else "?"
        ),
        description=description if isinstance(description, str) else "",
        parent_agent_id=parent if isinstance(parent, str) else None,
        spawn_depth=depth if isinstance(depth, int) else None,
        delegation=delegation,
        messages=len(usage_by_message),
        usage=totals,
        tool_calls=len(calls),
        tools=dict(Counter(name for name, _ in calls).most_common()),
        repeat_reads=sum(count - 1 for count in reads.values() if count > 1),
        path=str(transcript),
    )


def _counters(transcripts: list[Path]) -> CounterCheck:
    """Test whether output_tokens carries real totals or a frozen snapshot."""
    messages = 0
    suspicious = 0
    varying = 0
    for transcript in transcripts:
        per_id: dict[str, tuple[set[int], bool]] = {}
        for record in _records(transcript):
            message = _message(record)
            if message is None:
                continue
            usage = message.get("usage")
            message_id = message.get("id")
            if not isinstance(usage, dict) or not isinstance(message_id, str):
                continue
            outputs, has_tool = per_id.setdefault(message_id, (set(), False))
            outputs.add(_int(usage.get("output_tokens")))
            if not has_tool:
                has_tool = any(
                    block.get("type") == "tool_use" for block in _blocks(message)
                )
            per_id[message_id] = (outputs, has_tool)
        for outputs, has_tool in per_id.values():
            messages += 1
            if len(outputs) > 1:
                varying += 1
            if has_tool and max(outputs) <= FROZEN_SNAPSHOT_CEILING:
                suspicious += 1
    share = suspicious / messages if messages else 0.0
    return CounterCheck(
        messages=messages,
        tool_call_messages_at_or_below_ceiling=suspicious,
        share=round(share, 4),
        varying_within_message_id=varying,
        frozen_snapshot_suspected=share > FROZEN_SNAPSHOT_SHARE,
    )


def _duplicate_reads(nodes: list[AgentNode], paths: list[Path]) -> list[
    dict[str, object]
]:
    """Report targets read by more than one agent role in the same run."""
    roles: dict[str, set[str]] = {}
    for node, transcript in zip(nodes, paths):
        for name, target in _tool_calls(_records(transcript)):
            if name not in READ_TOOLS or not target:
                continue
            roles.setdefault(target, set()).add(node["agent_type"])
    shared = [
        {"target": target, "agent_types": sorted(owners)}
        for target, owners in roles.items()
        if len(owners) > 1
    ]
    shared.sort(key=lambda item: -len(item["agent_types"]))
    return shared


def audit(root: Path, *, with_counters: bool) -> tuple[Report, int]:
    """Audit one root transcript and every child beneath it."""
    if not root.is_file():
        raise AuditError(f"root transcript not found: {root}")
    children = sorted((root.parent / root.stem / "subagents").glob("agent-*.jsonl"))
    transcripts = [root, *children]
    nodes = [_node(root, {}, True)]
    nodes.extend(_node(child, _meta(child), False) for child in children)

    by_type: dict[str, dict[str, int]] = {}
    by_delegation: dict[str, dict[str, int]] = {}
    for node in nodes:
        for bucket, key in ((by_type, node["agent_type"]),
                            (by_delegation, node["delegation"])):
            totals = bucket.setdefault(key, dict.fromkeys(USAGE_FIELDS, 0))
            for field in USAGE_FIELDS:
                totals[field] += node["usage"][field]

    uses: set[str] = set()
    results: set[str] = set()
    missing: list[str] = []
    for transcript in transcripts:
        records = _records(transcript)
        uses |= _block_ids(records, "tool_use", "id")
        results |= _block_ids(records, "tool_result", "tool_use_id")
        if records and not _usage_by_message(records):
            has_assistant = any(
                (_message(record) or {}).get("role") == "assistant"
                for record in records
            )
            if has_assistant:
                missing.append(str(transcript))

    counters = _counters(transcripts) if with_counters else None
    disagrees = bool(missing) or bool(counters and counters["frozen_snapshot_suspected"])
    report = Report(
        status="snapshot" if uses - results else "closed",
        root_session_id=root.stem,
        project=root.parent.name,
        transcripts=len(transcripts),
        agents=nodes,
        totals_by_agent_type=by_type,
        totals_by_delegation=by_delegation,
        duplicate_reads_across_agents=_duplicate_reads(nodes, transcripts),
        reconciliation=Reconciliation(
            tool_use_blocks=len(uses),
            tool_result_blocks=len(results),
            unmatched_tool_use=len(uses - results),
            transcripts_without_usage=missing,
        ),
        counters=counters,
    )
    return report, 1 if disagrees else 0


def _build_parser() -> argparse.ArgumentParser:
    """Build the command line parser."""
    parser = argparse.ArgumentParser(
        description="Audit a Claude Code session tree from its JSONL transcripts.",
    )
    parser.add_argument("transcript", type=Path, help="Root <session-id>.jsonl file.")
    parser.add_argument(
        "--counters",
        action="store_true",
        help="Test whether output_tokens carries real totals. Exits 1 when not.",
    )
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    """Run the audit and print its JSON report."""
    args = _build_parser().parse_args(argv)
    try:
        report, code = audit(args.transcript, with_counters=args.counters)
    except AuditError as exc:
        print(f"audit_claude_code: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(report, indent=2, sort_keys=True))
    return code


if __name__ == "__main__":
    sys.exit(main())
