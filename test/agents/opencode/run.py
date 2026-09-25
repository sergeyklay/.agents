import argparse
import os
import shutil
import sys
import tempfile
from pathlib import Path


def executable(name: str) -> str:
    paths = [path for path in os.get_exec_path() if Path(path).name != "shims"]
    found = shutil.which(name, path=os.pathsep.join(paths))
    if found is None:
        raise SystemExit(f"Required runtime dependency not found: {name}")
    return str(Path(found).resolve())


def main() -> None:
    suite = Path(__file__).resolve().parent
    repo = suite.parents[2]
    parser = argparse.ArgumentParser(
        description="Run native OpenCode tests in a confined filesystem/network"
    )
    parser.add_argument("--source", type=Path, default=repo)
    parser.add_argument("--root", type=Path)
    parser.add_argument("tests", nargs="*")
    args = parser.parse_args()
    parent = Path(
        os.environ.get(
            "OPENCODE_TEST_SCRATCH", Path(tempfile.gettempdir()) / "opencode-tests"
        )
    )
    parent.mkdir(parents=True, exist_ok=True)
    root = args.root.resolve() if args.root else Path(tempfile.mkdtemp(dir=parent))
    root.mkdir(exist_ok=True)
    env = {
        "PATH": "/usr/bin:/bin",
        "PYTHONDONTWRITEBYTECODE": "1",
        "OPENCODE_TEST_SOURCE": str(args.source.resolve()),
        "OPENCODE_TEST_ROOT": str(root),
        "OPENCODE_TEST_BINARY": executable("opencode"),
        "OPENCODE_TEST_GO": executable("go"),
        "OPENCODE_TEST_GOPLS": executable("gopls"),
    }
    command = [
        executable("bwrap"),
        "--ro-bind",
        "/",
        "/",
        "--dev",
        "/dev",
        "--proc",
        "/proc",
        "--bind",
        str(root),
        str(root),
        "--unshare-net",
        "--unshare-pid",
        "--die-with-parent",
        "--clearenv",
        "--chdir",
        str(suite),
    ]
    for key, value in env.items():
        command.extend(["--setenv", key, value])
    selection = args.tests or ["discover", "-s", str(suite), "-p", "test_*.py"]
    command.extend([sys.executable, "-B", "-m", "unittest", *selection, "-v"])
    print(f"Runtime evidence: {root}", flush=True)
    os.execv(command[0], command)


if __name__ == "__main__":
    main()
