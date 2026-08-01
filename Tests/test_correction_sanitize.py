#!/usr/bin/env python3
"""Tests for ml.correction.sanitize_model_output.

Run with: python3 Tests/test_correction_sanitize.py

Every "real output" fixture below is a VERBATIM capture from the 2026-07-31
correction-model benchmark (.claude/bench/correction-model-results.jsonl). These
are not invented cases — each one caused a real correction to be silently
discarded by safeMerge.
"""

import os
import re
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "Sources"))

from ml.correction import sanitize_model_output  # noqa: E402


class TestSpecialTokenStripping(unittest.TestCase):
    """A2: chat-template control tokens pushed a correct answer past safeMerge."""

    def test_strips_phi_end_and_assistant_tokens(self):
        # Phi-3.5-mini, general_short. The correction itself was RIGHT; the
        # trailing tokens took the edit ratio to 0.6083, just past the 0.6 cut.
        raw = ("Remember to call the dentist tomorrow morning.<|end|>"
               "<|assistant|> Remember to call the dentist tomorrow morning.<|end|>")
        out = sanitize_model_output(raw)
        self.assertNotIn("<|", out)
        self.assertIn("Remember to call the dentist tomorrow morning.", out)

    def test_strips_common_template_tokens(self):
        for token in ("<|end|>", "<|assistant|>", "<|im_end|>", "<|eot_id|>",
                      "<|endoftext|>", "<|user|>", "<|system|>"):
            out = sanitize_model_output(f"Hello there.{token}")
            self.assertEqual(out, "Hello there.", f"failed to strip {token}")

    def test_does_not_eat_ordinary_angle_brackets(self):
        # A dictated transcript can legitimately contain comparisons or shell
        # redirects. Only <|…|> control tokens should go.
        out = sanitize_model_output("if x < 5 and y > 3 then echo done > out.txt")
        self.assertEqual(out, "if x < 5 and y > 3 then echo done > out.txt")


class TestReasoningPreambleStripping(unittest.TestCase):
    """A1: <think> was only one of three reasoning formats in the wild."""

    def test_strips_complete_think_block(self):
        out = sanitize_model_output("<think>reasoning here</think>The answer.")
        self.assertEqual(out, "The answer.")

    def test_strips_truncated_think_block(self):
        # Qwen3 hitting max_tokens mid-thought: no closing tag.
        out = sanitize_model_output("<think>reasoning that never finishes")
        self.assertEqual(out, "")

    def test_strips_gemma4_channel_thought(self):
        # gemma-4-e2b, terminal_homophones — verbatim prefix from the benchmark.
        raw = ("<|channel>thought\nThinking Process:\n\n1.  **Analyze the Request:** "
               "The goal is to clean up a transcribed speech intended for a terminal")
        self.assertEqual(sanitize_model_output(raw), "")

    def test_strips_bare_thinking_process_heading(self):
        # Qwen3.5-4B, terminal_homophones — no tags whatsoever.
        raw = ('Thinking Process:\n\n1.  **Analyze the Request:**\n    *   Input: '
               'A speech transcription ("um so run suit oh apt update").')
        self.assertEqual(sanitize_model_output(raw), "")

    def test_strips_thinking_and_thought_variants(self):
        for heading in ("Thinking Process:", "Thought Process:"):
            self.assertEqual(sanitize_model_output(f"{heading}\n\n1. Analyze"), "")

    def test_heading_match_is_case_insensitive(self):
        self.assertEqual(sanitize_model_output("THINKING PROCESS:\n\n1. Analyze"), "")

    def test_bare_reasoning_heading_is_deliberately_NOT_stripped(self):
        # Asymmetric risk: someone dictating notes could genuinely open with
        # "Reasoning:". Failing to strip costs a rejected correction; stripping
        # wrongly destroys the user's words. We choose the safe error.
        raw = "Reasoning: the deploy failed because the lock file was stale."
        self.assertEqual(sanitize_model_output(raw), raw)

    def test_heading_without_structured_reasoning_is_kept(self):
        # No list/bold after the colon -> probably real dictation, not a model
        # reasoning dump.
        raw = "Thinking process: we should ship on Friday."
        self.assertEqual(sanitize_model_output(raw), raw)

    def test_only_strips_heading_at_the_start(self):
        # Critical: the phrase can appear inside a legitimate transcript. Anchor
        # at the start, or we would delete real dictated content.
        raw = "I want to document our thinking process: first we scope it, then we build."
        self.assertEqual(sanitize_model_output(raw), raw)


class TestEmptyResultDrivesRetry(unittest.TestCase):
    """Returning "" is the DESIRED outcome for a reasoning-only response.

    `correct()` treats empty as "model produced only reasoning" and retries with
    thinking disabled. Guessing an answer out of a truncated reasoning dump would
    be worse than admitting there isn't one.
    """

    def test_reasoning_only_yields_empty_so_caller_can_retry(self):
        for raw in (
            "<think>only thinking",
            "<|channel>thought\nThinking Process:\n1. Analyze",
            "Thinking Process:\n1. Analyze",
        ):
            self.assertEqual(sanitize_model_output(raw), "")

    def test_none_and_empty_are_safe(self):
        self.assertEqual(sanitize_model_output(""), "")


class TestPreservesGoodOutput(unittest.TestCase):
    """The sanitiser must not damage output that was already fine."""

    def test_plain_correction_untouched(self):
        text = "Remind me to call the dentist tomorrow morning."
        self.assertEqual(sanitize_model_output(text), text)

    def test_terminal_correction_untouched(self):
        # The shell syntax a good terminal correction produces.
        text = "sudo apt update && cd ~/Documents && grep -v error | less"
        self.assertEqual(sanitize_model_output(text), text)

    def test_surrounding_quotes_are_trimmed(self):
        self.assertEqual(sanitize_model_output('"Corrected text."'), "Corrected text.")

    def test_multiline_prose_untouched(self):
        text = "Hi Sarah,\n\nI wanted to send you the quarterly report.\n\nBest regards,\nJustin"
        self.assertEqual(sanitize_model_output(text), text)


class TestSafeMergeInteraction(unittest.TestCase):
    """The whole point: sanitised output must survive the app's 0.6 guard."""

    @staticmethod
    def _ratio(a, b):
        if a == b:
            return 0.0
        if not a or not b:
            return 1.0
        shorter, longer = (a, b) if len(a) <= len(b) else (b, a)
        prev = list(range(len(shorter) + 1))
        cur = [0] * (len(shorter) + 1)
        for i in range(1, len(longer) + 1):
            cur[0] = i
            for j in range(1, len(shorter) + 1):
                cost = 0 if longer[i - 1] == shorter[j - 1] else 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            prev, cur = cur, prev
        return prev[len(shorter)] / max(len(a), len(b))

    def test_phi_output_now_passes_safemerge(self):
        original = "uh remind me to call the dentist tomorrow morning"
        raw = ("Remember to call the dentist tomorrow morning.<|end|>"
               "<|assistant|> Remember to call the dentist tomorrow morning.<|end|>")

        before = self._ratio(original, raw)
        after = self._ratio(original, sanitize_model_output(raw))

        self.assertGreater(before, 0.6, "fixture should reproduce the original rejection")
        self.assertLess(after, 0.6, "sanitised output must now be accepted by safeMerge")


if __name__ == "__main__":
    unittest.main(verbosity=2)
