# Repo Secret Inventory

Repo:

Infisical path:

Environment:

Migration date:

## Keys

| Key name | Source evidence | Destination | Status | Notes |
| --- | --- | --- | --- | --- |
| EXAMPLE_KEY | `.env` / source reference | `/repos/...` | present | value not recorded |

## Runtime Commands

```sh
infisical run --env dev --path /repos/personal/example -- <command>
```

## Notes

- Do not record secret values in this file.
- Use `present` / `missing` statuses only.
