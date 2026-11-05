"""Summary generation must fail explicitly rather than masquerade as cleanup."""
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Sources"))
from ml.correction import summarize  # noqa: E402


class MeetingSummaryTests(unittest.TestCase):
    def generate(self, output):
        tokenizer = MagicMock()
        tokenizer.apply_chat_template.return_value = "chat prompt"
        with patch("ml.correction.load_correction_model", return_value=(object(), tokenizer)), \
             patch("ml.correction._safe_generate", return_value=output):
            return summarize("local/model", "Maria will send the draft on Tuesday.", None)

    def test_empty_or_echoed_output_is_a_failure(self):
        for output in ["", "<think>reasoning only</think>", "Maria will send the draft on Tuesday."]:
            with self.assertRaises(RuntimeError):
                self.generate(output)

    def test_usable_notes_are_distinct_from_the_source(self):
        result = self.generate("Action: Maria sends the draft Tuesday.")
        self.assertTrue(result["success"])
        self.assertEqual(result["text"], "Action: Maria sends the draft Tuesday.")

    def test_oversized_input_is_rejected_before_loading(self):
        with patch("ml.correction.load_correction_model") as load:
            with self.assertRaises(ValueError):
                summarize("local/model", "x" * 8001, None)
            load.assert_not_called()


if __name__ == "__main__":
    unittest.main()
