#!/usr/bin/env bash
set -euo pipefail

input="${1:-}"
output="${2:-}"
force="${3:-}"
domain="${INFISICAL_API_URL:-http://127.0.0.1:18080}"
control_dir="/Users/joshka/.vault/umbrella/home-root"
crypto_script="/Users/joshka/.vault/scripts/vault-file-crypto.mjs"

if [[ -z "$input" || -z "$output" ]]; then
  echo "Usage: $0 <input.enc> <output> [--force]" >&2
  exit 2
fi

if [[ ! -f "$input" ]]; then
  echo "Encrypted input not found: $input" >&2
  exit 2
fi

args=(decrypt "$input" "$output")
if [[ "$force" == "--force" ]]; then
  args+=(--force)
fi

(
  cd "$control_dir"
  infisical run \
    --env dev \
    --path /home \
    --domain "$domain" \
    --silent \
    -- node "$crypto_script" "${args[@]}"
)

chmod 600 "$output"
