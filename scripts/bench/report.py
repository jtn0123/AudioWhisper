"""Build reproducible metrics and exportable charts from retained transcripts."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import statistics

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from scoring import aggregate_counts, error_counts, required_terms_retained
from writing_cases import cases

LABELS = {
    "parakeet-v2": "Parakeet v2", "parakeet-v3": "Parakeet v3",
    "granite-5": "Granite 5 TurboCTC", "cohere-8bit": "Cohere Transcribe · 8-bit",
    "qwen3-asr-4bit": "Qwen3 ASR · 4-bit",
    "whisper-large-v3_turbo": "Whisper Large v3 Turbo", "whisper-small": "Whisper Small",
    "whisper-base": "Whisper Base", "whisper-tiny": "Whisper Tiny",
    "writing-qwen4b": "Qwen3 4B", "writing-gemma1b": "Gemma 3 1B",
    "writing-qwen1.7b": "Qwen3 1.7B", "writing-lfm1.2b": "LFM2.5 1.2B",
    "writing-qwen3.5-2b": "Qwen3.5 2B", "writing-gemma4": "Gemma 4 E2B",
}
NATURAL = ["librispeech-clean", "librispeech-other", "ami-meetings"]
DAY_ALIASES = {"Tuesday": ["Tue", "Tues"], "Thursday": ["Thu", "Thur", "Thurs"]}


def read_events(path: Path):
    return [json.loads(line) for line in path.read_text().splitlines()]


def bootstrap(counts, seed=20261005):
    # Exploratory interval over this sampled set, not full-dataset confidence.
    rng = np.random.default_rng(seed)
    errors = np.array([row["errors"] for row in counts])
    words = np.array([row["reference_words"] for row in counts])
    indices = rng.integers(0, len(counts), size=(3000, len(counts)))
    values = 100 * errors[indices].sum(axis=1) / words[indices].sum(axis=1)
    return list(np.quantile(values, [.025, .975]))


def literal_terms(text, terms):
    return [term for term in terms if term.casefold() not in text.casefold()]


def evaluate_writing(row, task):
    text = row["delivered"]
    aliases = dict(DAY_ALIASES, **task["aliases"])
    missing = required_terms_retained(text, task["keep"], aliases)["missing"]
    repairs = required_terms_retained(text, task["fixes"], aliases)["missing"]
    # Fillers must be inspected before WER normalization removes them.
    fillers = [term for term in task["drop"] if re.search(r"(?<!\w)" + re.escape(term) + r"(?!\w)", text, re.I)]
    forbidden = required_terms_retained(text, task["forbid"])["kept"]
    literal_missing = literal_terms(text, task["literal"])
    return dict(case=row["case"], repetition=row["repetition"], category=row["category"],
                pass_checks=not any([missing, repairs, fillers, forbidden, literal_missing]),
                missing_meaning_terms=missing, missing_repairs=repairs, leftover_fillers=fillers,
                forbidden_terms=forbidden, missing_literals=literal_missing,
                guard_rejected=row["guard_rejected"], input=row["input"], raw=row["text"], delivered=text)


def plot_asr(rows, destination):
    order = sorted(rows, key=lambda item: item["warm_median_seconds"])
    colors = ["#177B6B" if row["current"] else "#426DD4" for row in order]
    fig, axes = plt.subplots(1, 2, figsize=(14, 7), sharey=True, gridspec_kw={"wspace": .15})
    fig.patch.set_facecolor("#F6F7F9")
    y = np.arange(len(order))
    speed = [row["warm_median_seconds"] for row in order]
    quality = [row["natural"]["wer_percent"] for row in order]
    axes[0].barh(y, speed, color=colors, height=.56)
    axes[1].barh(y, quality, color=colors, height=.56)
    for axis, values in zip(axes, [speed, quality]):
        axis.set_facecolor("#F6F7F9")
        axis.spines[["top", "right", "left"]].set_visible(False)
        axis.spines["bottom"].set_color("#CDD3DE")
        axis.grid(axis="x", color="#DCE1E9", linewidth=.7)
        axis.set_axisbelow(True)
        axis.tick_params(axis="both", length=0, labelsize=10, pad=8)
        axis.set_xlim(0, max(values) * 1.24)
        for position, value in enumerate(values):
            label = f"{value:.2f} s" if axis is axes[0] else f"{value:.1f}"
            axis.text(value + max(values) * .02, position, label, va="center", fontsize=10, fontweight="bold", color="#253247")
    axes[0].set_yticks(y, [LABELS[row["model_id"]] for row in order])
    axes[0].invert_yaxis()
    axes[0].set_title("Wait after 61 seconds of speech", loc="left", fontsize=13, fontweight="bold", pad=20)
    axes[1].set_title("Word mistakes per 100 words", loc="left", fontsize=13, fontweight="bold", pad=20)
    axes[0].set_xlabel("Seconds · lower is better", labelpad=15)
    axes[1].set_xlabel("Errors · lower is better", labelpad=15)
    fig.suptitle("English transcription on your M5 Pro", x=.03, y=.98, ha="left", fontsize=22, fontweight="bold", color="#182338")
    fig.text(.03, .90, "48 GB RAM  ·  5 speed repeats  ·  48 natural English clips / 922 reference words", fontsize=11, color="#536077")
    fig.text(.03, .025, "Green = currently offered in the app    Blue = challengers    |    Model inference only; first-use and safety checks in the report.", fontsize=10, color="#536077")
    fig.subplots_adjust(left=.235, right=.97, top=.79, bottom=.14)
    fig.savefig(destination, dpi=160)
    plt.close(fig)


def plot_writing(rows, destination):
    order = sorted(rows, key=lambda item: item["warm_median_seconds"])
    colors = ["#177B6B" if row["current"] else "#426DD4" for row in order]
    fig, axes = plt.subplots(1, 2, figsize=(12, 5.5), sharey=True)
    fig.patch.set_facecolor("#F6F7F9")
    y = np.arange(len(order))
    manual = all("manual_passes" in row for row in order)
    total = 28 if manual else 56
    quality = [row["manual_passes"] if manual else row["passes"] for row in order]
    for axis, values, title in zip(axes,
            [[row["warm_median_seconds"] for row in order], quality],
            ["Time to clean a short transcript", f"Passed reviewed tasks out of {total}" if manual else f"Passed task checks out of {total}"]):
        axis.barh(y, values, color=colors, height=.55)
        axis.set_facecolor("#F6F7F9")
        axis.spines[["top", "right", "left"]].set_visible(False)
        axis.grid(axis="x", alpha=.2)
        axis.set_axisbelow(True)
        axis.tick_params(length=0)
        axis.set_title(title, loc="left", fontsize=12, pad=20)
        axis.set_xlim(0, max(values) * 1.25)
        for position, value in enumerate(values):
            label = f"{value:.2f} s" if axis is axes[0] else f"{value:.0f}/{total}"
            axis.text(value + max(values) * .025, position, label, va="center", fontsize=10)
    axes[0].set_yticks(y, [LABELS[row["model_id"]] for row in order])
    axes[0].invert_yaxis()
    axes[0].set_xlabel("Lower is better")
    axes[1].set_xlabel("Higher is better · delivered text after app guard")
    fig.suptitle("Optional text cleanup on your M5 Pro", x=.03, ha="left", fontsize=19, fontweight="bold")
    note = "28 tasks · one qualitative reviewer · repeated outputs matched. Small quality differences are inconclusive." if manual else "28 tasks × 2 repeats. Checks cover requested repairs and preservation; they do not establish complete semantic correctness."
    fig.text(.03, .03, note, fontsize=9)
    fig.text(.03, .08, "Green = currently offered in the app    Blue = challengers", fontsize=9, color="#536077")
    fig.subplots_adjust(left=.20, right=.96, top=.76, bottom=.17, wspace=.20)
    fig.savefig(destination, dpi=160)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    args.destination.mkdir(parents=True, exist_ok=True)
    corpus = json.loads((args.base / "corpus/manifest.json").read_text())
    reference = {row["id"]: row for row in corpus}
    tasks = {row["id"]: row for row in cases()}
    registry = json.loads((args.base / "models.json").read_text())
    review_path = args.destination / "writing-manual-review.json"
    manual_review = json.loads(review_path.read_text())["models"] if review_path.exists() else {}
    speech, writing, details = [], [], {}
    for ident, entry in registry.items():
        path = args.base / "results" / (ident + ".jsonl")
        delivered = path.with_suffix(".delivered.jsonl")
        if not path.exists() or not delivered.exists():
            continue
        events = read_events(path)
        if not any(row["kind"] == "complete" and not row.get("failures", 0) for row in events):
            continue
        measured = read_events(delivered)
        loaded = next(row for row in events if row["kind"] == "loaded")
        common = dict(model_id=ident, current=entry["runtime"] in ["current", "writing-current", "whisper"],
                      load_seconds=loaded["load_seconds"], rss_peak_gb=max(row["rss_peak_bytes"] for row in events) / 1e9,
                      mlx_peak_gb=max(row.get("mlx_peak_bytes", 0) for row in events) / 1e9,
                      model_files_gb=entry["logical_bytes"] / 1e9,
                      errors=[row for row in events if row["kind"] == "error"])
        if ident.startswith("writing"):
            checks = [evaluate_writing(row, tasks[row["case"]]) for row in measured]
            warm = [row["seconds"] for row in measured if not (row["case"] == "writing-0" and row["repetition"] == 0)]
            first = measured[0]
            if ident in manual_review:
                reviewed = manual_review[ident]
                outputs = [(row["case"], row["delivered"]) for row in measured if row["repetition"] == 0]
                digest = hashlib.sha256(json.dumps(outputs, ensure_ascii=False).encode()).hexdigest()
                if digest != reviewed["first_repetition_output_sha256"]:
                    raise ValueError(f"Manual review is stale for {ident}; review changed outputs first")
                common.update(manual_passes=reviewed["passes"], manual_total=reviewed["total"])
            common.update(warm_median_seconds=statistics.median(warm), p90_seconds=float(np.quantile(warm, .9)),
                          passes=sum(row["pass_checks"] for row in checks), total=len(checks),
                          preservation_passes=sum(not row["missing_meaning_terms"] and not row["missing_literals"] for row in checks),
                          guard_rejections=sum(row["guard_rejected"] for row in checks),
                          repair_passes=sum(row["pass_checks"] for row in checks if tasks[row["case"]]["fixes"] or tasks[row["case"]]["drop"] or literal_terms(tasks[row["case"]]["input"], tasks[row["case"]]["literal"])),
                          repair_total=sum(bool(tasks[row["case"]]["fixes"] or tasks[row["case"]]["drop"] or literal_terms(tasks[row["case"]]["input"], tasks[row["case"]]["literal"])) for row in checks),
                          first_use_seconds=first["process_to_result_seconds"],
                          by_category={category: dict(passes=sum(row["pass_checks"] for row in checks if row["category"] == category),
                               total=sum(row["category"] == category for row in checks)) for category in {row["category"] for row in checks}})
            writing.append(common)
            details[ident] = checks
        else:
            per_case = [dict(case=row["case"], group=row["group"],
                        raw=error_counts(reference[row["case"]]["reference"], row["text"]),
                        delivered=error_counts(reference[row["case"]]["reference"], row["delivered"]),
                        terms=required_terms_retained(row["delivered"], reference[row["case"]]["required"],
                              {"5th": ["5"], "9:30": ["9.30", "930", "nine thirty"]})) for row in measured]
            natural = [row["delivered"] for row in per_case if row["group"] in NATURAL]
            speed = [row["seconds"] for row in events if row["kind"] == "speed"]
            first = next(row for row in events if row["kind"] == "first-use")
            common.update(warm_median_seconds=statistics.median(speed), warm_min_seconds=min(speed), warm_max_seconds=max(speed),
                          first_use_seconds=first["process_to_first_result_seconds"],
                          short_clip_median_seconds=statistics.median(row["seconds"] for row in measured if row["group"] in NATURAL),
                          natural=aggregate_counts(natural), natural_interval_95=bootstrap(natural),
                          raw_natural=aggregate_counts([row["raw"] for row in per_case if row["group"] in NATURAL]),
                          groups={group: aggregate_counts([row["delivered"] for row in per_case if row["group"] == group]) for group in {row["group"] for row in per_case}},
                          silence_nonempty=sum(bool(row["delivered"].strip()) for row in measured if row["group"] == "non-speech"),
                          silence_outputs=[dict(case=row["case"], text=row["delivered"]) for row in measured if row["group"] == "non-speech"],
                          synthetic_missing_terms=[dict(case=row["case"], missing=row["terms"]["missing"]) for row in per_case if row["terms"]["missing"]],
                          long_seconds=next(row["seconds"] for row in measured if row["group"] == "long-form"))
            speech.append(common)
            details[ident] = per_case
    (args.destination / "metrics.json").write_text(json.dumps(dict(speech=speech, writing=writing), indent=2) + "\n")
    (args.destination / "scored-cases.json").write_text(json.dumps(details, indent=2) + "\n")
    if "parakeet-v2" in details:
        baseline = [row for row in details["parakeet-v2"] if row["group"] in NATURAL]
        rng = np.random.default_rng(20261005)
        indices = rng.integers(0, len(baseline), size=(3000, len(baseline)))
        words = np.array([row["delivered"]["reference_words"] for row in baseline])
        errors = np.array([row["delivered"]["errors"] for row in baseline])
        paired = {}
        for row in speech:
            ident = row["model_id"]
            if ident == "parakeet-v2": continue
            lookup = {item["case"]: item["delivered"]["errors"] for item in details[ident]}
            delta = np.array([lookup[item["case"]] for item in baseline]) - errors
            resampled = 100 * delta[indices].sum(axis=1) / words[indices].sum(axis=1)
            paired[ident] = dict(wer_delta_percentage_points=100 * delta.sum() / words.sum(),
                                paired_clip_bootstrap_95=list(np.quantile(resampled, [.025, .975])))
        (args.destination / "paired-differences.json").write_text(json.dumps(paired, indent=2) + "\n")
    if speech: plot_asr(speech, args.destination / "speech-comparison.png")
    if writing: plot_writing(writing, args.destination / "cleanup-comparison.png")
    print(json.dumps(dict(speech=speech, writing=writing), indent=2))


if __name__ == "__main__":
    main()
