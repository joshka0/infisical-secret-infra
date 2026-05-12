#!/usr/bin/env bash
set -euo pipefail

vault_root="${VAULT_ROOT:-$HOME/.vault}"
service_dir="${INFISICAL_SERVICE_DIR:-$HOME/services/infisical}"
input="${1:-$service_dir/.env}"
output="${INFISICAL_BOOTSTRAP_ENV_ENC:-$vault_root/staging/bootstrap-env/infisical-bootstrap.env.enc}"
keychain_service="${INFISICAL_BOOTSTRAP_KEYCHAIN_SERVICE:-infisical-bootstrap-env-passphrase}"
crypto_script="${LOCAL_VAULT_CRYPTO_SCRIPT:-$vault_root/scripts/vault-file-crypto.mjs}"
account="${USER:-$(id -un)}"

if [[ ! -f "$input" ]]; then
  echo "input_missing=$input" >&2
  exit 2
fi

if [[ ! -f "$crypto_script" ]]; then
  echo "crypto_script_missing=$crypto_script" >&2
  exit 2
fi

if [[ -n "${LOCAL_VAULT_FILE_ENCRYPTION_KEY:-}" ]]; then
  passphrase="$LOCAL_VAULT_FILE_ENCRYPTION_KEY"
elif command -v security >/dev/null 2>&1; then
  if ! security find-generic-password -a "$account" -s "$keychain_service" >/dev/null 2>&1; then
    passphrase="$(openssl rand -base64 48)"
    security add-generic-password \
      -a "$account" \
      -s "$keychain_service" \
      -w "$passphrase" \
      -U >/dev/null
  fi
  passphrase="$(security find-generic-password -a "$account" -s "$keychain_service" -w)"
else
  echo "bootstrap_passphrase_missing=true" >&2
  echo "Set LOCAL_VAULT_FILE_ENCRYPTION_KEY from your bootstrap secret manager." >&2
  exit 2
fi
mkdir -p "$(dirname "$output")"
chmod 700 "$(dirname "$output")"

LOCAL_VAULT_FILE_ENCRYPTION_KEY="$passphrase" \
  node "$crypto_script" encrypt "$input" "$output" >/dev/null

chmod 600 "$output"

key_count="$(awk -F= '/^[A-Za-z_][A-Za-z0-9_]*=/{n++} END{print n+0}' "$input")"
sha256="$(shasum -a 256 "$output" | awk '{print $1}')"

printf 'encrypted=true\n'
printf 'input=%s\n' "$input"
printf 'output=%s\n' "$output"
printf 'keychain_service=%s\n' "$keychain_service"
printf 'key_count=%s\n' "$key_count"
printf 'ciphertext_sha256=%s\n' "$sha256"
