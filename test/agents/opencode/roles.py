import re
from pathlib import Path

ORCHESTRATORS = ("composer", "conductor")
WORKERS = (
    "arch-review",
    "architect",
    "go-coder",
    "go-tester",
    "planner",
    "sleuth",
    "ts-coder",
    "ts-tester",
)
ROLES = ORCHESTRATORS + WORKERS
FULL_SERVERS = {
    "context7": ROLES,
    "bpdb": ("sleuth", "ts-coder", "ts-tester"),
    "snyk": ("ts-coder",),
}
REQUIRED_SKILLS = {
    "arch-review": ("review-arch", "review-spec", "verify-impl"),
    "architect": ("writing-specs",),
    "planner": ("writing-plans",),
    "sleuth": ("research-it",),
    "go-tester": ("test-go",),
    "ts-tester": ("test-ts",),
}


def atlassian_tools(source: Path) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for role in ROLES:
        template = source / "templates/.claude/agents" / f"{role}.yaml"
        text = template.read_text()
        names = re.findall(r"^  - mcp__atlassian__(\S+)$", text, re.MULTILINE)
        if len(names) != text.count("mcp__atlassian__"):
            raise ValueError(f"Unrecognized Atlassian tool list in {template}")
        result[role] = names
    return result
