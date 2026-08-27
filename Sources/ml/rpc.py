"""JSON-RPC stdin/stdout server for ML tasks.

The wire contract lives in `protocol.py` and is mirrored by
`Sources/Managers/MLRPCProtocol.swift`; `MLRPCContractTests` runs this daemon
for real and checks the two agree.
"""

from __future__ import annotations

import json
import sys
from typing import Any, Dict, Optional

from .correction import correct
from .loader import load_correction_model, load_parakeet_model
from .parakeet import DEFAULT_PARAKEET_REPO, transcribe
from .protocol import (
    JSONRPC_VERSION,
    Response,
    optional_str,
    require_str,
    require_warmup_kind,
)


def _respond(payload: Response) -> None:
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def _result(req_id: Optional[int], result: Any) -> None:
    _respond({"jsonrpc": JSONRPC_VERSION, "id": req_id, "result": result})


def _error(req_id: Optional[int], message: str) -> None:
    _respond({"jsonrpc": JSONRPC_VERSION, "id": req_id, "error": {"message": message}})


def _dispatch(method: str, params: Dict[str, Any]) -> Any:
    """Run one method and return its result payload.

    Parameters are validated here rather than trusted: they arrive off a pipe,
    which is exactly where static types stop applying. `require_str` and friends
    replace truthiness checks that accepted any non-empty value of any type.
    """
    if method == "ping":
        return {"pong": True}

    if method == "transcribe":
        pcm_path = require_str(params, "pcm_path", method)
        repo = params.get("repo") or DEFAULT_PARAKEET_REPO
        if not isinstance(repo, str):
            raise ValueError(f"{method}: 'repo' must be a string, got {type(repo).__name__}")
        return transcribe(repo, pcm_path)

    if method == "correct":
        repo = require_str(params, "repo", method)
        # `text` may legitimately be empty — an empty transcript is not an
        # error — so it is checked for type without the non-empty rule.
        text = params.get("text")
        if not isinstance(text, str):
            got = type(text).__name__ if "text" in params else "nothing"
            raise ValueError(f"{method}: 'text' must be a string, got {got}")
        prompt = optional_str(params, "prompt", method)
        return correct(repo, text, prompt)

    if method == "warmup":
        kind = require_warmup_kind(params, method)
        repo = require_str(params, "repo", method)
        if kind == "parakeet":
            load_parakeet_model(repo)
        else:
            load_correction_model(repo)
        return {"success": True}

    raise ValueError(f"Unknown method: {method}")


def _handle_request(request: Dict[str, Any]) -> None:
    req_id = request.get("id")
    if req_id is not None and not isinstance(req_id, int):
        # A non-integer id cannot be matched to a waiting caller on the Swift
        # side, which keys `pending` by Int. Refuse rather than echo it back.
        _error(None, f"Request 'id' must be an integer, got {type(req_id).__name__}")
        return

    method = request.get("method")
    if not isinstance(method, str):
        _error(req_id, f"Request 'method' must be a string, got {type(method).__name__}")
        return

    params = request.get("params") or {}
    if not isinstance(params, dict):
        _error(req_id, f"Request 'params' must be an object, got {type(params).__name__}")
        return

    try:
        _result(req_id, _dispatch(method, params))
    except Exception as exc:
        _error(req_id, str(exc))


def main() -> int:
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError as exc:
            _error(None, f"Invalid JSON: {exc}")
            continue

        if not isinstance(request, dict):
            _error(None, "Request must be a JSON object")
            continue

        _handle_request(request)
    return 0
