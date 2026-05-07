#!/usr/bin/env bash
set -euo pipefail

umask 077

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

vault_root="${VAULT_ROOT:-/Users/joshka/.vault}"
service_dir="${INFISICAL_SERVICE_DIR:-/Users/joshka/services/infisical}"
compose_file="${INFISICAL_COMPOSE_FILE:-$service_dir/compose.yaml}"
env_file="${INFISICAL_ENV_FILE:-$service_dir/.env}"
backup_root="${INFISICAL_BACKUP_ROOT:-$vault_root/infisical/backups}"
state_dir="$backup_root/state"
crypto_script="${INFISICAL_BACKUP_CRYPTO_SCRIPT:-$vault_root/scripts/vault-file-crypto.mjs}"

keychain_service="${INFISICAL_BACKUP_KEYCHAIN_SERVICE:-infisical-backup-passphrase}"
keychain_account="${INFISICAL_BACKUP_KEYCHAIN_ACCOUNT:-${USER:-joshka}}"
local_keep="${INFISICAL_BACKUP_LOCAL_KEEP:-7}"
remote_keep="${INFISICAL_BACKUP_REMOTE_KEEP:-14}"
remote="${INFISICAL_BACKUP_REMOTE:-dev}"
remote_dir="${INFISICAL_BACKUP_REMOTE_DIR:-backups/infisical}"

force=0
dry_run=0
no_remote=0
backup_work_dir=""

usage() {
  cat <<'USAGE'
Usage: backup-infisical-if-changed.sh [--force] [--dry-run] [--no-remote]

Creates an encrypted Infisical self-hosted backup only when the snapshot hash
changed since the last successful encrypted backup.

Passphrase source, in order:
  1. INFISICAL_BACKUP_PASSPHRASE
  2. INFISICAL_BACKUP_PASSPHRASE_FILE
  3. macOS Keychain item infisical-backup-passphrase

The passphrase is never printed.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)
      force=1
      ;;
    --dry-run)
      dry_run=1
      ;;
    --no-remote)
      no_remote=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown_arg=$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "error=missing_command command=$1"
    exit 2
  fi
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

load_passphrase() {
  if [ -n "${INFISICAL_BACKUP_PASSPHRASE:-}" ]; then
    printf '%s' "$INFISICAL_BACKUP_PASSPHRASE"
    return 0
  fi

  if [ -n "${INFISICAL_BACKUP_PASSPHRASE_FILE:-}" ]; then
    if [ ! -f "$INFISICAL_BACKUP_PASSPHRASE_FILE" ]; then
      log "error=missing_passphrase_file path=$INFISICAL_BACKUP_PASSPHRASE_FILE"
      return 1
    fi
    LC_ALL=C tr -d '\n' < "$INFISICAL_BACKUP_PASSPHRASE_FILE"
    return 0
  fi

  security find-generic-password \
    -a "$keychain_account" \
    -s "$keychain_service" \
    -w 2>/dev/null
}

require_files() {
  for path in "$service_dir" "$compose_file" "$env_file" "$crypto_script"; do
    if [ ! -e "$path" ]; then
      log "error=missing_required_path path=$path"
      exit 2
    fi
  done
}

write_env_key_list() {
  local output="$1"
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /^[A-Za-z_][A-Za-z0-9_]*=/ {
      split($0, parts, "=")
      print parts[1]
    }
  ' "$env_file" | LC_ALL=C sort > "$output"
}

make_snapshot() {
  local work_dir="$1"
  local payload_dir="$work_dir/payload"
  local metadata_dir="$payload_dir/metadata"

  mkdir -p "$metadata_dir"

  log "snapshot=postgres_dump status=started"
  docker exec infisical-db sh -lc 'pg_dumpall -U "$POSTGRES_USER"' \
    > "$payload_dir/postgres.dump.sql"
  log "snapshot=postgres_dump status=done"

  cp "$compose_file" "$metadata_dir/compose.yaml"
  cp "$env_file" "$metadata_dir/service.env"
  if [ -f "$service_dir/README.md" ]; then
    cp "$service_dir/README.md" "$metadata_dir/service.README.md"
  fi
  write_env_key_list "$metadata_dir/service.env.keys.txt"

  {
    printf 'created_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'host=%s\n' "$(hostname)"
    printf 'service_dir=%s\n' "$service_dir"
    printf 'compose_file=%s\n' "$compose_file"
    printf 'db_container=infisical-db\n'
    printf 'backend_container=infisical-backend\n'
    docker inspect infisical-backend --format 'backend_image={{.Config.Image}}' 2>/dev/null || true
    docker inspect infisical-db --format 'db_image={{.Config.Image}}' 2>/dev/null || true
    docker inspect infisical-redis --format 'redis_image={{.Config.Image}}' 2>/dev/null || true
  } > "$metadata_dir/backup.meta.txt"
}

