"""Protect benchmark interpretation rather than any model implementation."""
import pytest

from scoring import aggregate_counts, error_counts, normalize, required_terms_retained


def test_semantic_checks_keep_meaningful_parentheses_and_brackets():
    result = required_terms_retained("Send it (including taxes) to Jordan [the editor].", ["including taxes", "the editor"])
    assert result["missing"] == []


def test_semantic_checks_preserve_negative_spoken_amounts():
    assert required_terms_retained("The balance is negative forty two dollars", ["negative $42"])["missing"] == []
    assert required_terms_retained("The balance is forty two dollars", ["negative $42"])["missing"] == ["negative $42"]


def test_clock_format_aliases_are_accepted_without_accepting_other_times():
    aliases = {"9:30": ["9.30", "930"]}
    assert required_terms_retained("Come at 9.30", ["9:30"], aliases)["missing"] == []
    assert required_terms_retained("Come at 9:45", ["9:30"], aliases)["missing"] == ["9:30"]


def test_number_formatting_does_not_count_as_an_asr_error():
    assert error_counts("Twenty one dollars", "$21")["errors"] == 0


def test_missing_negation_is_a_real_error():
    result = error_counts("do not send the report", "do send the report")
    assert result["deletions"] == 1
    assert result["errors"] == 1


def test_aggregate_weights_words_not_clips():
    result = aggregate_counts([
        error_counts("one", "two"),
        error_counts("the quick brown fox jumps over the lazy dog", "the quick brown fox jumps over the lazy dog"),
    ])
    assert result["reference_words"] == 10
    assert result["wer_percent"] == pytest.approx(10)


def test_silence_insertions_are_not_called_zero_error():
    result = error_counts("", "thanks for watching")
    assert result["insertions"] == 3
    assert result["reference_words"] == 0
    assert aggregate_counts([result])["wer_percent"] is None


def test_entity_checks_match_complete_terms():
    assert required_terms_retained("GitHub and Sudo", ["git", "sudo"])["kept"] == ["sudo"]


def test_normalization_keeps_meaningful_words():
    assert "not" in normalize("Please do not delete it.").split()


def test_curly_apostrophes_do_not_hide_negation():
    assert error_counts("Do not send it", "Don’t send it")["errors"] == 0
