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
~/services/infisical
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
~/repos/personal/foo -> /repos/personal/foo
~/repos/foxway/foo   -> /repos/foxway/foo
~/repos/mobiles/foo  -> /repos/mobiles/foo
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

## Infisical Bootstrap Env

The self-hosted Infisical service has one special secret boundary: the service
`.env` is needed before Infisical is running. Treat it as bootstrap material.

Recommended shape:

```text
real bootstrap env      -> created locally, never committed
encrypted bootstrap env -> ~/.vault/staging/bootstrap-env/infisical-bootstrap.env.enc
bootstrap passphrase    -> human password vault + OS keychain
compose wrapper         -> decrypts to a private temp file, runs compose, deletes temp
```

Do not encrypt the Infisical bootstrap env only with
`LOCAL_VAULT_FILE_ENCRYPTION_KEY` if that key lives in Infisical. That creates a
cold-start loop: if Infisical is down and the plaintext env is gone, the env
cannot be decrypted.

Use the local vault file crypto format with an external bootstrap passphrase, or
use an equivalent OS secret manager flow.

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