snapshot_hash() {
  local payload_dir="$1"
  local parts_file="$2"
  local dump_hash

  dump_hash="$(
    sed '/^--/d;/^[[:space:]]*$/d' "$payload_dir/postgres.dump.sql" \
      | shasum -a 256 \
      | awk '{print $1}'
  )"

  {
    printf 'postgres_dump_normalized=%s\n' "$dump_hash"
    printf 'compose=%s\n' "$(sha256_file "$payload_dir/metadata/compose.yaml")"
    printf 'service_env=%s\n' "$(sha256_file "$payload_dir/metadata/service.env")"
    if [ -f "$payload_dir/metadata/service.README.md" ]; then
      printf 'service_readme=%s\n' "$(sha256_file "$payload_dir/metadata/service.README.md")"
    fi
  } > "$parts_file"

  sha256_file "$parts_file"
}

archive_payload() {
  local work_dir="$1"
  local archive_path="$2"

  tar -C "$work_dir" -cf "$archive_path" payload
}

write_report() {
  local report_path="$1"
  local encrypted_path="$2"
  local snapshot="$3"
  local remote_status="$4"
  local remote_target="$5"

  {
    printf 'created_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'service_dir=%s\n' "$service_dir"
    printf 'encrypted_archive=%s\n' "$encrypted_path"
    printf 'encrypted_archive_sha256=%s\n' "$(sha256_file "$encrypted_path")"
    printf 'encrypted_archive_bytes=%s\n' "$(wc -c < "$encrypted_path" | tr -d ' ')"
    printf 'snapshot_hash=%s\n' "$snapshot"
    printf 'local_keep=%s\n' "$local_keep"
    printf 'remote_keep=%s\n' "$remote_keep"
    printf 'remote_status=%s\n' "$remote_status"
    printf 'remote_target=%s\n' "$remote_target"
    printf 'contains=postgres_dump,service_env,compose_metadata\n'
    printf 'secret_values_printed=false\n'
  } > "$report_path"
}

prune_local() {
  mkdir -p "$backup_root"
  find "$backup_root" -maxdepth 1 -type f -name 'infisical-*.tar.enc' -print \
    | LC_ALL=C sort -r \
    | awk -v keep="$local_keep" 'NR > keep { print }' \
    | while IFS= read -r old_archive; do
        rm -f "$old_archive" "${old_archive%.tar.enc}.report.txt"
        log "pruned=local path=$old_archive"
      done
}

upload_remote() {
  local encrypted_path="$1"
  local report_path="$2"

  if [ "$no_remote" -eq 1 ]; then
    printf 'skipped'
    return 0
  fi

  if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$remote" "mkdir -p '$remote_dir'" >/dev/null 2>&1; then
    printf 'unreachable'
    return 0
  fi

  if ! scp -q "$encrypted_path" "$report_path" "${remote}:${remote_dir}/" >/dev/null 2>&1; then
    printf 'failed'
    return 0
  fi

  ssh -o BatchMode=yes -o ConnectTimeout=8 "$remote" "
    cd '$remote_dir' &&
    ls -1r infisical-*.tar.enc 2>/dev/null |
      awk 'NR > $remote_keep { print }' |
      while IFS= read -r f; do
        rm -f -- \"\$f\" \"\${f%.tar.enc}.report.txt\"
      done
  " >/dev/null 2>&1 || true

  printf 'uploaded'
}

