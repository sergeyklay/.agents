#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
import stat
import sys
import tempfile
import time
from collections.abc import Generator
from contextlib import contextmanager
from fcntl import LOCK_EX, LOCK_UN, flock
from importlib import import_module
from pathlib import Path
from typing import Literal, cast

SUPPORTED_FIELDS = {"name", "description"}
SUPPORTED_TEMPLATE_FIELDS = {
    "allowed_skills",
    "disabled_features",
    "model",
    "model_reasoning_effort",
    "skills",
}
SUPPORTED_FEATURES = {"apps", "plugins", "shell_tool"}
SUPPORTED_EFFORTS = {"high", "max", "xhigh"}
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


def load_template(path: Path, skill_names: set[str]) -> dict[str, object]:
    if not path.is_file() or path.is_symlink():
        fail(f"Codex agent template is not a regular file: {path}")
    template = cast(dict[str, object], tomllib.loads(path.read_text(encoding="utf-8")))
    unknown = set(template) - SUPPORTED_TEMPLATE_FIELDS
    if unknown:
        fail(f"{path}: unsupported template field: {sorted(unknown)[0]}")
    for field in ("model", "model_reasoning_effort"):
        if not isinstance(template.get(field), str) or not template[field]:
            fail(f"{path}: {field} must be a non-empty string")
    if template["model_reasoning_effort"] not in SUPPORTED_EFFORTS:
        fail(f"{path}: unsupported model reasoning effort")
    features: object = template.get("disabled_features", [])
    if not isinstance(features, list):
        fail(f"{path}: disabled_features contains an unsupported value")
    for value in cast(list[object], features):
        if not isinstance(value, str) or value not in SUPPORTED_FEATURES:
            fail(f"{path}: disabled_features contains an unsupported value")
    allowed: object = template.get("allowed_skills")
    skills: object = template.get("skills")
    if allowed is not None and skills is not None:
        fail(f"{path}: allowed_skills and skills are mutually exclusive")
    if allowed is not None:
        if not isinstance(allowed, list) or not allowed:
            fail(f"{path}: allowed_skills contains an unsupported value")
        for value in cast(list[object], allowed):
            if not isinstance(value, str) or value not in skill_names:
                fail(f"{path}: allowed_skills contains an unsupported value")
    if skills is not None and skills != "none":
        fail(f"{path}: skills must be none")
    return template


def render(path: Path, template: dict[str, object], skill_names: set[str]) -> bytes:
    name, description, body = parse_agent(path)
    lines = [
        f"name = {json.dumps(name, ensure_ascii=False)}\n"
        f"description = {json.dumps(description, ensure_ascii=False)}\n"
        f"model = {json.dumps(template['model'])}\n"
        f"model_reasoning_effort = {json.dumps(template['model_reasoning_effort'])}\n"
        f"developer_instructions = {json.dumps(body, ensure_ascii=False)}\n"
    ]
    features = cast(list[str], template.get("disabled_features", []))
    if features:
        lines.append("\n[features]\n")
        lines.extend(f"{feature} = false\n" for feature in features)
    allowed = cast(list[str] | None, template.get("allowed_skills"))
    if allowed is not None:
        lines.append("\n[skills.bundled]\nenabled = false\n")
        for skill in sorted(skill_names - set(allowed)):
            lines.append(
                f"\n[[skills.config]]\nname = {json.dumps(skill)}\nenabled = false\n"
            )
    elif template.get("skills") == "none":
        lines.append("\n[skills]\ninclude_instructions = false\n")
    payload = "".join(lines).encode()
    parsed = tomllib.loads(payload.decode())
    if any(
        parsed.get(field) in (None, "")
        for field in (
            "name",
            "description",
            "model",
            "model_reasoning_effort",
            "developer_instructions",
        )
    ):
        fail(f"{path}: rendered role failed validation")
    return payload


def load_manifest(
    path: Path,
) -> tuple[Literal["stable", "pending"], dict[str, set[str]]]:
    if path.is_symlink():
        fail(f"ownership manifest is not a regular file: {path}")
    if not path.exists():
        return "stable", {}
    if not path.is_file():
        fail(f"ownership manifest is not a regular file: {path}")
    manifest: object = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict):
        fail(f"ownership manifest has an unsupported shape: {path}")
    manifest_dict = cast(dict[object, object], manifest)
    if set(manifest_dict) != {"state", "roles"}:
        fail(f"ownership manifest has an unsupported shape: {path}")
    state = manifest_dict["state"]
    if state not in {"stable", "pending"}:
        fail(f"ownership manifest has an unsupported state: {path}")
    roles = manifest_dict["roles"]
    if not isinstance(roles, dict):
        fail(f"ownership manifest roles must be an object: {path}")
    role_dict = cast(dict[object, object], roles)
    result: dict[str, set[str]] = {}
    for name, digests in role_dict.items():
        if (
            not isinstance(name, str)
            or Path(name).name != name
            or not name.endswith(".toml")
            or not isinstance(digests, list)
            or not digests
        ):
            fail(f"ownership manifest contains an invalid role entry: {path}")
        assert isinstance(name, str)
        digest_set: set[str] = set()
        for digest in cast(list[object], digests):
            if (
                not isinstance(digest, str)
                or len(digest) != 64
                or any(char not in "0123456789abcdef" for char in digest)
            ):
                fail(f"ownership manifest contains an invalid digest: {path}")
            assert isinstance(digest, str)
            digest_set.add(digest)
        result[name] = digest_set
    return cast(Literal["stable", "pending"], state), result


