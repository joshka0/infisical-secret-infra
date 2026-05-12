# Agent Guide

Use this guide whenever an agent touches local secret infrastructure.

## Do Not Print Secrets

Forbidden as discovery:

```sh
env
printenv
infisical secrets --output dotenv
infisical export
cat .env
cat ~/.env
cat ~/.aws/credentials
cat ~/.kube/config
cat ~/.ssh/*
```

Use code/config inspection to discover key names:

```sh
rg -n "process\\.env\\.|Deno\\.env|getenv\\(|System\\.getenv|ENV\\[|import\\.meta\\.env|VITE_|NEXT_PUBLIC_|EXPO_PUBLIC_" .
rg -n "OPENAI_API_KEY|ANTHROPIC_API_KEY|GITHUB_TOKEN|SUPABASE|TURSO|DATABASE_URL|AWS_|KUBECONFIG" .
find . -maxdepth 3 \( -name '.env.example' -o -name '.env.template' -o -name '.env.sample' -o -name '.envrc' \) -print
```

## Safe Output

Allowed:

- Key names
- `present` / `missing`
- Counts
- Hashes
- Paths
- Redacted reports
- Command success/failure

Not allowed:

- Values
- Prefixes/suffixes of values
- Token previews
- Full dotenv output
- Decrypted file content

## When A New `.env` Appears

1. Do not read it.
2. Import it with the helper.
3. Move plaintext into encrypted vault staging.
4. Verify key presence only.
5. Update repo docs to use `infisical run`.
6. Confirm `.env` is ignored.

## When A Workflow Needs Secrets

1. Identify the command.
2. Inspect source for required key names.
3. Map the repo to an Infisical path.
4. Run through Infisical:

```sh
infisical run --env dev --path /repos/personal/example -- <command>
```

5. If the workflow needs agent HTTP credentials, use Agent Vault instead of raw
   key injection.

## When Handling Backups

- Backups are encrypted before retention or upload.
- Upload target is operator-configured, for example `dev:backups/infisical`.
- Only `*.tar.enc` and redacted `*.report.txt` leave the machine.
- The backup passphrase must be copied into the password vault and must not be
  printed.

## When Handling The Infisical Bootstrap Env

- Do not commit or print the service `.env`.
- Use `~/.vault/scripts/infisical-encrypt-bootstrap-env.sh` after intentional
  service env changes.
- Use `~/.vault/scripts/infisical-compose-secure-env.sh` for start/stop/logs.
- Report only key counts, paths, hashes, and presence statuses.
- Do not store the bootstrap passphrase only inside Infisical.
