#!/usr/bin/env python3

import argparse
import json
import os
import re
import select
import signal
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, cast

JsonObject = dict[str, Any]


def write_message(message: JsonObject) -> None:
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
    sys.stdout.flush()


class MockResponsesProvider:
    def __init__(self, command: str, escalate: bool) -> None:
        self.command = command
        self.escalate = escalate
        self.tool_outputs: list[str] = []
        self.request_count = 0
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), self._handler())
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{self.server.server_port}/v1"

    def start(self) -> None:
        self.thread.start()

    def close(self) -> None:
        self.server.shutdown()
        self.thread.join(timeout=5)
        self.server.server_close()

    def _handler(self) -> type[BaseHTTPRequestHandler]:
        provider = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:
                if self.path != "/v1/responses":
                    self.send_error(404)
                    return
                content_length = int(self.headers.get("Content-Length", "0"))
                request = json.loads(self.rfile.read(content_length))
                for item in request.get("input", []):
                    if (
                        item.get("type") == "function_call_output"
                        and item.get("call_id") == "command-probe-call"
                    ):
                        provider.tool_outputs.append(item["output"])
                provider.request_count += 1
                response = provider._response(provider.request_count)
                body = response.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *_args: object) -> None:
                pass

        return Handler

    def _response(self, request_count: int) -> str:
        if request_count == 1:
            arguments: JsonObject = {"cmd": self.command, "login": False}
            if self.escalate:
                arguments.update(
                    sandbox_permissions="require_escalated",
                    justification="Exercise the Codex approval path.",
                )
            events = [
                {
                    "type": "response.created",
                    "response": {"id": f"response-{request_count}"},
                },
                {
                    "type": "response.output_item.done",
                    "item": {
                        "type": "function_call",
                        "call_id": "command-probe-call",
                        "name": "exec_command",
                        "arguments": json.dumps(
                            arguments,
                            separators=(",", ":"),
                        ),
                    },
                },
                {
                    "type": "response.completed",
                    "response": self._completed_response(request_count),
                },
            ]
        elif request_count == 2:
            events = [
                {"type": "response.created", "response": {"id": "response-2"}},
                {
                    "type": "response.output_item.done",
                    "item": {
                        "type": "message",
                        "role": "assistant",
                        "id": "approval-probe-message",
                        "content": [
                            {
                                "type": "output_text",
                                "text": "approval-policy-probe-complete",
                            }
                        ],
                    },
                },
                {
                    "type": "response.completed",
                    "response": self._completed_response(request_count),
                },
            ]
        else:
            raise RuntimeError(f"unexpected Responses request {request_count}")
        return "".join(
            f"event: {event['type']}\ndata: {json.dumps(event, separators=(',', ':'))}\n\n"
            for event in events
        )

    def _completed_response(self, request_count: int) -> JsonObject:
        return {
            "id": f"response-{request_count}",
            "usage": {
                "input_tokens": 0,
                "input_tokens_details": None,
                "output_tokens": 0,
                "output_tokens_details": None,
                "total_tokens": 0,
            },
        }


def serve(sentinel_log: Path) -> int:
    for line in sys.stdin:
        message = json.loads(line)
        method = message.get("method")
        request_id = message.get("id")
        if method == "initialize":
            params = message["params"]
            write_message(
                {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": {
                        "protocolVersion": params["protocolVersion"],
                        "capabilities": {"tools": {}},
                        "serverInfo": {"name": "task-031-sentinel", "version": "1.0.0"},
                    },
                }
            )
        elif method == "tools/list":
            write_message(
                {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": {
                        "tools": [
                            {
                                "name": "sentinel",
                                "description": "Return the supplied sentinel.",
                                "inputSchema": {
                                    "type": "object",
                                    "properties": {"value": {"type": "string"}},
                                    "required": ["value"],
                                    "additionalProperties": False,
                                },
                            }
                        ]
                    },
                }
            )
        elif method == "tools/call":
            params = message["params"]
            if params.get("name") != "sentinel":
                write_message(
                    {
                        "jsonrpc": "2.0",
                        "id": request_id,
                        "error": {"code": -32602, "message": "unknown tool"},
                    }
                )
                continue
            value = params["arguments"]["value"]
            sentinel_log.write_text(value + "\n", encoding="utf-8")
            write_message(
                {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": {
                        "content": [{"type": "text", "text": value}],
                        "structuredContent": {"sentinel": value},
                    },
                }
            )
        elif request_id is not None:
            write_message(
                {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "error": {
                        "code": -32601,
                        "message": f"unsupported method: {method}",
                    },
                }
            )
    return 0


