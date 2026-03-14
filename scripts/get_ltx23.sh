#!/usr/bin/env bash
# /opt/get_ltx23.sh  (resume-friendly)
set -euo pipefail

export HF_HUB_ENABLE_HF_TRANSFER=1
export HF_HOME="${HF_HOME:-$HOME/.cache/huggingface}"   # persistent HF cache
HF="/opt/venv/bin/hf"

MODEL_HOME="$HOME/comfy-models"
STAGE="$MODEL_HOME/.hf_stage_ltx23"                     # persistent staging (enables resume)

# Repositories
REPO_CHECKPOINT="Lightricks/LTX-2.3"
REPO_TEXT_ENC="Comfy-Org/ltx-2"                          # Same Gemma 3 text encoder as LTX-2.0

mkdir -p "$MODEL_HOME"/{checkpoints,text_encoders,loras,latent_upscale_models}
mkdir -p "$STAGE"

download_if_missing () {
  local repo="$1"
  local remote="$2"
  local dest_path="$3"  # Relative path under MODEL_HOME

  local dest_dir="$MODEL_HOME/$dest_path"
  local dest_file="$dest_dir/$(basename "$remote")"
  local staged="$STAGE/$remote"

  if [[ -f "$dest_file" ]]; then
    echo "✓ Already present: $dest_file"
    return
  fi

  echo "↓ Downloading $(basename "$remote") → $dest_file"
  mkdir -p "$(dirname "$staged")"
  mkdir -p "$dest_dir"

  "$HF" download "$repo" "$remote" \
      --repo-type model \
      --cache-dir "$HF_HOME" \
      --local-dir "$STAGE"
  mv -f "$staged" "$dest_file"
}

usage() {
  cat <<'USAGE'
Usage: get_ltx23.sh <target> [variant]

Targets:
  common       Gemma 3 12B IT text encoder (FP4 mixed) — shared with LTX-2.0
  checkpoint   LTX-2.3 22B checkpoint (Default: dev. Use 'distilled' for distilled)
  lora         LTX-2.3 distilled LoRA
  upscalers    Spatial (x1.5 + x2) + Temporal (x2) upscalers

Maintenance:
  clean-stage   Remove staging folder (keeps final models)
  clean-cache   Remove Hugging Face cache (~/.cache/huggingface)

Notes:
- Downloads RESUME automatically via persistent --cache-dir and --local-dir.
- Text encoder is the same Gemma 3 12B as LTX-2.0; if already present, it skips.
USAGE
}

case "${1:-}" in
  common)
    echo "==> Gemma 3 12B IT Text Encoder (FP4 mixed)"
    download_if_missing "$REPO_TEXT_ENC" "split_files/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors" "text_encoders"
    ;;

  checkpoint)
    VARIANT="${2:-dev}"
    echo "==> LTX-2.3 22B Checkpoint ($VARIANT)"
    case "$VARIANT" in
      dev)       download_if_missing "$REPO_CHECKPOINT" "ltx-2.3-22b-dev.safetensors" "checkpoints" ;;
      distilled) download_if_missing "$REPO_CHECKPOINT" "ltx-2.3-22b-distilled.safetensors" "checkpoints" ;;
      *)         echo "Unknown variant: $VARIANT (expected: dev, distilled)" >&2; exit 1 ;;
    esac
    ;;

  lora)
    echo "==> LTX-2.3 Distilled LoRA"
    download_if_missing "$REPO_CHECKPOINT" "ltx-2.3-22b-distilled-lora-384.safetensors" "loras"
    ;;

  upscalers)
    echo "==> LTX-2.3 Upscalers"
    download_if_missing "$REPO_CHECKPOINT" "ltx-2.3-spatial-upscaler-x1.5-1.0.safetensors" "latent_upscale_models"
    download_if_missing "$REPO_CHECKPOINT" "ltx-2.3-spatial-upscaler-x2-1.0.safetensors" "latent_upscale_models"
    download_if_missing "$REPO_CHECKPOINT" "ltx-2.3-temporal-upscaler-x2-1.0.safetensors" "latent_upscale_models"
    ;;

  clean-stage)
    rm -rf "$STAGE"; echo "✓ Removed stage: $STAGE"
    ;;
  clean-cache)
    rm -rf "$HF_HOME"; echo "✓ Removed HF cache: $HF_HOME"
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    echo "Unknown target: $1" >&2
    usage
    exit 1
    ;;
esac

echo "✓ Done."
