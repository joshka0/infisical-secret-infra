#!/usr/bin/env bash
set -euo pipefail

input="${1:-}"
output="${2:-}"
remove_plaintext="${3:-}"
domain="${INFISICAL_API_URL:-http://127.0.0.1:18080}"
vault_root="${VAULT_ROOT:-${HOME}/.vault}"
control_dir="${INFISICAL_CONTROL_DIR:-$vault_root/umbrella/home-root}"
crypto_script="${VAULT_FILE_CRYPTO_SCRIPT:-$vault_root/scripts/vault-file-crypto.mjs}"

if [[ -z "$input" ]]; then
  echo "Usage: $0 <input> [output.enc] [--remove-plaintext]" >&2
  exit 2
fi

if [[ ! -f "$input" ]]; then
  echo "Input file not found: $input" >&2
  exit 2
fi

if [[ -z "$output" || "$output" == "--remove-plaintext" ]]; then
  output="$input.enc"
  if [[ "${2:-}" == "--remove-plaintext" ]]; then
    remove_plaintext="--remove-plaintext"
  fi
fi

(
  cd "$control_dir"
  infisical run \
    --env dev \
    --path /home \
    --domain "$domain" \
    --silent \
    -- node "$crypto_script" encrypt "$input" "$output"
)

chmod 600 "$output"

if [[ "$remove_plaintext" == "--remove-plaintext" ]]; then
  rm -f "$input"
  echo "plaintext_removed=true"
else
  echo "plaintext_removed=false"
fi
