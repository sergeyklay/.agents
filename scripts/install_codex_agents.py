#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import tempfile
from importlib import import_module
from pathlib import Path

OWNER_PREFIX = "# .agents-owner: "
OWNER_PATTERN = re.compile(r"# \.agents-owner: ([0-9a-f]{64})\n")
SUPPORTED_FIELDS = {"name", "description"}
tomllib = import_module("tomllib")


def fail(message: str) -> None:
    raise ValueError(message)


def scalar(value: str, label: str) -> str:
    value = value.strip()
    if not value:
        fail(f"{label} cannot be blank")
    if value.startswith('"'):
        try:
            parsed_value: object = json.loads(value)
        except json.JSONDecodeError as error:
            fail(f"{label} has invalid quoting: {error.msg}")
            raise AssertionError from error
        if not isinstance(parsed_value, str):
            raise ValueError(f"{label} must be a string")
        return parsed_value
    if value.startswith("'"):
        if len(value) < 2 or not value.endswith("'"):
            fail(f"{label} has invalid quoting")
        return value[1:-1].replace("''", "'")
    return value


def reject_controls(value: str, label: str, *, multiline: bool = False) -> None:
    allowed: set[str] = {"\n", "\t"} if multiline else set()
    if any(
        (ord(char) < 32 and char not in allowed) or ord(char) == 127 for char in value
    ):
        fail(f"{label} contains a control character")


def parse_agent(path: Path) -> tuple[str, str, str]:
    raw = path.read_text(encoding="utf-8")
    lines = raw.splitlines(keepends=True)
    if not lines or lines[0].rstrip("\r\n") != "---":
        fail(f"{path}: frontmatter is required")
    closing = next(
        (
            index
            for index, line in enumerate(lines[1:], 1)
            if line.rstrip("\r\n") == "---"
        ),
        None,
    )
    if closing is None:
        raise ValueError(f"{path}: frontmatter is not closed")

    fields: dict[str, str] = {}
    for line in lines[1:closing]:
        if not line.strip():
            continue
        if line[:1].isspace() or ":" not in line:
            fail(f"{path}: unsupported frontmatter syntax")
        key, value = line.split(":", 1)
        if key not in SUPPORTED_FIELDS:
            fail(f"{path}: unsupported frontmatter field: {key}")
        if key in fields:
            fail(f"{path}: duplicate frontmatter field: {key}")
        fields[key] = scalar(value, f"{path}: {key}")

    missing = SUPPORTED_FIELDS - fields.keys()
    if missing:
        fail(f"{path}: missing required frontmatter field: {sorted(missing)[0]}")
    body = "".join(lines[closing + 1 :])
    if not body.strip():
        fail(f"{path}: developer instructions cannot be blank")

    name = fields["name"]
    description = fields["description"]
    reject_controls(name, f"{path}: name")
    reject_controls(description, f"{path}: description")
    reject_controls(body, f"{path}: developer instructions", multiline=True)
    if name != path.stem:
        fail(f"{path}: name must match the file name")
    return name, description, body


def render(path: Path) -> bytes:
    name, description, body = parse_agent(path)
    payload = (
        f"name = {json.dumps(name, ensure_ascii=False)}\n"
        f"description = {json.dumps(description, ensure_ascii=False)}\n"
        f"developer_instructions = {json.dumps(body, ensure_ascii=False)}\n"
    ).encode()
    parsed = tomllib.loads(payload.decode())
    expected = {
        "name": name,
        "description": description,
        "developer_instructions": body,
    }
    if parsed != expected:
        fail(f"{path}: rendered role failed validation")
    digest = hashlib.sha256(payload).hexdigest()
    return f"{OWNER_PREFIX}{digest}\n".encode() + payload


def ownership(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        return "unrecognized"
    content = path.read_bytes()
    line, separator, payload = content.partition(b"\n")
    if not separator:
        return "unrecognized"
    match = OWNER_PATTERN.fullmatch((line + separator).decode(errors="replace"))
    if not match:
        return "unrecognized"
    digest = hashlib.sha256(payload).hexdigest()
    return "owned" if digest == match.group(1) else "modified"


def atomic_write(path: Path, content: bytes) -> None:
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def install(repository: Path, destination: Path) -> list[tuple[str, Path]]:
    templates = [
        path
        for path in (repository / "templates/.codex").glob("agents*")
        if path.is_file() or (path.is_dir() and any(path.iterdir()))
    ]
    if templates:
        fail(f"unsupported Codex agent template: {templates[0]}")

    sources = sorted((repository / ".agents/agents").glob("*.md"))
    rendered = {f"{source.stem}.toml": render(source) for source in sources}
    if not rendered:
        fail("no canonical agents found")

    stale: list[Path] = []
    for path in sorted(destination.glob("*.toml")):
        state = ownership(path)
        if path.name in rendered:
            if state != "owned":
                fail(f"refusing to replace {state} Codex role: {path}")
        elif state == "owned":
            stale.append(path)
        elif state == "modified":
            fail(f"refusing to remove modified Codex role: {path}")

    operations: list[tuple[str, Path]] = []
    for name, content in rendered.items():
        path = destination / name
        atomic_write(path, content)
        operations.append(("updated", path))
    for path in stale:
        path.unlink()
        operations.append(("removed", path))
    return operations


def main() -> int:
    if len(sys.argv) != 3:
        print(
            f"usage: {Path(sys.argv[0]).name} REPOSITORY DESTINATION", file=sys.stderr
        )
        return 2
    try:
        operations = install(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, UnicodeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    for action, path in operations:
        print(f"{action}\t{path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