class AppServer:
    def __init__(self, codex: str, workspace: Path) -> None:
        self.pending_messages: list[JsonObject] = []
        self.stdout_buffer = bytearray()
        self.process = subprocess.Popen(
            [codex, "app-server", "--stdio", "--strict-config"],
            cwd=workspace,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
            start_new_session=True,
        )

    def request(self, request_id: int, method: str, params: JsonObject) -> JsonObject:
        if self.process.stdin is None:
            raise RuntimeError("app-server stdin is unavailable")
        message = {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
            "params": params,
        }
        self.process.stdin.write(
            (json.dumps(message, separators=(",", ":")) + "\n").encode("utf-8")
        )
        self.process.stdin.flush()
        return self._read_response(request_id)

    def _read_response(self, request_id: int) -> JsonObject:
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            message = self._read_stream_message(deadline)
            if message.get("id") == request_id:
                return message
            self.pending_messages.append(message)
        raise RuntimeError(
            self._failure(f"timed out waiting for response {request_id}")
        )

    def read_message(self, deadline: float) -> JsonObject:
        if self.pending_messages:
            return self.pending_messages.pop(0)
        return self._read_stream_message(deadline)

    def _read_stream_message(self, deadline: float) -> JsonObject:
        if self.process.stdout is None:
            raise RuntimeError("app-server stdout is unavailable")
        while time.monotonic() < deadline:
            newline = self.stdout_buffer.find(b"\n")
            if newline != -1:
                line = bytes(self.stdout_buffer[:newline])
                del self.stdout_buffer[: newline + 1]
                return cast(JsonObject, json.loads(line))
            ready, _, _ = select.select([self.process.stdout], [], [], 0.25)
            if not ready:
                if self.process.poll() is not None:
                    raise RuntimeError(
                        self._failure("app-server exited before responding")
                    )
                continue
            data = os.read(self.process.stdout.fileno(), 4096)
            if not data:
                raise RuntimeError(self._failure("app-server closed stdout"))
            self.stdout_buffer.extend(data)
        raise RuntimeError(self._failure("timed out waiting for app-server message"))

    def _failure(self, reason: str) -> str:
        stderr = ""
        if self.process.stderr is not None and self.process.poll() is not None:
            stderr = (
                self.process.stderr.read().decode("utf-8", errors="replace").strip()
            )
        return f"{reason}: {stderr}" if stderr else reason

    def close(self) -> None:
        if self.process.poll() is None:
            os.killpg(self.process.pid, signal.SIGTERM)
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)
                self.process.wait(timeout=5)


def result(response: JsonObject, method: str) -> JsonObject:
    if "error" in response:
        raise RuntimeError(
            f"{method} failed: {json.dumps(response['error'], sort_keys=True)}"
        )
    value = response.get("result")
    if not isinstance(value, dict):
        raise RuntimeError(f"{method} returned no object result")
    return cast(JsonObject, value)


def call_sentinel(codex: str, workspace: Path, server_name: str, sentinel: str) -> int:
    app = AppServer(codex, workspace)
    try:
        result(
            app.request(
                1,
                "initialize",
                {
                    "clientInfo": {"name": "task-031-probe", "version": "1.0.0"},
                    "capabilities": {"experimentalApi": True},
                },
            ),
            "initialize",
        )
        thread = result(
            app.request(
                2,
                "thread/start",
                {
                    "cwd": str(workspace),
                    "approvalPolicy": "never",
                    "sandbox": "danger-full-access",
                    "ephemeral": True,
                },
            ),
            "thread/start",
        )["thread"]
        called = result(
            app.request(
                3,
                "mcpServer/tool/call",
                {
                    "threadId": thread["id"],
                    "server": server_name,
                    "tool": "sentinel",
                    "arguments": {"value": sentinel},
                },
            ),
            "mcpServer/tool/call",
        )
        expected = [{"type": "text", "text": sentinel}]
        if called.get("content") != expected:
            raise RuntimeError(
                f"unexpected MCP result: {json.dumps(called, sort_keys=True)}"
            )
        print(sentinel)
        return 0
    finally:
        app.close()


def configure_command_probe(config_path: Path, provider: MockResponsesProvider) -> None:
    config = config_path.read_text(encoding="utf-8")
    config, model_count = re.subn(
        r'^model = ".*"$', 'model = "approval-probe-model"', config, flags=re.MULTILINE
    )
    if model_count != 1:
        raise RuntimeError("expected exactly one installed model setting")
    marker = "[permissions]\n"
    if config.count(marker) != 1:
        raise RuntimeError("expected exactly one permissions section")
    additions = 'model_provider = "approval-probe"\n\n'
    config = config.replace(marker, additions + marker)
    mcp_start = config.index("[mcp_servers]\n")
    mcp_end = config.index("[marketplaces]\n")
    config = config[:mcp_start] + config[mcp_end:]
    config += (
        "\n[model_providers.approval-probe]\n"
        'name = "Approval probe"\n'
        f'base_url = "{provider.base_url}"\n'
        'wire_api = "responses"\n'
        "request_max_retries = 0\n"
        "stream_max_retries = 0\n"
    )
    config_path.write_text(config, encoding="utf-8")


