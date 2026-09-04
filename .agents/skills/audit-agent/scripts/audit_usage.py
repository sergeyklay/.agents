#!/usr/bin/env python3
# Copyright 2026 Serghei Iakovlev
# SPDX-License-Identifier: Apache-2.0
"""Aggregate cumulative per-message counters from JSON event streams.

Use this only after observing that several records share one message id,
counter values are cumulative snapshots rather than per-event deltas, and
the terminal record equals each per-message maximum. The reduction is the
maximum of each field, grouped by (file, id).

No schema is assumed: every path is a caller argument, discoverable with
--probe. Paths are dot-separated, for example "message.usage".

Exit: 0 terminal evidence verified every group, 1 evidence missing or a
maximum disagreed with its terminal record, 2 usage error.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections.abc import Iterator
from pathlib import Path
from typing import TypedDict, Union, cast

MAX_PROBE_DEPTH = 3
MAX_PROBE_CANDIDATES = 10
MAX_DISTINCT_TRACKED = 5000
MAX_MISMATCH_EXAMPLES = 5
MISSING = object()

GroupKey = Union[str, tuple[str, str]]


class IdCandidate(TypedDict):
    path: str
    records: int
    distinct_values: int
    records_per_value: float


class UsageCandidate(TypedDict):
    path: str
    records: int
    fields: list[str]
    other_fields: list[str]


class TerminalCandidate(TypedDict):
    path: str
    set_on: int
    null_on: int
    absent_on: int


class ProbeReport(TypedDict):
    mode: str
    files: list[str]
    records_sampled: int
    id_candidates: list[IdCandidate]
    usage_candidates: list[UsageCandidate]
    terminal_marker_candidates: list[TerminalCandidate]
    usable: bool


class FileTotals(TypedDict):
    file: str
    records: int
    usage_records: int
    messages: int
    max_records_per_message: int
    by_message_max: dict[str, int | float]


class AggregateTotals(TypedDict):
    by_message_max: dict[str, int | float]
    by_naive_record_sum: dict[str, int | float]
    naive_inflation: dict[str, float]


class TerminalCheck(TypedDict):
    groups_checked: int
    groups_without_terminal_record: int
    groups_with_invalid_terminal_marker: int
    mismatched_groups: int
    examples: list[dict[str, object]]


class AggregateReport(TypedDict):
    mode: str
    id_path: str
    usage_path: str
    usage_fields: list[str] | None
    stop_path: str | None
    stop_predicate: str | dict[str, object]
    files: list[FileTotals]
    totals: AggregateTotals
    terminal_check: TerminalCheck | None
    verified: bool


class LoadError(Exception):
    pass


def _counter(value: object) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    return number if math.isfinite(number) and number >= 0 else None


def _plain(value: float) -> int | float:
    return int(value) if float(value).is_integer() else value


def _dig(record: object, path: str) -> object:
    current: object = record
    for part in path.split("."):
        if not isinstance(current, dict) or part not in current:
            return MISSING
        current = cast(dict[str, object], current)[part]
    return current


def _same_json_scalar(value: object, expected: object) -> bool:
    if isinstance(value, bool) or isinstance(expected, bool):
        return type(value) is type(expected) and value == expected
    if isinstance(value, (int, float)) and isinstance(expected, (int, float)):
        return value == expected
    return type(value) is type(expected) and value == expected


def _group_key(raw_id: object) -> GroupKey:
    if isinstance(raw_id, str):
        return raw_id
    return (type(raw_id).__name__, json.dumps(raw_id, default=str))


def _key_display(key: GroupKey) -> str:
    return key if isinstance(key, str) else f"{key[0]}:{key[1]}"


def _numbers(
    mapping: dict[str, object], fields: list[str] | None, label: str
) -> dict[str, float]:
    selected = fields or list(mapping)
    numbers: dict[str, float] = {}
    invalid: list[str] = []
    for field in selected:
        value = _dig(mapping, field)
        number = _counter(value)
        if number is None:
            invalid.append(field)
        else:
            numbers[field] = number
    if invalid:
        raise LoadError(
            f"{label} has missing or invalid numeric fields: {', '.join(invalid)}"
        )
    return numbers


def _field_kinds(mapping: dict[str, object]) -> tuple[set[str], set[str]]:
    numeric: set[str] = set()
    other: set[str] = set()
    for key, value in mapping.items():
        if _counter(value) is None:
            other.add(key)
        else:
            numeric.add(key)
    return numeric, other


def _load(path: Path) -> list[dict[str, object]]:
    """Parse JSON-lines or a single JSON array."""
    try:
        if str(path) == "-":
            text = sys.stdin.read()
        else:
            text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise LoadError(f"cannot read {path}: {exc}") from exc

    records: list[dict[str, object]] = []
    if text.lstrip().startswith("["):
        try:
            doc: object = json.loads(text)
        except json.JSONDecodeError as exc:
            raise LoadError(f"cannot parse {path}: {exc}") from exc
        if isinstance(doc, list):
            for index, item in enumerate(cast(list[object], doc)):
                if not isinstance(item, dict):
                    raise LoadError(f"{path}: array item {index} is not an object")
                records.append(cast(dict[str, object], item))
        return records

    for line_number, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            parsed: object = json.loads(line)
        except json.JSONDecodeError as exc:
            raise LoadError(f"cannot parse {path}:{line_number}: {exc.msg}") from exc
        if not isinstance(parsed, dict):
            raise LoadError(f"{path}:{line_number}: record is not an object")
        records.append(cast(dict[str, object], parsed))
    return records


def _walk(value: object, prefix: str, depth: int) -> Iterator[tuple[str, object]]:
    if depth > MAX_PROBE_DEPTH or not isinstance(value, dict):
        return
    for key, item in cast(dict[str, object], value).items():
        path = f"{prefix}.{key}" if prefix else key
        yield path, item
        yield from _walk(item, path, depth + 1)


def probe(paths: list[Path], limit: int) -> ProbeReport:
    seen: dict[str, int] = {}
    distinct: dict[str, set[str]] = {}
    usage_hits: dict[str, int] = {}
    usage_fields: dict[str, set[str]] = {}
    usage_other_fields: dict[str, set[str]] = {}
    nulls: dict[str, int] = {}
    non_nulls: dict[str, int] = {}
    sampled = 0

    for path in paths:
        for record in _load(path)[:limit]:
            sampled += 1
            for key, value in _walk(record, "", 0):
                seen[key] = seen.get(key, 0) + 1
                if value is None:
                    nulls[key] = nulls.get(key, 0) + 1
                    continue
                non_nulls[key] = non_nulls.get(key, 0) + 1
                if isinstance(value, (str, int)) and not isinstance(value, bool):
                    bucket = distinct.setdefault(key, set())
                    if len(bucket) < MAX_DISTINCT_TRACKED:
                        bucket.add(str(value))
                elif isinstance(value, dict):
                    fields, other = _field_kinds(cast(dict[str, object], value))
                    if fields:
                        usage_hits[key] = usage_hits.get(key, 0) + 1
                        usage_fields.setdefault(key, set()).update(fields)
                        usage_other_fields.setdefault(key, set()).update(other)

    floor = max(sampled // 2, 1)
    ids = sorted((-seen[k], k, len(distinct[k])) for k in distinct if seen[k] >= floor)
    usages = sorted((-count, k) for k, count in usage_hits.items())
    stops = sorted(
        (count, key) for key, count in non_nulls.items() if 0 < count < sampled
    )

    id_candidates: list[IdCandidate] = [
        IdCandidate(
            path=key,
            records=-neg_records,
            distinct_values=values,
            records_per_value=round(-neg_records / max(values, 1), 2),
        )
        for neg_records, key, values in ids[:MAX_PROBE_CANDIDATES]
    ]
    usage_candidates: list[UsageCandidate] = [
        UsageCandidate(
            path=key,
            records=-neg_records,
            fields=sorted(usage_fields[key]),
            other_fields=sorted(usage_other_fields.get(key, set())),
        )
        for neg_records, key in usages[:MAX_PROBE_CANDIDATES]
    ]
    terminal_candidates: list[TerminalCandidate] = [
        TerminalCandidate(
            path=key,
            set_on=set_on,
            null_on=nulls.get(key, 0),
            absent_on=sampled - seen[key],
        )
        for set_on, key in stops[:MAX_PROBE_CANDIDATES]
    ]
    return {
        "mode": "probe",
        "files": [str(p) for p in paths],
        "records_sampled": sampled,
        "id_candidates": id_candidates,
        "usage_candidates": usage_candidates,
        "terminal_marker_candidates": terminal_candidates,
        "usable": sampled > 0 and bool(ids) and bool(usages),
    }


def aggregate(
    paths: list[Path],
    id_path: str,
    usage_path: str,
    stop_path: str | None,
    usage_fields: list[str] | None = None,
    stop_value: object = MISSING,
) -> tuple[AggregateReport, bool]:
    """Reduce usage by maximum per (file, id) and cross-check the reduction."""
    files: list[FileTotals] = []
    grand_max: dict[str, float] = {}
    grand_sum: dict[str, float] = {}
    examples: list[dict[str, object]] = []
    checked = 0
    without_terminal = 0
    invalid_terminal = 0
    mismatched = 0
    parsed_records = 0

    for path in paths:
        maxima: dict[GroupKey, dict[str, float]] = {}
        last_usage: dict[GroupKey, dict[str, float]] = {}
        marker_values: dict[GroupKey, list[object]] = {}
        counts: dict[GroupKey, int] = {}
        file_sum: dict[str, float] = {}
        usage_records = 0

        records = _load(path)
        parsed_records += len(records)
        for record in records:
            usage = _dig(record, usage_path)
            if not isinstance(usage, dict):
                continue
            numbers = _numbers(
                cast(dict[str, object], usage),
                usage_fields,
                f"{path}: usage object {usage_path}",
            )
            if not numbers:
                continue
            raw_id = _dig(record, id_path)
            if raw_id is MISSING or raw_id is None:
                raise LoadError(f"{path}: usage record has no id at {id_path}")
            key = _group_key(raw_id)
            usage_records += 1
            counts[key] = counts.get(key, 0) + 1
            bucket = maxima.setdefault(key, {})
            for field, number in numbers.items():
                bucket[field] = max(bucket.get(field, number), number)
                file_sum[field] = file_sum.get(field, 0.0) + number
            last_usage[key] = numbers
            if stop_path is not None:
                marker_values.setdefault(key, []).append(_dig(record, stop_path))

        file_max: dict[str, float] = {}
        for bucket in maxima.values():
            for field, number in bucket.items():
                file_max[field] = file_max.get(field, 0.0) + number
        for field, number in file_max.items():
            grand_max[field] = grand_max.get(field, 0.0) + number
        for field, number in file_sum.items():
            grand_sum[field] = grand_sum.get(field, 0.0) + number

        if stop_path is not None:
            for key, bucket in maxima.items():
                values = marker_values[key]
                if stop_value is MISSING:
                    positions = [
                        index
                        for index, value in enumerate(values)
                        if isinstance(value, str) and bool(value)
                    ]
                    valid_prefix = all(
                        value is MISSING or value is None for value in values[:-1]
                    )
                else:
                    positions = [
                        index
                        for index, value in enumerate(values)
                        if _same_json_scalar(value, stop_value)
                    ]
                    valid_prefix = True
                if not positions:
                    without_terminal += 1
                    continue
                if positions != [len(values) - 1] or not valid_prefix:
                    invalid_terminal += 1
                    if len(examples) < MAX_MISMATCH_EXAMPLES:
                        examples.append(
                            {
                                "file": str(path),
                                "id": _key_display(key),
                                "issue": "terminal marker is not unique on the final usage record",
                            }
                        )
                    continue
                final = last_usage[key]
                checked += 1
                differing = {f: v for f, v in bucket.items() if final.get(f) != v}
                if not differing:
                    continue
                mismatched += 1
                for field, number in differing.items():
                    if len(examples) >= MAX_MISMATCH_EXAMPLES:
                        break
                    got = final.get(field)
                    examples.append(
                        {
                            "file": str(path),
                            "id": _key_display(key),
                            "field": field,
                            "max": _plain(number),
                            "terminal": None if got is None else _plain(got),
                        }
                    )

        files.append(
            {
                "file": str(path),
                "records": len(records),
                "usage_records": usage_records,
                "messages": len(maxima),
                "max_records_per_message": max(counts.values(), default=0),
                "by_message_max": {f: _plain(v) for f, v in sorted(file_max.items())},
            }
        )

    if parsed_records == 0:
        raise LoadError("no parsable record in the given files")

    verified = (
        stop_path is not None
        and checked > 0
        and without_terminal == 0
        and invalid_terminal == 0
        and mismatched == 0
    )
    report: AggregateReport = {
        "mode": "aggregate",
        "id_path": id_path,
        "usage_path": usage_path,
        "usage_fields": usage_fields,
        "stop_path": stop_path,
        "stop_predicate": (
            "final nonempty string after only null or missing values"
            if stop_value is MISSING
            else {"equals": stop_value}
        ),
        "files": files,
        "totals": {
            "by_message_max": {f: _plain(v) for f, v in sorted(grand_max.items())},
            "by_naive_record_sum": {f: _plain(v) for f, v in sorted(grand_sum.items())},
            "naive_inflation": {
                f: round(grand_sum[f] / grand_max[f], 3)
                for f in sorted(grand_max)
                if grand_max[f]
            },
        },
        "terminal_check": None
        if stop_path is None
        else TerminalCheck(
            groups_checked=checked,
            groups_without_terminal_record=without_terminal,
            groups_with_invalid_terminal_marker=invalid_terminal,
            mismatched_groups=mismatched,
            examples=examples,
        ),
        "verified": verified,
    }
    return report, not verified


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="audit_usage.py",
        description="Aggregate per-message usage counters from agent run logs.",
    )
    parser.add_argument("files", type=Path, nargs="+", help="Log files to read.")
    parser.add_argument(
        "--probe",
        action="store_true",
        help="Report candidate id, usage and terminal-marker paths, then exit.",
    )
    parser.add_argument("--id-path", help="Dot path to the message id.")
    parser.add_argument("--usage-path", help="Dot path to the usage object.")
    parser.add_argument(
        "--usage-field",
        action="append",
        dest="usage_fields",
        help=(
            "Numeric field path relative to the usage object; repeat to exclude "
            "metadata or select nested counters."
        ),
    )
    parser.add_argument(
        "--stop-path",
        help="Dot path to the terminal marker used to cross-check the reduction.",
    )
    parser.add_argument(
        "--stop-value",
        help=(
            "JSON literal required for boolean, numeric, or status markers, for "
            "example true or '\"completed\"'. Without it, the marker must be "
            "null/missing until a final nonempty string."
        ),
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=400,
        help="Records sampled per file in --probe mode (default: 400).",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    files = cast(list[Path], args.files)
    try:
        if cast(bool, args.probe):
            report = probe(files, cast(int, args.limit))
            failed = not report["usable"]
        else:
            id_path = cast("str | None", args.id_path)
            usage_path = cast("str | None", args.usage_path)
            if not id_path or not usage_path:
                print(
                    "--id-path and --usage-path are required without --probe",
                    file=sys.stderr,
                )
                return 2
            stop_path = cast("str | None", args.stop_path)
            raw_stop_value = cast("str | None", args.stop_value)
            if raw_stop_value is not None and stop_path is None:
                print("--stop-value requires --stop-path", file=sys.stderr)
                return 2
            stop_value: object = MISSING
            if raw_stop_value is not None:
                try:
                    stop_value = json.loads(raw_stop_value)
                except json.JSONDecodeError as exc:
                    print(f"--stop-value must be JSON: {exc.msg}", file=sys.stderr)
                    return 2
                if isinstance(stop_value, (dict, list)):
                    print("--stop-value must be a JSON scalar", file=sys.stderr)
                    return 2
            report, failed = aggregate(
                files,
                id_path,
                usage_path,
                stop_path,
                cast("list[str] | None", args.usage_fields),
                stop_value,
            )
    except LoadError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    print(json.dumps(report, indent=2, sort_keys=False))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
