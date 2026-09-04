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
from typing import TypedDict, cast

USAGE_FIELDS: tuple[str, ...] = (
    "input_tokens",
    "cache_creation_input_tokens",
    "cache_read_input_tokens",
    "output_tokens",
)
READ_TOOLS: tuple[str, ...] = ("Read", "NotebookRead")
TARGET_PATH_KEYS: tuple[str, ...] = ("file_path", "notebook_path", "path")
TARGET_TEXT_KEYS: tuple[str, ...] = ("command", "pattern", "skill", "url")
FROZEN_SNAPSHOT_CEILING = 20
FROZEN_SNAPSHOT_SHARE = 0.25
MAX_TARGET_TEXT = 200


class AgentNode(TypedDict):
    """One transcript in the run, root or child."""

    agent_id: str
    agent_type: str
    description: str
    parent_agent_id: str | None
    spawn_depth: int | None
    delegation: str
    messages: int
    usage: dict[str, int]
    tool_calls: int
    tools: dict[str, int]
    repeat_reads: int
    path: str


class SharedRead(TypedDict):
    """One target pulled into context by more than one agent role."""

    target: str
    agent_types: list[str]


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
    duplicate_reads_across_agents: list[SharedRead]
    reconciliation: Reconciliation
    counters: CounterCheck | None


class AuditError(Exception):
    """Raised when the requested session cannot be audited."""


def _zero_usage() -> dict[str, int]:
    """Return a fresh zeroed usage bucket."""
    return {field: 0 for field in USAGE_FIELDS}


def _records(path: Path) -> list[dict[str, object]]:
    """Return every JSON object in a JSONL transcript, skipping bad lines."""
    try:
        text = path.read_text(errors="replace")
    except OSError as exc:
        raise AuditError(f"cannot read {path}: {exc}") from exc

    records: list[dict[str, object]] = []
    for line in text.splitlines():
        if not line.strip():
            continue
        try:
            parsed: object = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            records.append(cast("dict[str, object]", parsed))
    return records


def _message(record: dict[str, object]) -> dict[str, object] | None:
    """Return the message object of a record, when it carries one."""
    message = record.get("message")
    if isinstance(message, dict):
        return cast("dict[str, object]", message)
    return None


def _blocks(message: dict[str, object]) -> list[dict[str, object]]:
    """Return the content blocks of a message, when content is a list."""
    content = message.get("content")
    if not isinstance(content, list):
        return []
    blocks: list[dict[str, object]] = []
    for block in cast("list[object]", content):
        if isinstance(block, dict):
            blocks.append(cast("dict[str, object]", block))
    return blocks


def _usage(message: dict[str, object]) -> dict[str, object] | None:
    """Return the usage object of a message, when it carries one."""
    usage = message.get("usage")
    if isinstance(usage, dict):
        return cast("dict[str, object]", usage)
    return None


def _int(value: object) -> int:
    """Coerce a JSON number to int, treating anything else as zero."""
    if isinstance(value, bool):
        return 0
    return value if isinstance(value, int) else 0


def _text(value: object) -> str:
    """Return a string value, or the empty string for anything else."""
    return value if isinstance(value, str) else ""


def _target(tool_input: dict[str, object]) -> str:
    """Return a stable identity for what a tool call acted on."""
    for key in TARGET_PATH_KEYS:
        value = tool_input.get(key)
        if isinstance(value, str):
            return value
    for key in TARGET_TEXT_KEYS:
        value = tool_input.get(key)
        if isinstance(value, str):
            return value[:MAX_TARGET_TEXT]
    return ""


def _usage_by_message(records: list[dict[str, object]]) -> dict[str, dict[str, int]]:
    """Reduce usage per message id by maximum, per this adapter's contract."""
    seen: dict[str, dict[str, int]] = {}
    for record in records:
        message = _message(record)
        if message is None:
            continue
        usage = _usage(message)
        message_id = message.get("id")
        if usage is None or not isinstance(message_id, str):
            continue
        current = seen.setdefault(message_id, _zero_usage())
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
            tool_input = block.get("input")
            narrowed = (
                cast("dict[str, object]", tool_input)
                if isinstance(tool_input, dict)
                else {}
            )
            calls.append((_text(block.get("name")) or "?", _target(narrowed)))
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
    except (OSError, json.JSONDecodeError):
        return {}
    if isinstance(parsed, dict):
        return cast("dict[str, object]", parsed)
    return {}


def _delegation(meta: dict[str, object], is_root: bool) -> str:
    """Classify how this transcript came to exist."""
    if is_root:
        return "root"
    return "spawn" if "toolUseId" in meta else "fork"


