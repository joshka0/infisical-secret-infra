# AGENTS.md - Infisical Secret Infrastructure

This repo documents sensitive infrastructure. Treat it as private even though it
must not contain secret values.

## Prime Directive

Do not print, summarize, quote, or expose secret values.

Report only:

- Paths
- Key names
- Counts
- Hashes
- Presence/missing statuses
- Redacted command outcomes

## Hard Rules

- Do not commit real `.env` files.
- Do not commit Infisical exports.
- Do not commit backup archives, plaintext dumps, decrypted files, or encrypted
  local vault artifacts.
- Do not run `env`, `printenv`, `infisical secrets --output dotenv`,
  `infisical export`, or `cat .env` as discovery commands.
- Use `rg`/code inspection to discover required environment variable names.
- Use Infisical presence checks that print only `present` or `missing`.
- Use `--silent` and redirect output for imports because Infisical CLI can print
  values in tables.
- If a secret-bearing file must remain on disk outside Infisical, encrypt it at
  rest and delete plaintext.
- The Infisical backup passphrase must be recoverable from a human password
  vault and must not live only inside Infisical.

## Agent Workflow For Repo `.env` Migration

1. Identify the target repo and desired Infisical path.
2. Inspect code/config for key names only.
3. If a real `.env` exists, import it with the vault helper without printing it.
4. Verify key presence with `present`/`missing` output only.
5. Remove plaintext `.env` from the repo.
6. Add or verify `.gitignore` coverage.
7. Add repo guidance for `infisical run`.
8. Report key counts, destination path, and any suspected typo key names.

## Recommended Local Paths

```text
~/.vault
~/.vault/AGENTS.md
~/services/infisical
~/.vault/scripts/infisical-import-dotenv.sh
~/.vault/scripts/backup-infisical-if-changed.sh
```

The local vault `AGENTS.md` is the machine-specific operating contract. If it
disagrees with this repo, follow the local vault file first and then update this
repo or local override.

For a new machine, start with [setup.md](setup.md).
