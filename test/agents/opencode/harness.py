import errno
import http.client
import json
import os
import socket
import subprocess
import sys
import time
import unittest
import urllib.parse
from contextlib import ExitStack
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional, cast

from fixtures.mcp_server import HISTORICAL_TOOLS
from provider import ScriptedProvider
from roles import FULL_SERVERS, ROLES, atlassian_tools

Json = dict[str, Any]


def call(tool: str, **args: Any) -> Json:
    return {"tool": tool, "args": args}


@dataclass
class Result:
    session: str
    tools: list[Json]
    error: Optional[Json]


class Runtime:
    def __init__(self, name: str) -> None:
        self.source = Path(os.environ["OPENCODE_TEST_SOURCE"])
        self.root = Path(os.environ["OPENCODE_TEST_ROOT"]) / name
        self.root.mkdir()
        self.project = self.root / "project"
        self.home = self.root / "home"
        self.config = self.home / ".config/opencode"
        self.binary = os.environ["OPENCODE_TEST_BINARY"]
        self.env = self._environment()
        self.resources = ExitStack()
        self.provider = ScriptedProvider(self.root / "provider.jsonl")
        self.sequence = 0
        self.url = ""
        self.agents: dict[str, Json] = {}

    def _environment(self) -> dict[str, str]:
        go = Path(os.environ["OPENCODE_TEST_GO"])
        env = {
            "PATH": f"{go.parent}:/usr/bin:/bin",
            "HOME": str(self.home),
            "SHELL": "/bin/bash",
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "XDG_DATA_HOME": str(self.home / ".local/share"),
            "XDG_CACHE_HOME": str(self.home / ".cache"),
            "XDG_STATE_HOME": str(self.home / ".local/state"),
            "TMPDIR": str(self.root / "tmp"),
            "GOCACHE": str(self.root / "go-cache"),
            "GOMODCACHE": str(self.root / "go-mod"),
            "GOPROXY": "off",
            "GOSUMDB": "off",
            "GOTOOLCHAIN": "local",
            "OPENCODE_DISABLE_PROJECT_CONFIG": "1",
            "OPENCODE_DISABLE_MODELS_FETCH": "1",
            "OPENCODE_DISABLE_AUTOUPDATE": "1",
            "OPENCODE_PURE": "1",
            "OPENCODE_DISABLE_FFF": "1",
            "OPENCODE_EXPERIMENTAL_LSP_TOOL": "1",
            "OPENCODE_DISABLE_LSP_DOWNLOAD": "1",
            "PYTHONDONTWRITEBYTECODE": "1",
        }
        for value in env.values():
            if value.startswith(str(self.root)):
                Path(value).mkdir(parents=True, exist_ok=True)
        self.project.mkdir()
        self.config.mkdir(parents=True)
        return env

    def command(self, args: list[str]) -> str:
        result = subprocess.run(
            args,
            cwd=self.project,
            env=self.env,
            capture_output=True,
            text=True,
            timeout=60,
        )
        record = {
            "command": args,
            "exit": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
        with (self.root / "commands.jsonl").open("a") as stream:
            stream.write(json.dumps(record) + "\n")
        result.check_returncode()
        return result.stdout.strip()

    def start(self) -> None:
        boundary = self.root.parent.parent / "outside-runtime-marker"
        try:
            boundary.write_text("unexpected-write")
        except OSError as error:
            if error.errno != errno.EROFS:
                raise
        else:
            raise AssertionError("Runtime sandbox permits writes outside its root")
        (self.root / "mountinfo.txt").write_text(
            Path("/proc/self/mountinfo").read_text()
        )
        if self.command([self.binary, "--version"]) != "1.18.31":
            raise RuntimeError(
                "Recheck the runtime contract before changing the OpenCode version pin"
            )
        self.command([os.environ["OPENCODE_TEST_GOPLS"], "version"])
        self.command([os.environ["OPENCODE_TEST_GO"], "version"])
        self.command(["git", "init", "-q"])
        self.command(
            [
                "sh",
                str(self.source / "scripts/install.sh"),
                "--agents",
                "--skills",
                "--opencode",
            ]
        )
        self.provider.start()
        self.resources.callback(self.provider.close)
        self._configure()
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        self.url = f"http://127.0.0.1:{port}"
        log = self.resources.enter_context((self.root / "server.log").open("wb"))
        process = subprocess.Popen(
            [
                self.binary,
                "serve",
                "--hostname",
                "127.0.0.1",
                "--port",
                str(port),
                "--print-logs",
                "--log-level",
                "DEBUG",
            ],
            cwd=self.project,
            env=self.env,
            stdout=log,
            stderr=log,
        )
        self.resources.callback(self._stop, process)
        self._wait_for_server(process)
        loaded = cast(list[Json], self.api("/agent"))
        self.agents = {agent["name"]: agent for agent in loaded}
        self.save("agents", loaded)

    @staticmethod
    def _stop(process: subprocess.Popen[bytes]) -> None:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()

    def _wait_for_server(self, process: subprocess.Popen[bytes]) -> None:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError((self.root / "server.log").read_text())
            if "server listening" not in (self.root / "server.log").read_text():
                time.sleep(0.1)
                continue
            try:
                self.api("/global/health")
                return
            except ConnectionRefusedError:
                time.sleep(0.1)
        raise TimeoutError("OpenCode did not become healthy")

    def _configure(self) -> None:
        settings = json.loads((self.source / ".opencode/opencode.json").read_text())
        models = {
            name: {
                "name": name,
                "tool_call": True,
                "limit": {"context": 100000, "output": 4096},
            }
            for name in ("gpt-fixture", "other-fixture")
        }
        for role in ROLES:
            file = self.config / "agents" / f"{role}.md"
            lines = file.read_text().splitlines()
            lines = [
                "model: fixture/gpt-fixture" if line.startswith("model: ") else line
                for line in lines
            ]
            file.write_text("\n".join(lines) + "\n")
        permission = settings["permission"]
        permission.update(
            {f"{server}_globallyBlocked": "deny" for server in FULL_SERVERS}
        )
        catalog = {
            server: [HISTORICAL_TOOLS[server], "extraCapability", "globallyBlocked"]
            for server in FULL_SERVERS
        }
        methods = atlassian_tools(self.source)
        catalog["atlassian"] = sorted(
            {name for names in methods.values() for name in names}
        ) + ["extraCapability"]
        catalog_path = self.root / "mcp-tools.json"
        catalog_path.write_text(json.dumps(catalog))
        mcp_fixture = Path(__file__).parent / "fixtures/mcp_server.py"
        config = {
            "permission": permission,
            "subagent_depth": settings["subagent_depth"],
            "model": "fixture/gpt-fixture",
            "small_model": "fixture/gpt-fixture",
            "enabled_providers": ["fixture"],
            "provider": {
                "fixture": {
                    "npm": "@ai-sdk/openai-compatible",
                    "models": models,
                    "options": {
                        "baseURL": self.provider.url,
                        "apiKey": "local-fixture",
                    },
                }
            },
            "snapshot": False,
            "autoupdate": False,
            "share": "disabled",
            "formatter": False,
            "mcp": {
                server: {
                    "type": "local",
                    "command": [
                        sys.executable,
                        str(mcp_fixture),
                        server,
                        str(self.root / "mcp.jsonl"),
                        str(catalog_path),
                    ],
                }
                for server in catalog
            },
            "lsp": {
                "gopls": {
                    "command": [os.environ["OPENCODE_TEST_GOPLS"]],
                    "extensions": [".go"],
                }
            },
        }
        (self.config / "opencode.json").write_text(json.dumps(config))
        skill = self.config / "skills/auxiliary-fixture"
        skill.mkdir()
        (skill / "SKILL.md").write_text(
            "---\nname: auxiliary-fixture\ndescription: Ordinary extra test skill\n---\nAUXILIARY_SKILL_LOADED\n"
        )
        (self.project / "go.mod").write_text("module fixture\n\ngo 1.24\n")
        (self.project / "main.go").write_text(
            "package fixture\n\nfunc Answer() int { return 42 }\n\nfunc Use() int { return Answer() }\n"
        )

    def api(self, path: str, body: Optional[Json] = None) -> Any:
        url = urllib.parse.urlsplit(self.url)
        connection = http.client.HTTPConnection(
            url.hostname or "127.0.0.1",
            url.port,
            timeout=2 if path == "/global/health" else 60,
        )
        try:
            connection.request(
                "GET" if body is None else "POST",
                path,
                body=None if body is None else json.dumps(body),
                headers={"Content-Type": "application/json"}
                if body is not None
                else {},
            )
            response = connection.getresponse()
            data = response.read()
            if response.status != 200:
                raise RuntimeError(f"{path}: {response.status} {data!r}")
            return json.loads(data)
        finally:
            connection.close()

    def save(self, name: str, value: Any) -> None:
        (self.root / f"{name}.json").write_text(json.dumps(value, indent=2))

    def plan(self, steps: list[Json]) -> str:
        self.sequence += 1
        name = f"probe-{self.sequence}"
        self.provider.plan(name, [[step] for step in steps])
        return name

    def run(self, role: str, steps: list[Json], model: str = "gpt-fixture") -> Result:
        return self.prompt(role, self.plan(steps), model)

    def prompt(self, role: str, plan: str, model: str = "gpt-fixture") -> Result:
        session = self.api("/session", {"title": plan})["id"]
        answer = self.api(
            f"/session/{session}/message",
            {
                "agent": role,
                "model": {"providerID": "fixture", "modelID": model},
                "parts": [{"type": "text", "text": f"PROBE:{plan}"}],
            },
        )
        if answer["info"]["agent"] != role:
            raise AssertionError("OpenCode substituted a different agent")
        messages = self.api(f"/session/{session}/message")
        self.save(plan, {"role": role, "messages": messages})
        tools = [
            part
            for message in messages
            for part in message["parts"]
            if part["type"] == "tool"
        ]
        return Result(session, tools, answer["info"].get("error"))

    def mcp_calls(self) -> list[Json]:
        log = self.root / "mcp.jsonl"
        return (
            [json.loads(line) for line in log.read_text().splitlines()]
            if log.exists()
            else []
        )

    def close(self) -> None:
        self.resources.close()


class RuntimeCase(unittest.TestCase):
    runtime: Runtime

    @classmethod
    def setUpClass(cls) -> None:
        cls.runtime = Runtime(cls.__name__)
        cls.addClassCleanup(cls.runtime.close)
        cls.runtime.start()

    def assert_completed(self, result: Result, tools: list[str]) -> None:
        self.assertIsNone(result.error)
        self.assertEqual([part["tool"] for part in result.tools], tools)
        for part in result.tools:
            self.assertEqual(part["state"]["status"], "completed", part["state"])

    def assert_denied(self, result: Result) -> None:
        self.assertTrue(result.tools, "No tool call reached the runtime")
        state = result.tools[-1]["state"]
        if result.tools[-1]["tool"] == "invalid":
            self.assertIn("unavailable tool", state["output"])
        else:
            self.assertEqual(state["status"], "error")
            self.assertIn("rule which prevents", state["error"])
