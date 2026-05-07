# Architecture

## Responsibility Split

```text
Infisical    -> app/runtime secrets and repo .env replacement
Agent Vault  -> brokered outbound HTTP credentials for agents
Keychain     -> bootstrap material and local automation passphrases
~/.vault     -> local control plane, encrypted staging, reports, scripts
GitLab repo  -> sanitized docs, scripts, templates, and agent runbooks
ssh dev      -> remote encrypted backup storage
```

## Local Infisical

The self-hosted Infisical instance runs from:

```text
/Users/joshka/services/infisical
```

The service exposes the UI locally at:

```text
http://127.0.0.1:18080
```

The service uses Postgres as the durable source of truth. Redis is runtime
supporting state and should not be treated as the primary backup target.

## Secret Paths

Preferred path mapping:

```text
/Users/joshka/repos/personal/foo -> /repos/personal/foo
/Users/joshka/repos/foxway/foo   -> /repos/foxway/foo
/Users/joshka/repos/mobiles/foo  -> /repos/mobiles/foo
home-level secrets               -> /home
migrated raw files               -> /migration/...
```

## File Encryption

Secret-bearing files under `~/.vault` outside Infisical must be encrypted at
rest. The local vault file-encryption key is stored in Infisical under `/home`
as:

```text
LOCAL_VAULT_FILE_ENCRYPTION_KEY
```

The Infisical self-hosted backup passphrase is separate. It must be recoverable
without Infisical, so it belongs in the human password vault and macOS Keychain.

## Backups

Nightly backup flow:

```text
launchd at 03:00
  -> pg_dumpall from infisical-db
  -> bundle service restore metadata
  -> encrypt archive locally
  -> keep local rotation
  -> upload encrypted archive/report to dev when reachable
  -> prune remote rotation
```

Only completed encrypted archives and redacted reports should leave the machine.
