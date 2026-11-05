"""Bounded operational metadata. Never accepts text, prompts or file paths."""
from __future__ import annotations

from contextvars import ContextVar
from dataclasses import dataclass
from functools import wraps
import resource
import sys
import time
from typing import Any, Callable, TypeVar

T = TypeVar("T")


@dataclass
class Metrics:
    cache: str = "unknown"
    load_ms: float = 0.0


_current: ContextVar[Metrics | None] = ContextVar("ml_metrics", default=None)


def model_load(cache: dict[str, Any]) -> Callable[[Callable[[str], T]], Callable[[str], T]]:
    def decorate(function: Callable[[str], T]) -> Callable[[str], T]:
        @wraps(function)
        def measured(repo: str) -> T:
            metrics = _current.get()
            warm = repo in cache
            start = time.perf_counter()
            try:
                return function(repo)
            finally:
                if metrics is not None:
                    metrics.cache = "warm" if warm else "cold"
                    if not warm:
                        metrics.load_ms += (time.perf_counter() - start) * 1000
        return measured
    return decorate


def operation(function: Callable[[], Any]) -> Any:
    metrics = Metrics()
    token = _current.set(metrics)
    start, cpu = time.perf_counter(), time.process_time()
    try:
        result = function()
        if isinstance(result, dict) and "text" in result:
            # ru_maxrss is lifetime high-water memory, not current RSS.
            try:
                peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
            except OSError:
                return result
            result["diagnostics"] = {
                "cache": metrics.cache,
                "loadMilliseconds": metrics.load_ms,
                "operationMilliseconds": (time.perf_counter() - start) * 1000,
                "cpuSeconds": max(0.0, time.process_time() - cpu),
                "peakResidentBytes": int(peak if sys.platform == "darwin" else peak * 1024),
            }
        return result
    finally:
        _current.reset(token)
