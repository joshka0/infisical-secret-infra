#!/usr/bin/env bash
set -euo pipefail

vault_root="${VAULT_ROOT:-$HOME/.vault}"
service_dir="${INFISICAL_SERVICE_DIR:-$HOME/services/infisical}"
compose_file="${INFISICAL_COMPOSE_FILE:-$service_dir/compose.yaml}"
encrypted_env="${INFISICAL_BOOTSTRAP_ENV_ENC:-$vault_root/staging/bootstrap-env/infisical-bootstrap.env.enc}"
keychain_service="${INFISICAL_BOOTSTRAP_KEYCHAIN_SERVICE:-infisical-bootstrap-env-passphrase}"
crypto_script="${LOCAL_VAULT_CRYPTO_SCRIPT:-$vault_root/scripts/vault-file-crypto.mjs}"
account="${USER:-$(id -un)}"

if [[ ! -f "$encrypted_env" ]]; then
  echo "encrypted_env_missing=$encrypted_env" >&2
  echo "run=$vault_root/scripts/infisical-encrypt-bootstrap-env.sh" >&2
  exit 2
fi

if [[ ! -f "$crypto_script" ]]; then
  echo "crypto_script_missing=$crypto_script" >&2
  exit 2
fi

if [[ -n "${LOCAL_VAULT_FILE_ENCRYPTION_KEY:-}" ]]; then
  passphrase="$LOCAL_VAULT_FILE_ENCRYPTION_KEY"
elif command -v security >/dev/null 2>&1; then
  passphrase="$(security find-generic-password -a "$account" -s "$keychain_service" -w)"
else
  echo "bootstrap_passphrase_missing=true" >&2
  echo "Set LOCAL_VAULT_FILE_ENCRYPTION_KEY from your bootstrap secret manager." >&2
  exit 2
fi
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/infisical-env.XXXXXX")"
tmp_env="$tmp_dir/.env"

cleanup() {
  rm -f "$tmp_env"
  rmdir "$tmp_dir" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

LOCAL_VAULT_FILE_ENCRYPTION_KEY="$passphrase" \
  node "$crypto_script" decrypt "$encrypted_env" "$tmp_env" >/dev/null

chmod 600 "$tmp_env"

cd "$service_dir"
INFISICAL_ENV_FILE="$tmp_env" docker compose --env-file "$tmp_env" -f "$compose_file" "$@"