upload_latest_existing() {
  if [ "$no_remote" -eq 1 ]; then
    log "changed=false backup=skipped remote_status=skipped"
    return 0
  fi

  local latest_archive
  latest_archive="$(
    find "$backup_root" -maxdepth 1 -type f -name 'infisical-*.tar.enc' -print \
      | LC_ALL=C sort -r \
      | head -n 1
  )"

  if [ -z "$latest_archive" ]; then
    log "changed=false backup=skipped remote_status=no_local_archive"
    return 0
  fi

  local latest_report="${latest_archive%.tar.enc}.report.txt"
  local existing_snapshot="unknown"
  if [ -f "$latest_report" ]; then
    existing_snapshot="$(awk -F= '$1 == "snapshot_hash" { print $2; exit }' "$latest_report")"
    if [ -z "$existing_snapshot" ]; then
      existing_snapshot="unknown"
    fi
  else
    touch "$latest_report"
    chmod 600 "$latest_report"
  fi

  local remote_status
  remote_status="$(upload_remote "$latest_archive" "$latest_report")"
  write_report "$latest_report" "$latest_archive" "$existing_snapshot" "$remote_status" "${remote}:${remote_dir}"
  chmod 600 "$latest_report"

  if [ "$remote_status" = "uploaded" ]; then
    scp -q "$latest_report" "${remote}:${remote_dir}/" >/dev/null 2>&1 || true
  fi

  log "changed=false backup=skipped latest_archive=$latest_archive remote_status=$remote_status"
}

main() {
  need_command docker
  need_command node
  need_command shasum
  need_command tar
  need_command awk
  need_command sed
  need_command security
  require_files

  mkdir -p "$backup_root" "$state_dir"

  if [ "$dry_run" -eq 1 ]; then
    log "dry_run=true service_dir=$service_dir backup_root=$backup_root local_keep=$local_keep remote=${remote}:${remote_dir}"
    log "dry_run=true passphrase_source=env_or_file_or_keychain snapshot_dump=skipped"
    exit 0
  fi

  local passphrase
  passphrase="$(load_passphrase || true)"
  if [ -z "$passphrase" ]; then
    log "error=missing_backup_passphrase keychain_service=$keychain_service"
    exit 2
  fi

  backup_work_dir="$(mktemp -d /private/tmp/infisical-backup.XXXXXX)"
  cleanup() {
    if [ -n "${backup_work_dir:-}" ]; then
      rm -rf "$backup_work_dir"
    fi
  }
  trap cleanup EXIT

  make_snapshot "$backup_work_dir"

  local parts_file="$backup_work_dir/snapshot.parts"
  local snapshot
  snapshot="$(snapshot_hash "$backup_work_dir/payload" "$parts_file")"

  local last_hash_file="$state_dir/last-snapshot.sha256"
  if [ "$force" -eq 0 ] && [ -f "$last_hash_file" ] && [ "$(cat "$last_hash_file")" = "$snapshot" ]; then
    upload_latest_existing
    log "snapshot_hash=$snapshot"
    exit 0
  fi

  local stamp
  stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  local archive_path="$backup_work_dir/infisical-$stamp.tar"
  local encrypted_path="$backup_root/infisical-$stamp.tar.enc"
  local report_path="$backup_root/infisical-$stamp.report.txt"

  archive_payload "$backup_work_dir" "$archive_path"

  log "encrypt=status_started output=$encrypted_path"
  LOCAL_VAULT_FILE_ENCRYPTION_KEY="$passphrase" \
    node "$crypto_script" encrypt "$archive_path" "$encrypted_path" >/dev/null
  chmod 600 "$encrypted_path"

  printf '%s' "$snapshot" > "$last_hash_file"
  chmod 600 "$last_hash_file"

  write_report "$report_path" "$encrypted_path" "$snapshot" "pending" "${remote}:${remote_dir}"
  chmod 600 "$report_path"

  local remote_status
  remote_status="$(upload_remote "$encrypted_path" "$report_path")"
  write_report "$report_path" "$encrypted_path" "$snapshot" "$remote_status" "${remote}:${remote_dir}"
  chmod 600 "$report_path"

  if [ "$remote_status" = "uploaded" ]; then
    scp -q "$report_path" "${remote}:${remote_dir}/" >/dev/null 2>&1 || true
  fi

  prune_local

  log "backup=created encrypted_archive=$encrypted_path remote_status=$remote_status snapshot_hash=$snapshot"
}

main "$@"
