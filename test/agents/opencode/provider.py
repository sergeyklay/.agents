import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

Json = dict[str, Any]


class ScriptedProvider:
    """Supply tool calls over HTTP; OpenCode owns their validation and execution."""

    def __init__(self, log: Path) -> None:
        self.log = log
        self.plans: dict[str, list[list[Json]]] = {}
        self.requests: dict[str, list[Json]] = {}
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), self._handler())
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    @property
    def url(self) -> str:
        return f"http://127.0.0.1:{self.server.server_port}/v1"

    def start(self) -> None:
        self.thread.start()

    def close(self) -> None:
        self.server.shutdown()
        self.thread.join(timeout=5)
        self.server.server_close()

    def plan(self, name: str, steps: list[list[Json]]) -> None:
        self.plans[name] = list(steps)
        self.requests[name] = []

    def response(self, request: Json) -> str:
        messages = request["messages"]
        user = next(item for item in reversed(messages) if item["role"] == "user")
        content = user["content"]
        text = content if isinstance(content, str) else content[0]["text"]
        name = text.removeprefix("PROBE:")
        plan = self.plans.get(name, [])
        self.requests.setdefault(name, []).append(request)
        with self.log.open("a") as stream:
            stream.write(json.dumps({"probe": name, "request": request}) + "\n")
        step = plan.pop(0) if plan else []
        calls = [
            {
                "index": index,
                "id": f"call_{len(self.requests[name])}_{index}",
                "type": "function",
                "function": {
                    "name": call["tool"],
                    "arguments": json.dumps(call["args"]),
                },
            }
            for index, call in enumerate(step)
        ]
        delta = {"tool_calls": calls} if calls else {"content": f"DONE:{name}"}
        chunks = [
            self._chunk(delta, None),
            self._chunk({}, "tool_calls" if calls else "stop"),
        ]
        return (
            "".join(f"data: {json.dumps(chunk)}\n\n" for chunk in chunks)
            + "data: [DONE]\n\n"
        )

    @staticmethod
    def _chunk(delta: Json, finish: Any) -> Json:
        return {
            "id": "fixture",
            "object": "chat.completion.chunk",
            "created": 1,
            "model": "fixture",
            "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
        }

    def _handler(self) -> type[BaseHTTPRequestHandler]:
        provider = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:
                size = int(self.headers["Content-Length"])
                request = json.loads(self.rfile.read(size))
                body = provider.response(request).encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                pass

        return Handler
