#!/usr/bin/env python3

from __future__ import annotations

import copy
import datetime as dt
import importlib
import json
import math
import re
import sys
from pathlib import Path
from typing import Any, BinaryIO, Protocol, cast


class TomlReader(Protocol):
    def load(self, stream: BinaryIO) -> dict[str, Any]: ...


tomllib = cast(TomlReader, importlib.import_module("tomllib"))

BARE_KEY = re.compile(r"[A-Za-z0-9_-]+")


def merge(host: dict[str, Any], repository: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(host)
    for key, repository_value in repository.items():
        host_value = result.get(key)
        if isinstance(host_value, dict) and isinstance(repository_value, dict):
            result[key] = merge(
                cast(dict[str, Any], host_value),
                cast(dict[str, Any], repository_value),
            )
        else:
            result[key] = copy.deepcopy(repository_value)
    return result


def format_key(key: str) -> str:
    if BARE_KEY.fullmatch(key):
        return key
    return json.dumps(key, ensure_ascii=False)


def format_value(value: Any) -> str:
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if math.isnan(value):
            return "nan"
        if math.isinf(value):
            return "inf" if value > 0 else "-inf"
        return repr(value)
    if isinstance(value, (dt.datetime, dt.date, dt.time)):
        return value.isoformat()
    if isinstance(value, list):
        items = cast(list[Any], value)
        return "[" + ", ".join(format_value(item) for item in items) + "]"
    if isinstance(value, dict):
        table = cast(dict[str, Any], value)
        fields = ", ".join(
            f"{format_key(key)} = {format_value(item)}" for key, item in table.items()
        )
        return "{ " + fields + " }"
    raise TypeError(f"unsupported TOML value: {type(value).__name__}")


def is_array_of_tables(value: Any) -> bool:
    items = cast(list[Any], value) if isinstance(value, list) else []
    return bool(items) and all(isinstance(item, dict) for item in items)


def format_path(path: tuple[str, ...]) -> str:
    return ".".join(format_key(part) for part in path)


def append_table(
    lines: list[str],
    path: tuple[str, ...],
    table: dict[str, Any],
    *,
    array: bool = False,
) -> None:
    if path:
        brackets = "[[{}]]" if array else "[{}]"
        lines.append(brackets.format(format_path(path)))

    for key, value in table.items():
        if not isinstance(value, dict) and not is_array_of_tables(value):
            lines.append(f"{format_key(key)} = {format_value(value)}")

    for key, value in table.items():
        if isinstance(value, dict):
            if lines and lines[-1]:
                lines.append("")
            append_table(lines, (*path, key), cast(dict[str, Any], value))
        elif is_array_of_tables(value):
            for item in value:
                if lines and lines[-1]:
                    lines.append("")
                append_table(lines, (*path, key), item, array=True)


def dumps(config: dict[str, Any]) -> str:
    lines: list[str] = []
    append_table(lines, (), config)
    return "\n".join(lines).rstrip() + "\n"


def load(path: Path) -> dict[str, Any]:
    with path.open("rb") as config_file:
        return tomllib.load(config_file)


def main() -> int:
    if len(sys.argv) != 4:
        print(
            f"usage: {Path(sys.argv[0]).name} HOST REPOSITORY OUTPUT", file=sys.stderr
        )
        return 2

    host_path, repository_path, output_path = map(Path, sys.argv[1:])
    merged = merge(load(host_path), load(repository_path))
    output_path.write_text(dumps(merged), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
