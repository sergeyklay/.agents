import json
import sys
from pathlib import Path
from typing import Any

Json = dict[str, Any]
HISTORICAL_TOOLS = {
    "context7": "query-docs",
    "bpdb": "query",
    "snyk": "snyk_version",
}


def reply(namespace: str, log: Path, request: Json, catalog: Json) -> Json:
    method = request["method"]
    if method == "initialize":
        return {
            "protocolVersion": "2024-11-05",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": namespace, "version": "1"},
        }
    if method == "tools/list":
        names = catalog[namespace]
        return {
            "tools": [
                {
                    "name": name,
                    "description": f"Fixture {name}",
                    "inputSchema": {"type": "object", "properties": {}},
                }
                for name in names
            ]
        }
    if method == "tools/call":
        name = request["params"]["name"]
        with log.open("a") as stream:
            stream.write(json.dumps({"server": namespace, "tool": name}) + "\n")
        return {
            "content": [{"type": "text", "text": f"MCP_EXECUTED:{namespace}:{name}"}]
        }
    return {}


def main() -> None:
    namespace, path, catalog_path = sys.argv[1:]
    catalog = json.loads(Path(catalog_path).read_text())
    for line in sys.stdin:
        request = json.loads(line)
        if "id" not in request:
            continue
        result = reply(namespace, Path(path), request, catalog)
        print(
            json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}),
            flush=True,
        )


if __name__ == "__main__":
    main()
