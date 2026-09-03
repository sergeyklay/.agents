#!/usr/bin/env python3
"""Semantic audit of a Dependabot config against the repository's real manifests.

Schema validation proves the file parses and its keys are spelled correctly. It
cannot tell that a group pattern matches nothing, or that two groups claim the
same package. This script does that half: it resolves every `patterns`,
`exclude-patterns` and `ignore.dependency-name` entry against the dependency
names the repository actually declares.

Findings:
  dead-pattern        a patterns entry matching zero declared dependencies
  dead-exclude        an exclude-patterns entry excluding nothing its group matched
  dead-ignore         an ignore.dependency-name matching zero declared dependencies
  double-claim        one dependency claimed by two groups with overlapping scope
  missing-directory   an update entry whose directory does not exist
  missing-manifest    an update entry whose ecosystem manifest is absent
  ungrouped           (info) declared dependency no group claims

Exit codes: 0 clean or informational only, 1 findings present, 2 usage or parse error.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import re
import sys
from pathlib import Path
from typing import Callable, Optional, TypedDict, cast

NPM_DEP_KEYS = (
    "dependencies",
    "devDependencies",
    "optionalDependencies",
    "peerDependencies",
)

USES_RE = re.compile(r"^\s*-?\s*uses:\s*['\"]?([^'\"\s]+)")
FROM_RE = re.compile(r"^\s*FROM\s+(.*)$", re.IGNORECASE)
GOMOD_REQUIRE_BLOCK = re.compile(r"^\s*require\s*\($")
GOMOD_REQUIRE_LINE = re.compile(r"^\s*require\s+(\S+)")


ObjectMapping = dict[object, object]
Resolver = Callable[[Path], tuple[list[str], Optional[str]]]


class GroupSpec(TypedDict):
    patterns: list[str]
    excludes: list[str]
    applies_to: str
    update_types: list[str]


class UpdateSpec(TypedDict):
    ecosystem: str
    directory: str | None
    directories: list[str]
    groups: dict[str, GroupSpec]
    ignored: list[str]


def require_mapping(value: object, context: str) -> ObjectMapping:
    if not isinstance(value, dict):
        raise ValueError(f"{context} must be a mapping")
    return cast(ObjectMapping, value)


def require_list(value: object, context: str) -> list[object]:
    if not isinstance(value, list):
        raise ValueError(f"{context} must be a list")
    return cast(list[object], value)


def string_list(value: object | None, context: str) -> list[str]:
    if value is None:
        return []
    result: list[str] = []
    for item in require_list(value, context):
        if not isinstance(item, str):
            raise ValueError(f"{context} entries must be strings")
        result.append(item)
    return result


def optional_string(
    mapping: ObjectMapping, key: str, context: str, default: str
) -> str:
    value = mapping.get(key)
    if value is None:
        return default
    if not isinstance(value, str):
        raise ValueError(f"{context}.{key} must be a string")
    return value


def parse_group(value: object, context: str) -> GroupSpec:
    mapping = require_mapping(value, context)
    return {
        "patterns": string_list(mapping.get("patterns"), f"{context}.patterns"),
        "excludes": string_list(
            mapping.get("exclude-patterns"), f"{context}.exclude-patterns"
        ),
        "applies_to": optional_string(
            mapping, "applies-to", context, "version-updates"
        ),
        "update_types": string_list(
            mapping.get("update-types"), f"{context}.update-types"
        ),
    }


def parse_update(value: object, index: int) -> UpdateSpec:
    context = f"updates[{index}]"
    mapping = require_mapping(value, context)

    directory = mapping.get("directory")
    if directory is not None and not isinstance(directory, str):
        raise ValueError(f"{context}.directory must be a string")

    groups_value = mapping.get("groups")
    groups: dict[str, GroupSpec] = {}
    if groups_value is not None:
        for name, group in require_mapping(groups_value, f"{context}.groups").items():
            if not isinstance(name, str):
                raise ValueError(f"{context}.groups names must be strings")
            groups[name] = parse_group(group, f"{context}.groups.{name}")

    ignored: list[str] = []
    ignore_value = mapping.get("ignore")
    if ignore_value is not None:
        for ignore_index, item in enumerate(
            require_list(ignore_value, f"{context}.ignore")
        ):
            ignored_mapping = require_mapping(item, f"{context}.ignore[{ignore_index}]")
            target = ignored_mapping.get("dependency-name")
            if target is None:
                continue
            if not isinstance(target, str):
                raise ValueError(
                    f"{context}.ignore[{ignore_index}].dependency-name must be a string"
                )
            if target:
                ignored.append(target)

    return {
        "ecosystem": optional_string(mapping, "package-ecosystem", context, "?"),
        "directory": directory,
        "directories": string_list(
            mapping.get("directories"), f"{context}.directories"
        ),
        "groups": groups,
        "ignored": ignored,
    }


def config_updates(value: object) -> list[object] | None:
    if not isinstance(value, dict):
        return None
    mapping = cast(ObjectMapping, value)
    updates = mapping.get("updates")
    if not isinstance(updates, list):
        return None
    return cast(list[object], updates)


def load_config(path: Path) -> object:
    """Parse a Dependabot config from YAML, or from JSON when given .json.

    Accepting JSON removes the PyYAML requirement for callers that already
    converted the file - step 1 of the skill produces exactly such a file.
    """
    text = path.read_text()
    if path.suffix == ".json":
        json_data: object = json.loads(text)
        return json_data
    try:
        # PyYAML is optional; the missing-module path below is valid behavior.
        import yaml  # pyright: ignore[reportMissingModuleSource]
    except ModuleNotFoundError:
        sys.exit(
            "PyYAML is required to read YAML directly.\n"
            "Either `pip install pyyaml`, or convert the config to JSON first and\n"
            "pass it with --config (see the manual fallback in SKILL.md)."
        )
    yaml_data: object = yaml.safe_load(text)
    return yaml_data


def npm_names(base: Path) -> tuple[list[str], str | None]:
    manifest = base / "package.json"
    if not manifest.is_file():
        return [], str(manifest)
    parsed: object = json.loads(manifest.read_text())
    data = require_mapping(parsed, str(manifest))
    names: set[str] = set()
    for key in NPM_DEP_KEYS:
        value = data.get(key)
        if isinstance(value, dict):
            dependencies = cast(ObjectMapping, value)
            for name in dependencies:
                if not isinstance(name, str):
                    raise ValueError(f"{manifest}:{key} names must be strings")
                names.add(name)
    return sorted(names), None


def actions_names(base: Path) -> tuple[list[str], str | None]:
    """Action references are `uses:` values; the name is everything before @."""
    workflows = base / ".github" / "workflows"
    composites = sorted((base / ".github" / "actions").glob("*/action.y*ml"))
    if not workflows.is_dir() and not composites:
        return [], str(workflows)
    names: set[str] = set()
    files = sorted(workflows.glob("*.yml")) + sorted(workflows.glob("*.yaml"))
    for path in list(files) + composites:
        for line in path.read_text().splitlines():
            match = USES_RE.match(line)
            if match:
                ref = match.group(1)
                if not ref.startswith("./"):  # local actions are not updatable
                    names.add(ref.split("@")[0])
    return sorted(names), None


def docker_names(base: Path) -> tuple[list[str], str | None]:
    """Image names from FROM lines, excluding build-stage back-references."""
    files = sorted(base.glob("Dockerfile*")) + sorted(base.glob("*.Dockerfile"))
    if not files:
        return [], str(base / "Dockerfile")
    images: set[str] = set()
    stages: set[str] = set()
    for path in files:
        for line in path.read_text().splitlines():
            match = FROM_RE.match(line)
            if not match:
                continue
            tokens = match.group(1).split()
            tokens = [t for t in tokens if not t.startswith("--")]
            if not tokens:
                continue
            image = tokens[0]
            if len(tokens) >= 3 and tokens[1].lower() == "as":
                stages.add(tokens[2].lower())
            images.add(
                image.split("@")[0].rsplit(":", 1)[0]
                if ":" in image
                else image.split("@")[0]
            )
    return sorted(images - stages), None


def gomod_names(base: Path) -> tuple[list[str], str | None]:
    manifest = base / "go.mod"
    if not manifest.is_file():
        return [], str(manifest)
    names: set[str] = set()
    in_block = False
    for line in manifest.read_text().splitlines():
        stripped = line.split("//")[0].strip()
        if not stripped:
            continue
        if GOMOD_REQUIRE_BLOCK.match(stripped):
            in_block = True
            continue
        if in_block:
            if stripped == ")":
                in_block = False
                continue
            names.add(stripped.split()[0])
            continue
        single = GOMOD_REQUIRE_LINE.match(stripped)
        if single:
            names.add(single.group(1))
    return sorted(names), None


RESOLVERS: dict[str, Resolver] = {
    "npm": npm_names,
    "github-actions": actions_names,
    "docker": docker_names,
    "gomod": gomod_names,
}


def matches(name: str, pattern: str) -> bool:
    """Dependabot patterns are case-insensitive wildcard globs; `*` spans `/`.

    fnmatchcase over pre-lowercased operands, because fnmatch applies
    os.path.normcase and would behave differently on Windows.
    """
    return fnmatch.fnmatchcase(name.lower(), pattern.lower())


def claimed(name: str, group: GroupSpec) -> bool:
    if not any(matches(name, pattern) for pattern in group["patterns"]):
        return False
    return not any(matches(name, exclude) for exclude in group["excludes"])


def scope(group: GroupSpec) -> tuple[str, frozenset[str]]:
    update_types = group["update_types"]
    return (
        group["applies_to"],
        frozenset(update_types) if update_types else frozenset({"*"}),
    )


def scopes_overlap(
    a: tuple[str, frozenset[str]], b: tuple[str, frozenset[str]]
) -> bool:
    if a[0] != b[0]:
        return False
    if "*" in a[1] or "*" in b[1]:
        return True
    return bool(a[1] & b[1])


def expand_directories(root: Path, entry: UpdateSpec) -> list[str]:
    """Dependabot accepts `directory` (one) or `directories` (many, globbable)."""
    if entry["directory"]:
        return [entry["directory"]]
    result: list[str] = []
    for raw in entry["directories"] or ["/"]:
        if any(ch in raw for ch in "*?["):
            hits = sorted(p for p in root.glob(raw.lstrip("/")) if p.is_dir())
            result.extend("/" + str(p.relative_to(root)) for p in hits)
        else:
            result.append(raw)
    return result or ["/"]


def audit_directory(
    root: Path, entry: UpdateSpec, index: int, directory: str, show_ungrouped: bool
) -> tuple[list[tuple[str, str]], bool]:
    """Returns (findings, audited). audited=False means the ecosystem was skipped."""
    findings: list[tuple[str, str]] = []
    ecosystem = entry["ecosystem"]
    label = f"updates[{index}] {ecosystem} {directory}"

    base = root / directory.lstrip("/")
    if not base.is_dir():
        return [
            ("missing-directory", f"{label}: directory does not exist in the repo")
        ], True

    resolver = RESOLVERS.get(ecosystem)
    if resolver is None:
        print(
            f"  {label}: skipped semantic audit, no resolver for ecosystem '{ecosystem}'"
        )
        return [], False

    names, missing = resolver(base)
    if missing:
        return [
            ("missing-manifest", f"{label}: expected manifest not found at {missing}")
        ], True
    print(f"  {label}: resolved {len(names)} declared dependencies")
    if not names:
        findings.append(
            (
                "missing-manifest",
                f"{label}: manifest present but declares no dependencies",
            )
        )

    groups = entry["groups"]
    for gname, group in groups.items():
        patterns = group["patterns"]
        for pattern in patterns:
            if not any(matches(n, pattern) for n in names):
                findings.append(
                    (
                        "dead-pattern",
                        f"{label}: group '{gname}' pattern '{pattern}' matches nothing",
                    )
                )
        matched = [n for n in names if any(matches(n, p) for p in patterns)]
        for exclude in group["excludes"]:
            if not any(matches(n, exclude) for n in matched):
                findings.append(
                    (
                        "dead-exclude",
                        f"{label}: group '{gname}' exclude-pattern '{exclude}' excludes nothing "
                        "its own patterns matched",
                    )
                )

    for name in names:
        owners = [g for g, spec in groups.items() if claimed(name, spec)]
        for i, first in enumerate(owners):
            for second in owners[i + 1 :]:
                if scopes_overlap(scope(groups[first]), scope(groups[second])):
                    findings.append(
                        (
                            "double-claim",
                            f"{label}: '{name}' claimed by groups '{first}' and '{second}' with "
                            "overlapping applies-to/update-types; Dependabot assigns it to the "
                            "first match, so add exclude-patterns to the group that should not own it",
                        )
                    )
        if not owners and show_ungrouped:
            findings.append(
                ("ungrouped", f"{label}: '{name}' is in no group (individual PRs)")
            )

    for target in entry["ignored"]:
        if not any(matches(n, target) for n in names):
            findings.append(
                (
                    "dead-ignore",
                    f"{label}: ignore entry '{target}' matches no declared dependency",
                )
            )

    return findings, True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config",
        default=".github/dependabot.yml",
        help="path to dependabot.yml, or a .json conversion of it",
    )
    parser.add_argument(
        "--root", default=".", help="repository root the config's paths resolve against"
    )
    parser.add_argument(
        "--show-ungrouped",
        action="store_true",
        help="also report dependencies no group claims (informational, never fails the run)",
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    config = Path(args.config)
    if not config.is_absolute():
        config = root / config
    if not config.is_file():
        print(f"config not found: {config}", file=sys.stderr)
        return 2

    try:
        doc = load_config(config)
    except (json.JSONDecodeError, ValueError) as exc:
        print(f"parse error in {config}: {exc}", file=sys.stderr)
        return 2

    updates = config_updates(doc)
    if updates is None:
        print(f"{config}: no `updates` list - not a Dependabot config", file=sys.stderr)
        return 2

    print(f"auditing {config} against {root}")
    findings: list[tuple[str, str]] = []
    audited = skipped = 0
    for index, raw_entry in enumerate(updates):
        entry_value: object = raw_entry
        if not isinstance(entry_value, dict):
            print(f"updates[{index}]: not a mapping, skipping", file=sys.stderr)
            continue
        try:
            entry = parse_update(cast(ObjectMapping, entry_value), index)
        except ValueError as exc:
            print(f"parse error in {config}: {exc}", file=sys.stderr)
            return 2
        for directory in expand_directories(root, entry):
            entry_findings, was_audited = audit_directory(
                root, entry, index, directory, args.show_ungrouped
            )
            findings.extend(entry_findings)
            audited += 1 if was_audited else 0
            skipped += 0 if was_audited else 1

    if audited == 0:
        print(
            "\nno update entry could be audited - every ecosystem was skipped",
            file=sys.stderr,
        )
        return 2

    failing = [f for f in findings if f[0] != "ungrouped"]
    if findings:
        print()
        for kind, message in findings:
            print(f"{kind}: {message}")
        print(
            f"\n{len(failing)} finding(s), {len(findings) - len(failing)} informational"
        )
    else:
        print(
            "\nclean: every pattern, exclude-pattern and ignore entry resolves; no double claims"
        )
    if skipped:
        print(
            f"note: {skipped} update entry/entries skipped for lack of an ecosystem resolver"
        )
    return 1 if failing else 0


if __name__ == "__main__":
    sys.exit(main())
