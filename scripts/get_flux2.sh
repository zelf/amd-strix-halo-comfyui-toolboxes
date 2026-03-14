#!/usr/bin/env bash
# /opt/get_flux2.sh  (resume-friendly)
set -euo pipefail

export HF_HUB_ENABLE_HF_TRANSFER=1
export HF_HOME="${HF_HOME:-$HOME/.cache/huggingface}"   # persistent HF cache
HF="/opt/venv/bin/hf"

MODEL_HOME="$HOME/comfy-models"
STAGE="$MODEL_HOME/.hf_stage_flux2"                     # persistent staging (enables resume)

# Repositories
# FLUX.2 uses different text encoders per model: Mistral 3 (Dev), Qwen 3 8B (Klein)
# Both share the same FLUX.2 VAE (flux2-vae.safetensors)
REPO_DEV="Comfy-Org/flux2-dev"                                     # Mistral 3 text enc + VAE + fp8 diffusion model
REPO_DEV_GGUF="unsloth/FLUX.2-dev-GGUF"                           # GGUF quantized Dev diffusion models
REPO_KLEIN_ENC="Comfy-Org/vae-text-encorder-for-flux-klein-9b"    # Qwen 3 8B text enc + VAE (note: typo in repo name is upstream)
REPO_KLEIN_GGUF="unsloth/FLUX.2-klein-9B-GGUF"                    # GGUF quantized Klein 9B diffusion models

mkdir -p "$MODEL_HOME"/{diffusion_models,text_encoders,vae}
mkdir -p "$STAGE"

download_if_missing () {
  local repo="$1"
  local remote="$2"
  local dest_path="$3"  # Relative path under MODEL_HOME, e.g., "text_encoders"

  local dest_dir="$MODEL_HOME/$dest_path"
  local dest_file="$dest_dir/$(basename "$remote")"
  local staged="$STAGE/$remote"

  if [[ -f "$dest_file" ]]; then
    echo "✓ Already present: $dest_file"
    return
  fi

  echo "↓ Downloading $(basename "$remote") → $dest_file"
  mkdir -p "$(dirname "$staged")"        # ensure stage path exists
  mkdir -p "$dest_dir"                   # ensure dest dir exists

  "$HF" download "$repo" "$remote" \
      --repo-type model \
      --cache-dir "$HF_HOME" \
      --local-dir "$STAGE"
  mv -f "$staged" "$dest_file"
}

usage() {
  cat <<'USAGE'
Usage: get_flux2.sh <target> [variant]

Targets:
  common     FLUX.2 VAE (shared between Dev and Klein)
  dev        Mistral 3 text encoder + FLUX.2 Dev GGUF (Default: Q8_0)
  klein      Qwen 3 8B text encoder + FLUX.2 Klein 9B GGUF (Default: BF16)

Variants (2nd arg):
  dev:   q8 (default), q4, bf16
  klein: bf16 (default), q8, q4

Maintenance:
  clean-stage   Remove staging folder (keeps final models)
  clean-cache   Remove Hugging Face cache (~/.cache/huggingface)

Notes:
- Downloads RESUME automatically via persistent --cache-dir and --local-dir.
- FLUX.2 uses DIFFERENT text encoders per model (not shared like FLUX.1).
  Dev = Mistral 3, Klein 9B = Qwen 3 8B.
USAGE
}

case "${1:-}" in
  common)
    echo "==> FLUX.2 VAE"
    download_if_missing "$REPO_DEV" "split_files/vae/flux2-vae.safetensors" "vae"
    ;;
  dev)
    VARIANT="${2:-q8}"
    echo "==> FLUX.2 Dev ($VARIANT) + Mistral 3 text encoder"
    # Text encoder (FP8)
    download_if_missing "$REPO_DEV" "split_files/text_encoders/mistral_3_small_flux2_fp8.safetensors" "text_encoders"
    # Diffusion model (GGUF)
    case "$VARIANT" in
      q8)   download_if_missing "$REPO_DEV_GGUF" "flux2-dev-Q8_0.gguf" "diffusion_models" ;;
      q4)   download_if_missing "$REPO_DEV_GGUF" "flux2-dev-Q4_K_M.gguf" "diffusion_models" ;;
      bf16) download_if_missing "$REPO_DEV_GGUF" "flux2-dev-BF16.gguf" "diffusion_models" ;;
      *)    echo "Unknown variant: $VARIANT (expected: q8, q4, bf16)" >&2; exit 1 ;;
    esac
    ;;
  klein)
    VARIANT="${2:-bf16}"
    echo "==> FLUX.2 Klein 9B ($VARIANT) + Qwen 3 8B text encoder"
    # Text encoder (FP4 mixed — recommended by Comfy-Org)
    download_if_missing "$REPO_KLEIN_ENC" "split_files/text_encoders/qwen_3_8b_fp4mixed.safetensors" "text_encoders"
    # Diffusion model (GGUF)
    case "$VARIANT" in
      bf16) download_if_missing "$REPO_KLEIN_GGUF" "flux-2-klein-9b-BF16.gguf" "diffusion_models" ;;
      q8)   download_if_missing "$REPO_KLEIN_GGUF" "flux-2-klein-9b-Q8_0.gguf" "diffusion_models" ;;
      q4)   download_if_missing "$REPO_KLEIN_GGUF" "flux-2-klein-9b-Q4_K_M.gguf" "diffusion_models" ;;
      *)    echo "Unknown variant: $VARIANT (expected: bf16, q8, q4)" >&2; exit 1 ;;
    esac
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
