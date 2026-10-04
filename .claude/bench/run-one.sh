#!/usr/bin/env bash
# Download ONE model to the USB cache, benchmark it, then delete it.
# Peak disk is therefore one model at a time, never the whole candidate set.
#
#   ./run-one.sh mlx-community/Qwen3-1.7B-4bit
set -uo pipefail

REPO="${1:?usage: run-one.sh <hf-repo-id>}"
BENCH=/Volumes/512Flash/aw-model-bench
VENV=/Users/justin/.claude/jobs/1feea920/tmp/lockprobe/.venv/bin

# Downloads land on the USB, NOT in ~/.cache/huggingface. The user's real cache
# (which holds their Parakeet model) is never touched.
export HF_HOME="$BENCH/hf"
export HF_HUB_DISABLE_PROGRESS_BARS=0
export TOKENIZERS_PARALLELISM=false

escaped="models--${REPO//\//--}"
model_dir="$HF_HOME/hub/$escaped"

echo "=============================================================="
echo "MODEL: $REPO"
echo "=============================================================="

echo "--- downloading ---"
dl_start=$(date +%s)
"$VENV/python" -c "
import sys
from huggingface_hub import snapshot_download
snapshot_download('$REPO')
" || { echo 'DOWNLOAD FAILED'; exit 1; }
dl_end=$(date +%s)

size=$(du -sh "$model_dir" 2>/dev/null | cut -f1)
echo "--- downloaded ${size:-?} in $((dl_end - dl_start))s ---"

echo "--- benchmarking ---"
"$VENV/python" "$BENCH/bench.py" "$REPO"
bench_status=$?

echo "--- deleting model to free space ---"
rm -rf "$model_dir"
# Blobs are hard-linked into the snapshot dir; clear any orphans too.
rm -rf "$HF_HOME/hub/.locks/$escaped"
echo "remaining on USB cache: $(du -sh "$HF_HOME" 2>/dev/null | cut -f1)"
echo "free on USB: $(df -h /Volumes/512Flash | tail -1 | awk '{print $4}')"

exit $bench_status
