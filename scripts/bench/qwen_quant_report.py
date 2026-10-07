"""Report manually reviewed published MLX builds with matched same-session controls."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics
import subprocess

from postprocess import build_helper

MODELS = {
    "qwen3-4b": "Qwen3 4B · 4-bit (current)",
    "qwen3.5-9b": "Qwen3.5 9B · 4-bit",
    "qwen3.5-9b-8bit": "Qwen3.5 9B · 8-bit",
    "qwen3.8-27b": "Qwen3.8 27B · 4-bit",
    "qwen3.8-27b-3bit": "Qwen3.8 27B · mixed 3-bit",
    "qwen3.8-27b-6bit": "Qwen3.8 27B · 6-bit",
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("--postprocess-only", action="store_true")
    args = parser.parse_args()
    base = args.base
    status = json.loads((base / "run-status-direct-strict.json").read_text())
    assert all(status.get(ident, {}).get("exit") == 0 for ident in MODELS), "A model worker did not finish successfully"
    expected_cases = [row["id"] for row in json.loads((base / "cases.json").read_text())]
    helper = build_helper(Path(__file__).resolve().parents[2], base)
    raw_by_model = {}
    delivered_by_model = {}
    for ident in MODELS:
        path = base / "results" / f"{ident}-direct-strict.jsonl"
        raw = [json.loads(line) for line in path.read_text().splitlines()]
        assert raw[-1]["kind"] == "complete", f"Incomplete model run: {ident}"
        writing = [row for row in raw if row["kind"] == "writing"]
        assert len(writing) == 128
        result = subprocess.run(
            [str(helper)], input="".join(json.dumps(row) + "\n" for row in writing),
            text=True, capture_output=True, check=True,
        )
        path.with_suffix(".delivered.jsonl").write_text(result.stdout)
        raw_by_model[ident] = raw
        delivered_by_model[ident] = [json.loads(line) for line in result.stdout.splitlines()]
    if args.postprocess_only:
        print("Postprocessed six models / 768 edits using the production Swift guard.")
        return

    reviews = json.loads((base / "manual-review.json").read_text())["reviews"]
    manifest = json.loads((base / "models.json").read_text())
    metrics = {}
    for ident in MODELS:
        raw = raw_by_model[ident]
        for mode in ["direct", "strict"]:
            key = ident + "/" + mode
            rows = [row for row in delivered_by_model[ident] if row["mode"] == mode]
            assert len(rows) == 64
            assert [row["case"] for row in rows] == expected_cases
            review = reviews[key]
            assert review["total"] == 64
            assert review["outputs_sha256"] == hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()
            failures = review["failures"]
            assert review["passes"] == 64 - len(failures)
            assert review["critical_failures"] == sum(f["critical"] for f in failures.values())
            assert set(failures).issubset({row["case"] for row in rows})
            warm_times = [row["seconds"] for row in rows[1:]]
            identical_times = [row["seconds"] for row in raw
                               if row["kind"] == "speed" and row["mode"] == mode and row["repetition"] > 0]
            profiles = {}
            for category in sorted({row["category"] for row in rows}):
                subset = [row for row in rows if row["category"] == category]
                profiles[category] = dict(total=len(subset), acceptable=sum(row["case"] not in failures for row in subset))
            grammar = [row for row in rows if row["focus"] == "grammar"]
            metrics[key] = dict(
                acceptable=review["passes"], total=64,
                critical_failures=review["critical_failures"],
                app_failures=sum(f["component"] == "app" for f in failures.values()),
                median_task_seconds=statistics.median(warm_times),
                p90_task_seconds=sorted(warm_times)[math.ceil(.9 * len(warm_times)) - 1],
                identical_short_task_median_seconds=statistics.median(identical_times),
                identical_short_task_min_seconds=min(identical_times),
                identical_short_task_max_seconds=max(identical_times),
                first_task_seconds=rows[0]["seconds"],
                first_process_result_seconds=rows[0].get("process_to_result_seconds"),
                load_seconds=raw[0]["load_seconds"],
                peak_mlx_bytes=max(row["mlx_peak_bytes"] for row in raw),
                peak_rss_bytes=max(row["rss_peak_bytes"] for row in raw),
                model_bytes=manifest[ident]["logical_bytes"],
                guard_rejections=sum(row["guard_rejected"] for row in rows),
                generation_retries=sum(row["generation_calls"] > 1 for row in rows),
                grammar_acceptable=sum(row["case"] not in failures for row in grammar),
                grammar_total=len(grammar), by_profile=profiles,
            )
    (base / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")

    pairwise = {}
    for variant, control in [
        ("qwen3.5-9b-8bit", "qwen3.5-9b"),
        ("qwen3.8-27b-3bit", "qwen3.8-27b"),
        ("qwen3.8-27b-6bit", "qwen3.8-27b"),
    ]:
        for mode in ["direct", "strict"]:
            key = variant + "/" + mode
            control_key = control + "/" + mode
            variant_failed = set(reviews[key]["failures"])
            control_failed = set(reviews[control_key]["failures"])
            control_rows = {row["case"]: row for row in delivered_by_model[control] if row["mode"] == mode}
            variant_rows = [row for row in delivered_by_model[variant] if row["mode"] == mode]
            pairwise[key] = dict(
                control=control_key,
                improved_cases=sorted(control_failed - variant_failed),
                regressed_cases=sorted(variant_failed - control_failed),
                failed_in_both=sorted(variant_failed & control_failed),
                changed_delivered_outputs=sum(row["delivered"] != control_rows[row["case"]]["delivered"] for row in variant_rows),
                median_task_time_ratio=metrics[key]["median_task_seconds"] / metrics[control_key]["median_task_seconds"],
                identical_short_task_time_ratio=metrics[key]["identical_short_task_median_seconds"] / metrics[control_key]["identical_short_task_median_seconds"],
                peak_mlx_allocation_ratio=metrics[key]["peak_mlx_bytes"] / metrics[control_key]["peak_mlx_bytes"],
            )
    (base / "pairwise.json").write_text(json.dumps(pairwise, indent=2) + "\n")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    names = list(MODELS.values())
    colors = ["#768494", "#489d8b", "#28786b", "#6d5cba", "#a391d1", "#47378c"]
    fig, axes = plt.subplots(1, 3, figsize=(14, 5.8), sharey=True)
    for ax, field, title, unit in [
        (axes[0], "median_task_seconds", "Warm editing time · lower is better", "Seconds"),
        (axes[1], "acceptable", "Acceptable edits · higher is better", "Out of 64; critical failures in parentheses"),
        (axes[2], "peak_mlx_bytes", "Peak MLX allocation · lower is better", "GB; not total app memory"),
    ]:
        values = [metrics[ident + "/direct"][field] / (1e9 if field == "peak_mlx_bytes" else 1) for ident in MODELS]
        bars = ax.barh(names, values, color=colors, height=.65)
        ax.set_title(title, fontsize=11, loc="left", pad=15)
        ax.set_xlabel(unit, fontsize=9)
        ax.spines[["top", "right", "left"]].set_visible(False)
        ax.tick_params(axis="y", length=0, labelsize=10)
        ax.set_xlim(0, max(values) * 1.24)
        for bar, value, ident in zip(bars, values, MODELS):
            label = (f"{value:.2f}s" if field == "median_task_seconds" else
                     f"{value:.1f}" if field == "peak_mlx_bytes" else
                     f"{int(value)} ({metrics[ident + '/direct']['critical_failures']})")
            ax.text(bar.get_width() + max(values) * .025, bar.get_y() + bar.get_height()/2,
                    label, va="center", fontsize=10, fontweight="bold")
    axes[0].invert_yaxis()
    fig.suptitle("Qwen quantized builds on your M5 Pro · same-session 4-bit controls", fontsize=14, x=.035, ha="left")
    fig.text(.035, .025, "64 short English stress cases · thinking disabled · existing app prompts and output guard · one qualitative reviewer", fontsize=9, color="#53616e")
    fig.tight_layout(rect=[.02, .08, .99, .92])
    fig.savefig(base / "qwen-quant-comparison.png", dpi=160)
    plt.close(fig)
    for ident in MODELS:
        print(ident, {mode: {field: metrics[ident + '/' + mode][field]
                            for field in ['acceptable', 'critical_failures', 'median_task_seconds', 'peak_mlx_bytes']}
                      for mode in ['direct', 'strict']})


if __name__ == "__main__":
    main()
