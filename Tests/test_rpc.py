#!/usr/bin/env python3
"""Tests for ml.protocol (wire validation) and ml.rpc (the daemon's request loop).

Run with: python3 Tests/test_rpc.py

MLRPCContractTests on the Swift side runs the real daemon and checks that the
two sides of the wire agree. These cover what that cannot reach cheaply: every
way a request can be malformed, and what the daemon answers to each. The model
calls are replaced with fakes, so no mlx, no venv and no model are needed.
"""

import io
import json
import os
import sys
import unittest
from contextlib import redirect_stdout
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "Sources"))

from ml import protocol, rpc  # noqa: E402


def run_daemon(*lines: str) -> list:
    """Feed `lines` to rpc.main() as stdin; return each stdout line, decoded."""
    out = io.StringIO()
    with mock.patch.object(sys, "stdin", io.StringIO("".join(line + "\n" for line in lines))):
        with redirect_stdout(out):
            status = rpc.main()
    assert status == 0
    return [json.loads(line) for line in out.getvalue().splitlines()]


def handle(request: dict) -> dict:
    """Run one request through _handle_request; return the single response."""
    out = io.StringIO()
    with redirect_stdout(out):
        rpc._handle_request(request)
    lines = out.getvalue().splitlines()
    assert len(lines) == 1, lines
    return json.loads(lines[0])


class TestRequireStr(unittest.TestCase):
    def test_returns_a_present_string(self):
        self.assertEqual(protocol.require_str({"k": "v"}, "k", "m"), "v")

    def test_absent_key_is_reported_as_nothing(self):
        with self.assertRaisesRegex(ValueError, "m: 'k' must be a string, got nothing"):
            protocol.require_str({}, "k", "m")

    def test_wrong_type_is_reported_by_type_name(self):
        # The case the old truthiness check let through: a non-empty int.
        with self.assertRaisesRegex(ValueError, "got int"):
            protocol.require_str({"k": 123}, "k", "m")

    def test_explicit_null_is_a_type_error_not_absence(self):
        with self.assertRaisesRegex(ValueError, "got NoneType"):
            protocol.require_str({"k": None}, "k", "m")

    def test_empty_string_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "m: 'k' must not be empty"):
            protocol.require_str({"k": ""}, "k", "m")


class TestOptionalStr(unittest.TestCase):
    def test_absent_and_null_are_both_none(self):
        self.assertIsNone(protocol.optional_str({}, "k", "m"))
        self.assertIsNone(protocol.optional_str({"k": None}, "k", "m"))

    def test_returns_a_string_including_empty(self):
        self.assertEqual(protocol.optional_str({"k": "v"}, "k", "m"), "v")
        self.assertEqual(protocol.optional_str({"k": ""}, "k", "m"), "")

    def test_wrong_type_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "must be a string or null, got list"):
            protocol.optional_str({"k": []}, "k", "m")


class TestWarmupKind(unittest.TestCase):
    def test_accepts_every_declared_kind(self):
        for kind in protocol.WARMUP_KINDS:
            self.assertEqual(protocol.require_warmup_kind({"type": kind}, "warmup"), kind)

    def test_unknown_kind_names_the_accepted_values(self):
        with self.assertRaises(ValueError) as ctx:
            protocol.require_warmup_kind({"type": "whisper"}, "warmup")
        self.assertIn("Unknown warmup type: whisper", str(ctx.exception))
        self.assertIn("parakeet, mlx, correction", str(ctx.exception))

    def test_missing_kind_is_a_string_error(self):
        with self.assertRaisesRegex(ValueError, "'type' must be a string"):
            protocol.require_warmup_kind({}, "warmup")


class TestContractConstants(unittest.TestCase):
    def test_methods_match_what_dispatch_handles(self):
        # Swift's MLRPCMethod must list these same four; MLRPCContractTests
        # checks that side. This checks the Literal and the dispatcher agree.
        self.assertEqual(protocol.METHODS, ("ping", "transcribe", "correct", "warmup"))

    def test_warmup_kinds(self):
        self.assertEqual(protocol.WARMUP_KINDS, ("parakeet", "mlx", "correction"))