def _node(transcript: Path, meta: dict[str, object], is_root: bool) -> AgentNode:
    """Build one node of the delegation forest from a transcript."""
    records = _records(transcript)
    usage_by_message = _usage_by_message(records)
    totals = _zero_usage()
    for usage in usage_by_message.values():
        for field in USAGE_FIELDS:
            totals[field] += usage[field]

    calls = _tool_calls(records)
    reads: Counter[str] = Counter(
        target for name, target in calls if name in READ_TOOLS and target
    )
    names: Counter[str] = Counter(name for name, _ in calls)
    parent = meta.get("parentAgentId")
    depth = meta.get("spawnDepth")
    agent_type = _text(meta.get("agentType")) or "?"
    return AgentNode(
        agent_id=transcript.stem,
        agent_type="ROOT" if is_root else agent_type,
        description=_text(meta.get("description")),
        parent_agent_id=parent if isinstance(parent, str) else None,
        spawn_depth=depth if isinstance(depth, int) else None,
        delegation=_delegation(meta, is_root),
        messages=len(usage_by_message),
        usage=totals,
        tool_calls=len(calls),
        tools=dict(names.most_common()),
        repeat_reads=sum(count - 1 for count in reads.values() if count > 1),
        path=str(transcript),
    )


def _counters(transcripts: list[Path]) -> CounterCheck:
    """Test whether output_tokens carries real totals or a frozen snapshot."""
    messages = 0
    suspicious = 0
    varying = 0
    for transcript in transcripts:
        outputs: dict[str, set[int]] = {}
        tool_bearing: set[str] = set()
        for record in _records(transcript):
            message = _message(record)
            if message is None:
                continue
            usage = _usage(message)
            message_id = message.get("id")
            if usage is None or not isinstance(message_id, str):
                continue
            outputs.setdefault(message_id, set()).add(_int(usage.get("output_tokens")))
            if any(block.get("type") == "tool_use" for block in _blocks(message)):
                tool_bearing.add(message_id)
        for message_id, values in outputs.items():
            messages += 1
            if len(values) > 1:
                varying += 1
            if message_id in tool_bearing and max(values) <= FROZEN_SNAPSHOT_CEILING:
                suspicious += 1
    share = suspicious / messages if messages else 0.0
    return CounterCheck(
        messages=messages,
        tool_call_messages_at_or_below_ceiling=suspicious,
        share=round(share, 4),
        varying_within_message_id=varying,
        frozen_snapshot_suspected=share > FROZEN_SNAPSHOT_SHARE,
    )


def _duplicate_reads(nodes: list[AgentNode], paths: list[Path]) -> list[SharedRead]:
    """Report targets read by more than one agent role in the same run."""
    roles: dict[str, set[str]] = {}
    for node, transcript in zip(nodes, paths):
        for name, target in _tool_calls(_records(transcript)):
            if name not in READ_TOOLS or not target:
                continue
            roles.setdefault(target, set()).add(node["agent_type"])
    shared = [
        SharedRead(target=target, agent_types=sorted(owners))
        for target, owners in roles.items()
        if len(owners) > 1
    ]
    shared.sort(key=lambda item: (-len(item["agent_types"]), item["target"]))
    return shared


def _accumulate(
    bucket: dict[str, dict[str, int]], key: str, usage: dict[str, int]
) -> None:
    """Add one node's usage into a keyed total."""
    totals = bucket.setdefault(key, _zero_usage())
    for field in USAGE_FIELDS:
        totals[field] += usage[field]


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
        _accumulate(by_type, node["agent_type"], node["usage"])
        _accumulate(by_delegation, node["delegation"], node["usage"])

    uses: set[str] = set()
    results: set[str] = set()
    missing: list[str] = []
    for transcript in transcripts:
        records = _records(transcript)
        uses |= _block_ids(records, "tool_use", "id")
        results |= _block_ids(records, "tool_result", "tool_use_id")
        if not records or _usage_by_message(records):
            continue
        for record in records:
            message = _message(record)
            if message is not None and message.get("role") == "assistant":
                missing.append(str(transcript))
                break

    counters = _counters(transcripts) if with_counters else None
    disagrees = bool(missing) or (
        counters is not None and counters["frozen_snapshot_suspected"]
    )
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


def main(argv: list[str] | None = None) -> int:
    """Run the audit and print its JSON report."""
    args = _build_parser().parse_args(argv)
    try:
        report, code = audit(
            cast(Path, args.transcript), with_counters=cast(bool, args.counters)
        )
    except AuditError as exc:
        print(f"audit_claude_code: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(report, indent=2, sort_keys=True))
    return code


if __name__ == "__main__":
    sys.exit(main())
