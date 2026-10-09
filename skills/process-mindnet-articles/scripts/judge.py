#!/usr/bin/env python3
"""Judge (fidelity reviewer) in a separate platform sub-agent on an OpenAI model.

Rule: who writes and who checks are always from different families. Claude
writes, so every check (extractor, cold reader, fidelity reviewer,
translate proofreader) comes here, to GPT. Models favour their own text
(MSumBench; Wataoka et al. 2024). A platform sub-agent on the
codex harness with a GPT model gives both another family and a clean context.

Usage:
  python3 judge.py PROMPT_FILE [--schema fidelity|cold|extractor|proofread|FILE.json]
                    [--model azure/gpt-6-astra] [--effort high] [--ttl-min 8]
                    [--out result.json]

PROMPT_FILE is a finished template from references/phase-a.md with the article,
the extractor's list and the cards filled in. The result (JSON validated by the
platform against the schema) goes to stdout and to --out. Progress and model go to stderr.

Exit code: 0 done, 1 the sub-agent failed (reason on stderr), 2 bad arguments.
"""
import argparse, json, sys, time
import driver_sdk as d

STR_ARR = {"type": "array", "items": {"type": "string"}}
PAIR = {"type": "object", "properties": {"cards": {"type": "array", "items": {"type": "integer"}}, "shared": {"type": "string"}},
        "required": ["cards", "shared"]}
NULLABLE_STR = {"type": ["string", "null"]}

SCHEMAS = {
    "fidelity": {
        "type": "object",
        "properties": {
            "cards": {"type": "array", "items": {"type": "object", "properties": {
                "n": {"type": "integer"},
                "wrong": STR_ARR,
                "lost_caveat": STR_ARR,
                "quote_not_verbatim": {"type": "boolean"},
                "frame": NULLABLE_STR,
                "adds_nothing_beyond": {"type": ["integer", "null"]},
            }, "required": ["n", "wrong", "lost_caveat", "quote_not_verbatim", "frame", "adds_nothing_beyond"]}},
            "missing_ideas": STR_ARR,
            "missing_ending": {"type": "boolean"},
            "duplicates": {"type": "array", "items": PAIR},
            "strongest_quote_unused": NULLABLE_STR,
            "judge_model": {"type": "string"},
        },
        "required": ["cards", "missing_ideas", "missing_ending", "duplicates", "strongest_quote_unused"],
    },
    "cold": {
        "type": "object",
        "properties": {
            "cards": {"type": "array", "items": {"type": "object", "properties": {
                "n": {"type": "integer"}, "learned": {"type": "string"},
                "missing": STR_ARR, "vague": STR_ARR, "meta": STR_ARR, "unknown": STR_ARR,
                "frame": {"type": "boolean"},
            }, "required": ["n", "learned", "missing", "vague", "meta", "unknown", "frame"]}},
            "duplicates": {"type": "array", "items": PAIR},
            "facts": {"type": "array", "items": {"type": "object", "properties": {
                "id": {"type": "string"}, "card": {"type": ["integer", "string"]}}, "required": ["id", "card"]}},
            "judge_model": {"type": "string"},
        },
        "required": ["cards", "duplicates", "facts"],
    },
    "proofread": {
        "type": "object",
        "properties": {
            "ok": {"type": "boolean"},
            "errors": {"type": "array", "items": {"type": "object", "properties": {
                "where": {"type": "string"}, "found": {"type": "string"},
                "problem": {"type": "string"}, "fix": {"type": "string"}},
                "required": ["where", "found", "problem", "fix"]}},
            "judge_model": {"type": "string"},
        },
        "required": ["ok", "errors"],
    },
    "extractor": {"type": "object", "properties": {
        k: {"type": "array", "items": {"type": "object"}} for k in ("core_ideas", "facts", "quotes", "context", "ending")
    } | {"judge_model": {"type": "string"}}, "required": ["core_ideas", "facts", "quotes", "context", "ending"]},
}

WRAPPER = """You run unattended as an independent reviewer. Nobody will answer questions.
Do not browse, do not run commands, do not read or write files: everything you need is below.
Do the task exactly as written, then call the report_result tool ONCE with the JSON object the task asks for
(an object, not a string). Add a field "judge_model" with the model id you run as, if you know it.
Write string values in the language the task says (the article's language).

TASK:
"""


def _missing(obj, schema, path="$"):
    """Minimal structural check: types of object/array and required keys."""
    t = schema.get("type")
    if t == "object":
        if not isinstance(obj, dict):
            return [f"{path} not an object"]
        errs = [f"{path}.{k} missing" for k in schema.get("required", []) if k not in obj]
        for k, sub in schema.get("properties", {}).items():
            if k in obj:
                errs += _missing(obj[k], sub, f"{path}.{k}")
        return errs
    if t == "array":
        if not isinstance(obj, list):
            return [f"{path} not an array"]
        errs = []
        for i, it in enumerate(obj):
            errs += _missing(it, schema.get("items", {}), f"{path}[{i}]")
        return errs
    return []