def ownership(path: Path, recorded_digests: set[str] | None) -> str:
    if recorded_digests is None:
        return "unrecognized"
    if path.is_symlink() or not path.is_file():
        return "modified"
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return "owned" if digest in recorded_digests else "modified"


def manifest_content(state: str, roles: dict[str, set[str]]) -> bytes:
    return (
        json.dumps(
            {
                "state": state,
                "roles": {name: sorted(digests) for name, digests in roles.items()},
            },
            indent=2,
            sort_keys=True,
        ).encode()
        + b"\n"
    )


def atomic_write(path: Path, content: bytes) -> None:
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


@contextmanager
def transaction_lock(path: Path) -> Generator[None, None, None]:
    if path.is_symlink():
        fail(f"transaction lock is not a regular file: {path}")
    flags = os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW
    descriptor = os.open(path, flags, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            fail(f"transaction lock is not a regular file: {path}")
        flock(descriptor, LOCK_EX)
        yield
    finally:
        flock(descriptor, LOCK_UN)
        os.close(descriptor)


def fail_after(phase: str, index: int) -> None:
    if os.environ.get("AGENTS_INSTALL_FAIL_PHASE") == phase and os.environ.get(
        "AGENTS_INSTALL_FAIL_INDEX"
    ) == str(index):
        fail(f"injected failure during {phase}")


def reconcile(repository: Path, codex_home: Path) -> None:
    sources = sorted((repository / ".agents/agents").glob("*.md"))
    skill_names = {
        path.parent.name for path in (repository / ".agents/skills").glob("*/SKILL.md")
    }
    template_dir = repository / "templates/.codex/agents"
    source_names = {source.stem for source in sources}
    template_names = {path.stem for path in template_dir.glob("*.toml")}
    if source_names != template_names:
        fail("Codex agent templates do not match canonical agents")
    rendered = {
        f"{source.stem}.toml": render(
            source,
            load_template(template_dir / f"{source.stem}.toml", skill_names),
            skill_names,
        )
        for source in sources
    }
    if not rendered:
        fail("no canonical agents found")

    destination = codex_home / "agents"
    manifest_path = codex_home / ".agents-install-state.json"
    _, manifest = load_manifest(manifest_path)
    stale: list[Path] = []
    for path in sorted(destination.glob("*.toml")):
        ownership_state = ownership(path, manifest.get(path.name))
        if path.name in rendered:
            if ownership_state != "owned":
                fail(f"refusing to replace {ownership_state} Codex role: {path}")
        elif ownership_state == "owned":
            stale.append(path)
        elif ownership_state == "modified":
            fail(f"refusing to remove modified Codex role: {path}")
    desired = {
        name: hashlib.sha256(content).hexdigest() for name, content in rendered.items()
    }
    ready = os.environ.get("AGENTS_INSTALL_READY")
    if ready:
        Path(ready).touch()
    release = os.environ.get("AGENTS_INSTALL_RELEASE")
    while release and not Path(release).exists():
        time.sleep(0.01)
    pending = {name: set(digests) for name, digests in manifest.items()}
    for name, digest in desired.items():
        pending.setdefault(name, set()).add(digest)
    atomic_write(manifest_path, manifest_content("pending", pending))

    for index, (name, content) in enumerate(rendered.items(), 1):
        path = destination / name
        atomic_write(path, content)
        fail_after("write", index)
    for index, path in enumerate(stale, 1):
        path.unlink()
        fail_after("remove", index)
    stable = {name: {digest} for name, digest in desired.items()}
    atomic_write(manifest_path, manifest_content("stable", stable))


def install(repository: Path, codex_home: Path) -> None:
    with transaction_lock(codex_home / ".agents-install.lock"):
        reconcile(repository, codex_home)


def main() -> int:
    if len(sys.argv) != 3:
        print(
            f"usage: {Path(sys.argv[0]).name} REPOSITORY DESTINATION", file=sys.stderr
        )
        return 2
    try:
        install(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, UnicodeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
