"""Summarize manually reviewed Qwen trials without treating checks as meaning."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import statistics
import subprocess

from postprocess import build_helper

MODELS = ["qwen3-4b", "qwen3.5-4b", "qwen3.5-9b", "qwen3.8-27b"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    args = parser.parse_args()
    base = args.base
    binary = build_helper(Path(__file__).resolve().parents[2], base)
    for ident in MODELS:
        for suffix in ["", "-strict"]:
            path = base / "results" / f"{ident}{suffix}.jsonl"
            rows = [json.loads(line) for line in path.read_text().splitlines()]
            writing = [row for row in rows if row["kind"] == "writing"]
            result = subprocess.run(
                [str(binary)], input="".join(json.dumps(row) + "\n" for row in writing),
                text=True, capture_output=True, check=True,
            )
            path.with_suffix(".delivered.jsonl").write_text(result.stdout)
    review = json.loads((base / "manual-review.json").read_text())
    manifest = json.loads((base / "models.json").read_text())
    metrics = {}
    for ident in MODELS:
        for suffix in ["", "-strict"]:
            path = base / "results" / f"{ident}{suffix}.jsonl"
            raw = [json.loads(l) for l in path.read_text().splitlines()]
            delivered_path = path.with_suffix(".delivered.jsonl")
            delivered = [json.loads(l) for l in delivered_path.read_text().splitlines()]
            for mode in {r["mode"] for r in delivered}:
                rows = [r for r in delivered if r["mode"] == mode]
                key = ident + "/" + mode
                if len(rows) != 64:
                    # Qwen3.8 production is a bounded compatibility diagnostic.
                    assert ident == "qwen3.8-27b" and mode == "production" and len(rows) == 19
                    metrics[key] = dict(diagnostic=True, cases=len(rows),
                                        guard_rejections=sum(r["guard_rejected"] for r in rows),
                                        median_seconds=statistics.median(r["seconds"] for r in rows))
                    continue
                quality = review["reviews"][key]
                assert quality["outputs_sha256"] == hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()
                failures = quality["failures"]
                assert quality["passes"] == 64 - len(failures)
                assert quality["critical_failures"] == sum(item["critical"] for item in failures.values())
                assert set(failures).issubset({row["case"] for row in rows})
                groups = {}
                for category in sorted({r["category"] for r in rows}):
                    chosen = [r for r in rows if r["category"] == category]
                    groups[category] = dict(total=len(chosen), passes=sum(r["case"] not in failures for r in chosen))
                speed = [r["seconds"] for r in raw if r["kind"] == "speed" and r["mode"] == mode and r["repetition"] > 0]
                grammar = [r for r in rows if r["focus"] == "grammar"]
                legacy = [r for r in rows if r["case"].startswith("writing-")]
                metrics[key] = dict(
                    median_task_seconds=statistics.median(r["seconds"] for r in rows[1:]),
                    identical_short_task_median_seconds=statistics.median(speed),
                    first_task_seconds=rows[0]["seconds"],
                    first_process_result_seconds=rows[0].get("process_to_result_seconds"),
                    acceptable=quality["passes"], total=64,
                    critical_failures=quality["critical_failures"],
                    app_failures=sum(v["component"] == "app" for v in failures.values()),
                    legacy_acceptable=sum(r["case"] not in failures for r in legacy), legacy_total=len(legacy),
                    grammar_acceptable=sum(r["case"] not in failures for r in grammar), grammar_total=len(grammar),
                    generation_retries=sum(r["generation_calls"] > 1 for r in rows),
                    guard_rejections=sum(r["guard_rejected"] for r in rows),
                    peak_mlx_bytes=max(r.get("mlx_peak_bytes", 0) for r in raw),
                    peak_rss_bytes=max(r.get("rss_peak_bytes", 0) for r in raw),
                    model_bytes=manifest[ident]["logical_bytes"], by_profile=groups,
                )
    assert len([m for m in metrics.values() if not m.get("diagnostic")]) == 11
    (base / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    names = ["Qwen3 4B\ncurrent", "Qwen3.5 4B", "Qwen3.5 9B", "Qwen3.8 27B"]
    colors = ["#768494", "#489d8b", "#28786b", "#6d5cba"]
    fig, axes = plt.subplots(1, 3, figsize=(13.5, 4.6))
    for ax, field, title, ylabel in [
        (axes[0], "median_task_seconds", "Time to edit · lower is better", "Seconds, median warm task"),
        (axes[1], "acceptable", "Acceptable edits · higher is better", "Tasks accepted out of 64"),
        (axes[2], "critical_failures", "Critical failures · lower is better", "Changed intent / omitted safety constraint"),
    ]:
        values = [metrics[m + "/direct"][field] for m in MODELS]
        bars = ax.bar(names, values, color=colors, width=.65)
        ax.spines[["top", "right"]].set_visible(False)
        ax.set_title(title, fontsize=11, loc="left", pad=14)
        ax.set_ylabel(ylabel, fontsize=9)
        ax.tick_params(axis="x", labelsize=9)
        ax.set_ylim(0, max(values) * 1.18)
        for bar, value in zip(bars, values):
            label = f"{value:.2f}s" if field == "median_task_seconds" else str(value)
            ax.text(bar.get_x() + bar.get_width()/2, bar.get_height()+max(values)*.035,
                    label, ha="center", fontsize=10, fontweight="bold")
    axes[1].set_ylim(0, 70)
    fig.suptitle("Qwen editing on your M5 Pro · thinking disabled, existing app prompts", fontsize=14, x=.06, ha="left")
    fig.text(.06, .03, "64 handcrafted English stress tests · one manual reviewer · processing only · app output guard included", fontsize=9, color="#53616e")
    fig.tight_layout(rect=[.03, .09, .99, .91])
    fig.savefig(base / "qwen-comparison.png", dpi=160)
    plt.close(fig)
    print(json.dumps({m: {mode: metrics[m + "/" + mode] for mode in ["direct", "strict"]} for m in MODELS}, indent=2))


if __name__ == "__main__":
    main()
