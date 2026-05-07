# Local Secrets

Secrets for this repo live in Infisical.

Infisical path:

```text
/repos/personal/example
```

Run commands through Infisical:

```sh
infisical run --env dev --path /repos/personal/example -- <command>
```

Rules:

- Do not commit `.env`.
- Do not print secret values.
- Discover required key names from code/config.
- Check key presence with `present` / `missing` only.
- If a new `.env` appears, import it with
  `/Users/joshka/.vault/scripts/infisical-import-dotenv.sh`.
