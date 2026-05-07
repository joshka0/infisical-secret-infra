#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  infisical-import-dotenv.sh <dotenv-file> [infisical-path] [environment] [--move-source-to-vault]

Examples:
  /Users/joshka/.vault/scripts/infisical-import-dotenv.sh .env /repos/personal/praze dev --move-source-to-vault
  /Users/joshka/.vault/scripts/infisical-import-dotenv.sh /path/to/repo/.env

Safety:
  - Does not print secret values.
  - Suppresses Infisical import output because the CLI may print values.
  - Reports only key names, counts, hashes, paths, and present/missing status.
USAGE
}

env_file="${1:-}"
secret_path="${2:-}"
environment="${3:-dev}"
move_source="0"
domain="${INFISICAL_API_URL:-http://127.0.0.1:18080}"
control_dir="/Users/joshka/.vault/umbrella/home-root"
vault_root="/Users/joshka/.vault"

for arg in "${@:4}"; do
  case "$arg" in
    --move-source-to-vault)
      move_source="1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$env_file" ]]; then
  usage
  exit 2
fi

if [[ ! -f "$env_file" ]]; then
  echo "Dotenv file not found: $env_file" >&2
  exit 2
fi

case "$env_file" in
  *.example|*.template|*.sample|*.dist)
    echo "Refusing to import template/example file: $env_file" >&2
    exit 2
    ;;
esac

if ! command -v infisical >/dev/null 2>&1; then
  echo "infisical CLI is not installed or not on PATH" >&2
  exit 127
fi

if [[ ! -f "$control_dir/.infisical.json" ]]; then
  echo "Infisical control directory is not linked: $control_dir" >&2
  exit 2
fi

abs_env_dir="$(cd "$(dirname "$env_file")" && pwd -P)"
abs_env_file="$abs_env_dir/$(basename "$env_file")"

infer_secret_path() {
  local file="$1"
  local repo_root
  repo_root="$abs_env_dir"

  while [[ "$repo_root" != "/" && ! -d "$repo_root/.git" ]]; do
    repo_root="$(dirname "$repo_root")"
  done

  case "$repo_root" in
    /Users/joshka/repos/personal/*)
      printf '/repos/personal/%s' "$(basename "$repo_root")"
      ;;
    /Users/joshka/repos/foxway/*)
      printf '/repos/foxway/%s' "$(basename "$repo_root")"
      ;;
    /Users/joshka/repos/mobiles/*)
      printf '/repos/mobiles/%s' "$(basename "$repo_root")"
      ;;
    /Users/joshka/repos/githubs/*)
      printf '/repos/githubs/%s' "$(basename "$repo_root")"
      ;;
    *)
      printf '/migration/dotenv/%s' "$(basename "$(dirname "$file")")"
      ;;
  esac
}

if [[ -z "$secret_path" ]]; then
  secret_path="$(infer_secret_path "$abs_env_file")"
fi

tmp_keys="$(mktemp /tmp/infisical-dotenv-keys.XXXXXX)"
tmp_out="$(mktemp /tmp/infisical-dotenv-import-out.XXXXXX)"
tmp_err="$(mktemp /tmp/infisical-dotenv-import-err.XXXXXX)"
trap 'rm -f "$tmp_keys" "$tmp_out" "$tmp_err"' EXIT

awk -F= '
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*$/ { next }
  /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/ {
    gsub(/[[:space:]]/, "", $1)
    print $1
  }
' "$abs_env_file" | sort -u > "$tmp_keys"

key_count="$(wc -l < "$tmp_keys" | tr -d ' ')"
if [[ "$key_count" == "0" ]]; then
  echo "No dotenv keys found in: $abs_env_file" >&2
  exit 2
fi

sha256="$(shasum -a 256 "$abs_env_file" | awk '{print $1}')"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
safe_name="$(printf '%s' "$abs_env_file" | sed 's#^/Users/joshka/##; s#[^A-Za-z0-9._-]#-#g')"
staging_dir="$vault_root/staging/dotenv-imports"
imports_dir="$vault_root/imports"
mkdir -p "$staging_dir" "$imports_dir"
chmod 700 "$staging_dir" "$imports_dir"

if ! (
  cd "$control_dir"
  infisical secrets set \
    --file "$abs_env_file" \
    --env "$environment" \
    --path "$secret_path" \
    --domain "$domain" \
    --silent >"$tmp_out" 2>"$tmp_err"
); then
  : >"$tmp_out"
  : >"$tmp_err"
  echo "Infisical dotenv import failed for $abs_env_file; output suppressed to avoid leaking values." >&2
  exit 1
fi

: >"$tmp_out"
: >"$tmp_err"

verify_output="$(
  cd "$control_dir"
  infisical run \
    --env "$environment" \
    --path "$secret_path" \
    --domain "$domain" \
    --silent \
    -- sh -lc '
      file="$1"
      missing=0
      total=0
      while IFS= read -r key; do
        [ -n "$key" ] || continue
        total=$((total + 1))
        eval "value=\${$key:-}"
        if [ -z "$value" ]; then
          missing=$((missing + 1))
          printf "missing %s\n" "$key"
        fi
      done < "$file"
      printf "total=%s missing=%s\n" "$total" "$missing"
      [ "$missing" -eq 0 ]
    ' sh "$tmp_keys"
)"

staged_file="$staging_dir/${stamp}-${safe_name}.enc"
crypto_script="$vault_root/scripts/vault-file-crypto.mjs"
if [[ "$move_source" == "1" ]]; then
  (
    cd "$control_dir"
    infisical run \
      --env "$environment" \
      --path /home \
      --domain "$domain" \
      --silent \
      -- node "$crypto_script" encrypt "$abs_env_file" "$staged_file" >/dev/null
  )
  rm -f "$abs_env_file"
else
  (
    cd "$control_dir"
    infisical run \
      --env "$environment" \
      --path /home \
      --domain "$domain" \
      --silent \
      -- node "$crypto_script" encrypt "$abs_env_file" "$staged_file" >/dev/null
  )
fi
chmod 600 "$staged_file"

report="$imports_dir/dotenv-import-${stamp}.report.txt"
{
  printf 'source=%s\n' "$abs_env_file"
  printf 'source_handling=%s\n' "$([[ "$move_source" == "1" ]] && printf encrypted-to-vault-and-removed || printf encrypted-copy-to-vault)"
  printf 'staged_file=%s\n' "$staged_file"
  printf 'infisical_path=%s\n' "$secret_path"
  printf 'env=%s\n' "$environment"
  printf 'domain=%s\n' "$domain"
  printf 'key_count=%s\n' "$key_count"
  printf 'sha256=%s\n' "$sha256"
  printf 'verification=%s\n' "$verify_output"
  printf '\nkeys:\n'
  sed 's/^/- /' "$tmp_keys"
} > "$report"
chmod 600 "$report"

printf 'imported=true\n'
printf 'infisical_path=%s\n' "$secret_path"
printf 'env=%s\n' "$environment"
printf 'key_count=%s\n' "$key_count"
printf 'staged_file=%s\n' "$staged_file"
printf 'report=%s\n' "$report"
if [[ "$move_source" == "1" ]]; then
  printf 'source_removed=true\n'
else
  printf 'source_removed=false\n'
fi