class TestDispatch(unittest.TestCase):
    def test_ping(self):
        self.assertEqual(rpc._dispatch("ping", {}), {"pong": True})

    def test_transcribe_passes_repo_and_path(self):
        with mock.patch.object(rpc, "transcribe", return_value={"success": True, "text": "hi"}) as fake:
            result = rpc._dispatch("transcribe", {"pcm_path": "/tmp/a.raw", "repo": "org/model"})
        fake.assert_called_once_with("org/model", "/tmp/a.raw")
        self.assertEqual(result, {"success": True, "text": "hi"})

    def test_transcribe_defaults_the_repo_when_absent_or_empty(self):
        with mock.patch.object(rpc, "transcribe", return_value={}) as fake:
            rpc._dispatch("transcribe", {"pcm_path": "/tmp/a.raw"})
            rpc._dispatch("transcribe", {"pcm_path": "/tmp/a.raw", "repo": ""})
        for call in fake.call_args_list:
            self.assertEqual(call.args[0], rpc.DEFAULT_PARAKEET_REPO)

    def test_transcribe_rejects_a_non_string_repo(self):
        with mock.patch.object(rpc, "transcribe") as fake:
            with self.assertRaisesRegex(ValueError, "transcribe: 'repo' must be a string, got int"):
                rpc._dispatch("transcribe", {"pcm_path": "/tmp/a.raw", "repo": 7})
        fake.assert_not_called()

    def test_transcribe_requires_pcm_path(self):
        with self.assertRaisesRegex(ValueError, "transcribe: 'pcm_path'"):
            rpc._dispatch("transcribe", {})

    def test_correct_passes_text_and_prompt(self):
        with mock.patch.object(rpc, "correct", return_value={"success": True, "text": "x"}) as fake:
            rpc._dispatch("correct", {"repo": "org/m", "text": "hello", "prompt": "fix"})
        fake.assert_called_once_with("org/m", "hello", "fix")

    def test_correct_accepts_empty_text_and_absent_prompt(self):
        # An empty transcript is not an error, unlike an empty repo.
        with mock.patch.object(rpc, "correct", return_value={}) as fake:
            rpc._dispatch("correct", {"repo": "org/m", "text": ""})
        fake.assert_called_once_with("org/m", "", None)

    def test_correct_rejects_missing_or_mistyped_text(self):
        with mock.patch.object(rpc, "correct") as fake:
            with self.assertRaisesRegex(ValueError, "correct: 'text' must be a string, got nothing"):
                rpc._dispatch("correct", {"repo": "org/m"})
            with self.assertRaisesRegex(ValueError, "got dict"):
                rpc._dispatch("correct", {"repo": "org/m", "text": {}})
        fake.assert_not_called()

    def test_warmup_parakeet_loads_the_parakeet_model(self):
        with mock.patch.object(rpc, "load_parakeet_model") as parakeet, \
                mock.patch.object(rpc, "load_correction_model") as correction:
            self.assertEqual(rpc._dispatch("warmup", {"type": "parakeet", "repo": "org/p"}), {"success": True})
        parakeet.assert_called_once_with("org/p")
        correction.assert_not_called()

    def test_warmup_mlx_and_its_alias_load_the_correction_model(self):
        with mock.patch.object(rpc, "load_parakeet_model") as parakeet, \
                mock.patch.object(rpc, "load_correction_model") as correction:
            rpc._dispatch("warmup", {"type": "mlx", "repo": "org/c"})
            rpc._dispatch("warmup", {"type": "correction", "repo": "org/c"})
        self.assertEqual(correction.call_count, 2)
        parakeet.assert_not_called()

    def test_warmup_requires_a_repo(self):
        with self.assertRaisesRegex(ValueError, "warmup: 'repo'"):
            rpc._dispatch("warmup", {"type": "mlx"})

    def test_unknown_method(self):
        with self.assertRaisesRegex(ValueError, "Unknown method: shutdown"):
            rpc._dispatch("shutdown", {})


class TestHandleRequest(unittest.TestCase):
    def test_success_echoes_the_id(self):
        self.assertEqual(
            handle({"jsonrpc": "2.0", "id": 4, "method": "ping"}),
            {"jsonrpc": "2.0", "id": 4, "result": {"pong": True}},
        )

    def test_a_non_integer_id_is_refused_without_echoing_it(self):
        # Swift keys its pending calls by Int; a string id could never be matched.
        response = handle({"id": "4", "method": "ping"})
        self.assertIsNone(response["id"])
        self.assertIn("'id' must be an integer, got str", response["error"]["message"])

    def test_a_missing_id_is_allowed(self):
        self.assertEqual(handle({"method": "ping"})["result"], {"pong": True})

    def test_a_non_string_method(self):
        response = handle({"id": 1, "method": 5})
        self.assertEqual(response["id"], 1)
        self.assertIn("'method' must be a string, got int", response["error"]["message"])

    def test_params_must_be_an_object(self):
        response = handle({"id": 1, "method": "ping", "params": [1, 2]})
        self.assertIn("'params' must be an object, got list", response["error"]["message"])

    def test_null_params_mean_none(self):
        self.assertEqual(handle({"id": 1, "method": "ping", "params": None})["result"], {"pong": True})

    def test_a_failing_method_becomes_an_error_response(self):
        response = handle({"id": 9, "method": "transcribe", "params": {}})
        self.assertEqual(response["id"], 9)
        self.assertNotIn("result", response)
        self.assertIn("'pcm_path' must be a string", response["error"]["message"])


class TestMainLoop(unittest.TestCase):
    def test_answers_each_line_in_order_and_skips_blank_ones(self):
        responses = run_daemon(
            json.dumps({"id": 1, "method": "ping"}),
            "",
            "   ",
            json.dumps({"id": 2, "method": "ping"}),
        )
        self.assertEqual([r["id"] for r in responses], [1, 2])

    def test_invalid_json_is_reported_and_the_loop_continues(self):
        responses = run_daemon("{not json", json.dumps({"id": 3, "method": "ping"}))
        self.assertEqual(len(responses), 2)
        self.assertIsNone(responses[0]["id"])
        self.assertTrue(responses[0]["error"]["message"].startswith("Invalid JSON:"))
        self.assertEqual(responses[1]["result"], {"pong": True})

    def test_a_non_object_request_is_refused(self):
        responses = run_daemon("[1, 2, 3]")
        self.assertEqual(responses, [
            {"jsonrpc": "2.0", "id": None, "error": {"message": "Request must be a JSON object"}},
        ])

    def test_empty_stdin_exits_cleanly(self):
        self.assertEqual(run_daemon(), [])


if __name__ == "__main__":
    unittest.main()