def direct_call(prompt, schema, model, effort, timeout):
    import os, urllib.request
    url = os.environ.get("OPENAI_BASE_URL", "https://ete-litellm.ai-models.vpc.res.ibm.com").rstrip("/") + "/v1/chat/completions"
    msgs = [{"role": "system", "content": "Answer with one JSON object only. It must match this JSON Schema: " + json.dumps(schema)},
            {"role": "user", "content": prompt.replace("call the report_result tool ONCE with", "answer with")}]
    for attempt in range(2):
        body = {"model": model, "messages": msgs, "response_format": {"type": "json_object"}}
        if effort:
            body["reasoning_effort"] = effort
        try:
            req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"content-type": "application/json"})
            r = json.load(urllib.request.urlopen(req, timeout=timeout))
            out = json.loads(r["choices"][0]["message"]["content"])
        except Exception as e:
            print(f"direct attempt {attempt+1} failed: {e}", file=sys.stderr)
            continue
        errs = _missing(out, schema)
        if not errs:
            out.setdefault("judge_model", r.get("model", model))
            return out
        print(f"direct attempt {attempt+1} schema errors: {errs[:5]}", file=sys.stderr)
        msgs += [{"role": "assistant", "content": json.dumps(out, ensure_ascii=False)},
                 {"role": "user", "content": "Schema errors: " + "; ".join(errs[:20]) + ". Answer again with the corrected full JSON."}]
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("prompt_file")
    ap.add_argument("--schema", default="fidelity")
    ap.add_argument("--model", default="azure/gpt-6-astra")
    ap.add_argument("--effort", default="high")
    ap.add_argument("--ttl-min", type=float, default=8)
    ap.add_argument("--out")
    ap.add_argument("--label", default="judge")
    ap.add_argument("--direct", action="store_true",
                    help="no sandbox: direct GPT call through LiteLLM (~10 s instead of ~30-40 s); same model, clean context, the script validates the schema")
    ap.add_argument("--spawn-model", default="gpt-6-astra",
                    help="model for the platform spawn on the codex harness. Default gpt-6-astra (WITHOUT the azure/ prefix) — verified, codex accepts it and gives GPT-6. DO NOT SEND azure/gpt-6-astra: with that prefix codex returns 400 and the sub-agent HANGS SILENTLY until liveness (platform defect, admin 8 October 2026). Empty = harness default (gpt-5). Note: even with a valid name the spawn is occasionally flaky (~1 in 4 dies on liveness) — check.sh then falls back to --direct. --model applies only to --direct.")
    a = ap.parse_args()

    schema = SCHEMAS.get(a.schema)
    if schema is None:
        try:
            schema = json.load(open(a.schema))
        except Exception as e:
            print(f"bad --schema: {e}", file=sys.stderr)
            return 2
    prompt = WRAPPER + open(a.prompt_file, encoding="utf-8").read()

    t0 = time.time()
    if a.direct:
        res = direct_call(prompt, schema, a.model, a.effort, a.ttl_min * 60)
        if res is None:
            print(f"JUDGE FAILED (direct) after {time.time()-t0:.0f}s", file=sys.stderr)
            return 1
        print(f"judge done in {time.time()-t0:.0f}s on {a.model} (direct)", file=sys.stderr)
        txt = json.dumps(res, ensure_ascii=False, indent=1)
        if a.out:
            open(a.out, "w", encoding="utf-8").write(txt)
        print(txt)
        return 0
    # For the platform spawn we do NOT send the model (codex harness default = gpt-5,
    # GPT family) — codex rejects a LiteLLM name like azure/gpt-6-astra with 400 and
    # the sub-agent hangs silently until liveness. Use --spawn-model only when you know
    # the harness accepts that name.
    spawn_kwargs = {"harness": "codex",
                    "config_options": {"effort": a.effort} if a.effort else None,
                    "ttl_ms": int(a.ttl_min * 60_000), "label": a.label, "poll_seconds": 1.0}
    if a.spawn_model:
        spawn_kwargs["model"] = a.spawn_model
    try:
        res = d.spawn(prompt, schema, **spawn_kwargs)
    except d.InvocationFailed as e:
        print(f"JUDGE FAILED after {time.time()-t0:.0f}s: {e.reason or e}", file=sys.stderr)
        return 1
    print(f"judge done in {time.time()-t0:.0f}s on spawn-model={a.spawn_model or 'harness-default(gpt-5)'} (reports: {res.get('judge_model') if isinstance(res, dict) else '?'})",
          file=sys.stderr)
    txt = json.dumps(res, ensure_ascii=False, indent=1)
    if a.out:
        open(a.out, "w", encoding="utf-8").write(txt)
    print(txt)
    return 0


if __name__ == "__main__":
    sys.exit(main())
