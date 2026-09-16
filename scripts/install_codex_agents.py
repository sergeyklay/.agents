#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
import sys
import tempfile
from importlib import import_module
from pathlib import Path
from typing import cast

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
    return payload


def load_manifest(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    if path.is_symlink() or not path.is_file():
        fail(f"ownership manifest is not a regular file: {path}")
    manifest: object = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict):
        fail(f"ownership manifest has an unsupported shape: {path}")
    manifest_dict = cast(dict[object, object], manifest)
    if list(manifest_dict) != ["roles"]:
        fail(f"ownership manifest has an unsupported shape: {path}")
    roles = manifest_dict["roles"]
    if not isinstance(roles, dict):
        fail(f"ownership manifest roles must be an object: {path}")
    role_dict = cast(dict[object, object], roles)
    result: dict[str, str] = {}
    for name, digest in role_dict.items():
        if (
            not isinstance(name, str)
            or Path(name).name != name
            or not name.endswith(".toml")
            or not isinstance(digest, str)
            or len(digest) != 64
            or any(char not in "0123456789abcdef" for char in digest)
        ):
            fail(f"ownership manifest contains an invalid role entry: {path}")
        assert isinstance(name, str)
        assert isinstance(digest, str)
        result[name] = digest
    return result


def ownership(path: Path, recorded_digest: str | None) -> str:
    if recorded_digest is None:
        return "unrecognized"
    if path.is_symlink() or not path.is_file():
        return "modified"
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return "owned" if digest == recorded_digest else "modified"


def atomic_write(path: Path, content: bytes) -> None:
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def install(repository: Path, codex_home: Path) -> list[tuple[str, Path]]:
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

    destination = codex_home / "agents"
    manifest_path = codex_home / ".agents-install-state.json"
    manifest = load_manifest(manifest_path)
    stale: list[Path] = []
    for path in sorted(destination.glob("*.toml")):
        state = ownership(path, manifest.get(path.name))
        if path.name in rendered:
            if state != "owned":
                fail(f"refusing to replace {state} Codex role: {path}")
        elif state == "owned":
            stale.append(path)
        elif state == "modified":
            fail(f"refusing to remove modified Codex role: {path}")
    missing_recorded = set(manifest) - {
        path.name for path in destination.glob("*.toml")
    }
    if missing_recorded:
        fail(
            f"ownership manifest names a missing Codex role: {sorted(missing_recorded)[0]}"
        )

    operations: list[tuple[str, Path]] = []
    for name, content in rendered.items():
        path = destination / name
        atomic_write(path, content)
        operations.append(("updated", path))
    for path in stale:
        path.unlink()
        operations.append(("removed", path))
    manifest_content = (
        json.dumps(
            {
                "roles": {
                    name: hashlib.sha256(content).hexdigest()
                    for name, content in rendered.items()
                }
            },
            indent=2,
            sort_keys=True,
        ).encode()
        + b"\n"
    )
    atomic_write(manifest_path, manifest_content)
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
