# Repo `.env` Migration Runbook

Use this when a repo has a plaintext `.env` or a new secret needs to move into
Infisical.

## Goal

Move secrets out of local repo files and into Infisical without printing values
or leaving plaintext behind.

## Standard Path

Map repos to Infisical paths:

```text
/Users/joshka/repos/personal/foo -> /repos/personal/foo
/Users/joshka/repos/foxway/foo   -> /repos/foxway/foo
/Users/joshka/repos/mobiles/foo  -> /repos/mobiles/foo
```

Use an explicit path if a secret belongs somewhere narrower or broader.

## Import A Repo `.env`

Run:

```sh
/Users/joshka/.vault/scripts/infisical-import-dotenv.sh \
  /path/to/repo/.env \
  /repos/personal/example \
  dev \
  --move-source-to-vault
```

This helper should:

- Import through Infisical with output suppressed.
- Verify key presence without printing values.
- Store an encrypted copy under `~/.vault/staging`.
- Remove the repo plaintext file when `--move-source-to-vault` is used.
- Write a redacted report under `~/.vault/imports`.

## Verify Without Printing Values

Presence check pattern:

```sh
cd /Users/joshka/.vault/umbrella/home-root
infisical run --env dev --path /repos/personal/example -- sh -lc '
for key in DATABASE_URL API_TOKEN EXPO_PAT; do
  eval "value=\${$key:-}"
  if [ -n "$value" ]; then
    printf "%s=present\n" "$key"
  else
    printf "%s=missing\n" "$key"
  fi
done
'
```

Never print the value.

## Update The Repo

In the migrated repo:

1. Ensure `.env` and `.env.*` are ignored, except safe examples.
2. Add a short `AGENTS.md` section with the Infisical runtime path.
3. Prefer:

```sh
infisical run --env dev --path /repos/personal/example -- <command>
```

4. Generate local files only when a tool cannot consume environment variables.
5. Write generated files to ignored paths.

## Final Report

Report:

- Target repo path
- Infisical path
- Key names imported
- Key count
- Presence-check status
- Whether plaintext was removed
- Encrypted staging/report paths
- Suspected typo key names, if any

Do not report values.