def run_command_scenario(
    codex: str, workspace: Path, expect_approval: bool
) -> tuple[int, bool]:
    app = AppServer(codex, workspace)
    try:
        result(
            app.request(
                1,
                "initialize",
                {
                    "clientInfo": {
                        "name": "task-031-approval-probe",
                        "version": "1.0.0",
                    },
                    "capabilities": {"experimentalApi": True},
                },
            ),
            "initialize",
        )
        thread_result = result(
            app.request(
                2,
                "thread/start",
                {
                    "cwd": str(workspace),
                    "ephemeral": True,
                },
            ),
            "thread/start",
        )
        expected_policy = "on-request" if expect_approval else "never"
        if thread_result.get("approvalPolicy") != expected_policy:
            raise RuntimeError(
                f"session did not inherit {expected_policy} approval policy"
            )
        if thread_result.get("activePermissionProfile", {}).get("id") != "full-access":
            raise RuntimeError(
                "session did not inherit the installed permission profile"
            )
        thread = thread_result["thread"]
        if (
            not isinstance(thread, dict)
            or "id" not in thread
            or not isinstance(thread["id"], str)
        ):
            raise RuntimeError("thread/start returned no thread id")
        result(
            app.request(
                3,
                "turn/start",
                {
                    "threadId": thread["id"],
                    "input": [
                        {
                            "type": "text",
                            "text": "run the approval probe",
                            "textElements": [],
                        }
                    ],
                },
            ),
            "turn/start",
        )
        approval_requests = 0
        observed_methods: list[str] = []
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            message = app.read_message(deadline)
            method_value = message["method"] if "method" in message else None
            method = method_value if isinstance(method_value, str) else None
            observed_methods.append(str(method))
            if method == "item/commandExecution/requestApproval":
                approval_requests += 1
                params = message["params"] if "params" in message else None
                if (
                    not isinstance(params, dict)
                    or "itemId" not in params
                    or params["itemId"] != "command-probe-call"
                ):
                    raise RuntimeError(
                        "approval request did not describe the deterministic command"
                    )
                if not expect_approval:
                    raise RuntimeError("never policy unexpectedly requested approval")
                return approval_requests, False
            if method == "turn/completed":
                if expect_approval:
                    raise RuntimeError(
                        "on-request turn completed before an approval request: "
                        + ", ".join(observed_methods)
                    )
                if message["params"]["turn"]["status"] != "completed":
                    raise RuntimeError(f"turn failed: {message['params']['turn']}")
                return approval_requests, True
        raise RuntimeError(
            f"{expected_policy} scenario did not reach a terminal outcome"
        )
    finally:
        app.close()


def run_command_probe(
    codex: str, workspace: Path, command: str, escalate: bool, expect_approval: bool
) -> int:
    config_path = Path.home() / ".codex" / "config.toml"
    if not config_path.is_file():
        raise RuntimeError("isolated Codex config is unavailable")
    original_config = config_path.read_text(encoding="utf-8")
    provider = MockResponsesProvider(command, escalate)
    provider.start()
    try:
        configure_command_probe(config_path, provider)
        approval_requests, turn_completed = run_command_scenario(
            codex, workspace, expect_approval
        )
        expected_requests = 1 if expect_approval else 2
        if provider.request_count != expected_requests:
            raise RuntimeError("unexpected number of deterministic Responses requests")
        if len(provider.tool_outputs) != (0 if expect_approval else 1):
            raise RuntimeError("unexpected number of command results sent to the model")
        print(f"approval_requests={approval_requests}")
        print(f"turn_completed={str(turn_completed).lower()}")
        for output in provider.tool_outputs:
            print(output)
        return 0
    finally:
        provider.close()
        config_path.write_text(original_config, encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    serve_parser = subparsers.add_parser("serve")
    serve_parser.add_argument("sentinel_log", type=Path)

    call_parser = subparsers.add_parser("call")
    call_parser.add_argument("codex")
    call_parser.add_argument("workspace", type=Path)
    call_parser.add_argument("server_name")
    call_parser.add_argument("sentinel")

    command_parser = subparsers.add_parser("command")
    command_parser.add_argument("codex")
    command_parser.add_argument("workspace", type=Path)
    command_parser.add_argument("shell_command")
    command_parser.add_argument("--escalate", action="store_true")
    command_parser.add_argument("--expect-approval", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.command == "serve":
        return serve(args.sentinel_log)
    if args.command == "call":
        return call_sentinel(
            args.codex, args.workspace, args.server_name, args.sentinel
        )
    return run_command_probe(
        args.codex,
        args.workspace,
        args.shell_command,
        args.escalate,
        args.expect_approval,
    )


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, RuntimeError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error
