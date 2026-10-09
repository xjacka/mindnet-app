#!/usr/bin/env python3
"""Preflight for the scheduled MindNet jobs: is there work worth waking an agent for?

Calls the MCP tool `status` (claims nothing) and decides:

  precheck.py dispatch [--max-sessions 6]
      wake the dispatcher when articles wait AND fewer than --max-sessions
      articles are being worked on (status.articles_in_progress)
  precheck.py article
      wake an article session when at least one article still waits
      (another session may have taken it since the dispatcher ran)

Contract with the scheduler:
  exit 0  run the job; stdout is the summary the job prompt reads
          under „Precheck output“
  exit 1  skip this run, nothing to do
When the check itself fails (network, missing secret, unexpected answer) it
prints a line starting with `PRECHECK FAILED:` and exits 0: the job runs
and its prompt tells the agent to call `status` itself. A broken precheck
must never silently stop the queue.

Reaching the server (no secret is required on a platform that routes
MindNet through a connection proxy):
  MINDNET_MCP_URL    the MCP address. Optional: when unset, it is read from
                     the MCP config (.pi/agent/mcp.json, server
                     `mind-net-mcp`), the same address the running agent
                     uses.
  MINDNET_AGENT_KEY  the reader's key mn_agent_… Optional: sent as a Bearer
                     header only when set. On a platform where the egress
                     gateway injects the connection's credentials itself,
                     the header is unnecessary and this stays unset — never
                     put a real key into a prompt, a file or a report.
"""
import argparse, json, os, sys, urllib.error, urllib.request

MCP_CONFIG_PATHS = (
    os.path.expanduser("~/.pi/agent/mcp.json"),
    os.path.expanduser("~/.mcp.json"),
)


def mcp_url_from_config():
    """The `mind-net-mcp` address from the agent's MCP config, or ""."""
    for path in MCP_CONFIG_PATHS:
        try:
            with open(path) as f:
                cfg = json.load(f)
            url = cfg["mcpServers"]["mind-net-mcp"]["url"].strip()
            if url:
                return url
        except (OSError, KeyError, ValueError, TypeError):
            continue
    return ""


def parse_mcp_response(raw):
    """Parse an MCP tools/call response, plain JSON or SSE (`data: {...}`)."""
    raw = raw.strip()
    if raw.startswith("event:") or raw.startswith("data:"):
        raw = "\n".join(l[5:].strip() for l in raw.splitlines()
                        if l.startswith("data:"))
    msg = json.loads(raw)
    result = msg.get("result") or {}
    if "error" in msg or result.get("isError"):
        raise RuntimeError(f"status returned an error: {json.dumps(msg)[:200]}")
    return json.loads(result["content"][0]["text"])


def status():
    url = os.environ.get("MINDNET_MCP_URL", "").strip() or mcp_url_from_config()
    key = os.environ.get("MINDNET_AGENT_KEY", "").strip()
    if not url:
        raise RuntimeError("no MindNet MCP URL: set MINDNET_MCP_URL or add "
                           "the mind-net-mcp server to .pi/agent/mcp.json")
    headers = {
        "content-type": "application/json",
        "accept": "application/json, text/event-stream",
    }
    if key:
        headers["authorization"] = f"Bearer {key}"
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                       "params": {"name": "status", "arguments": {}}}).encode()
    req = urllib.request.Request(url, data=body, method="POST", headers=headers)
    with urllib.request.urlopen(req, timeout=20) as r:
        return parse_mcp_response(r.read().decode())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["dispatch", "article"])
    ap.add_argument("--max-sessions", type=int, default=6)
    a = ap.parse_args()

    try:
        s = status()
        waiting = int(s["articles"])
        running = int(s.get("articles_in_progress", 0))
    except (urllib.error.URLError, RuntimeError, KeyError, ValueError, TypeError) as e:
        print(f"PRECHECK FAILED: {e}")
        return 0

    slots = max(0, a.max_sessions - running)
    print(f"articles waiting: {waiting}; articles in progress: {running}; "
          f"free session slots: {slots} of {a.max_sessions}")
    print(json.dumps({k: s.get(k) for k in ("waiting", "in_progress", "articles",
                                             "articles_in_progress", "answer_within_min")}))
    if waiting == 0:
        return 1
    if a.mode == "dispatch" and slots == 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
