"""The JSON-RPC wire contract, mirroring Sources/Managers/MLRPCProtocol.swift.

Neither of those files can check the other — no type system spans a process
boundary. What they do is give each side ONE place to state the contract, so a
change is a visible edit rather than a string literal quietly drifting apart
from its counterpart. `MLRPCContractTests` on the Swift side runs the real
daemon and asserts the two agree.

The `Literal` aliases below are the load-bearing part: mypy rejects a method or
warmup kind that is not in the set, and the validators turn the same sets into
runtime checks for values arriving off the wire, where static typing has
nothing to say.
"""

from __future__ import annotations

from typing import Any, Dict, Literal, Optional, TypedDict, get_args

JSONRPC_VERSION = "2.0"

Method = Literal["ping", "transcribe", "correct", "warmup"]
METHODS: tuple[str, ...] = get_args(Method)

# "correction" is a synonym for "mlx" that predates the Swift enum. Swift only
# ever sends "parakeet" or "mlx" (see MLWarmupKind); the alias is kept because
# removing it would break nothing and prove nothing, but it is documented as
# daemon tolerance rather than part of the contract.
WarmupKind = Literal["parakeet", "mlx", "correction"]
WARMUP_KINDS: tuple[str, ...] = get_args(WarmupKind)


# Optional members use the base-class + `total=False` form rather than
# `NotRequired`. `typing.NotRequired` landed in 3.11, and while the app's own
# runtime is pinned to 3.11 by uv, these modules are ALSO imported by tests
# running on whatever `python3` the machine has — /usr/bin/python3 is still
# 3.9.6 on macOS. Importing this file must not be the thing that breaks.


class _TranscribeRequired(TypedDict):
    pcm_path: str


class TranscribeParams(_TranscribeRequired, total=False):
    """`repo` is optional; the daemon falls back to DEFAULT_PARAKEET_REPO."""

    repo: str


class _CorrectRequired(TypedDict):
    repo: str
    text: str


class CorrectParams(_CorrectRequired, total=False):
    prompt: Optional[str]


class WarmupParams(TypedDict):
    type: WarmupKind
    repo: str


class TranscribeResult(TypedDict):
    success: bool
    text: str


class CorrectResult(TypedDict):
    success: bool
    text: str


class WarmupResult(TypedDict):
    success: bool


class PingResult(TypedDict):
    pong: bool


class ErrorBody(TypedDict):
    message: str


class _ResponseRequired(TypedDict):
    jsonrpc: str
    id: Optional[int]


class Response(_ResponseRequired, total=False):
    """One line of stdout. Exactly one of `result` / `error` is present."""

    result: Any
    error: ErrorBody


# ------------------------------------------------------------------ validation
# Everything below runs on values that came off a pipe. Static types describe
# what SHOULD arrive; these check what did.
#
# The old code tested truthiness — `if not pcm_path: raise` — which accepts any
# non-empty value of any type. A numeric `pcm_path` passed that guard and
# reached `os.path.exists(123)`, failing several frames later with a message
# about the wrong thing.


def require_str(params: Dict[str, Any], key: str, method: str) -> str:
    """Return `params[key]`, or raise if it is absent or not a string."""
    value = params.get(key)
    if not isinstance(value, str):
        got = type(value).__name__ if key in params else "nothing"
        raise ValueError(f"{method}: '{key}' must be a string, got {got}")
    if not value:
        raise ValueError(f"{method}: '{key}' must not be empty")
    return value


def optional_str(params: Dict[str, Any], key: str, method: str) -> Optional[str]:
    """Return `params[key]` when present and non-null, else None.

    An absent key and an explicit null are treated alike: Swift omits the member
    when the value is nil, but a hand-written client may send `null`.
    """
    value = params.get(key)
    if value is None:
        return None
    if not isinstance(value, str):
        raise ValueError(f"{method}: '{key}' must be a string or null, got {type(value).__name__}")
    return value


def require_warmup_kind(params: Dict[str, Any], method: str) -> str:
    """Return the warmup `type`, or raise naming the accepted values."""
    value = require_str(params, "type", method)
    if value not in WARMUP_KINDS:
        raise ValueError(f"Unknown warmup type: {value} (expected one of {', '.join(WARMUP_KINDS)})")
    return value
