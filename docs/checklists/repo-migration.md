# Repo Secret Migration Checklist

## Intake

- [ ] Target repo path identified.
- [ ] Infisical destination path selected.
- [ ] Existing `.infisical.json` checked, if present.
- [ ] Required key names discovered from code/config only.
- [ ] No secret values printed.

## Import

- [ ] Real `.env` imported with `infisical-import-dotenv.sh`.
- [ ] Import output suppressed.
- [ ] Key presence verified with `present`/`missing` only.
- [ ] Plaintext `.env` removed from repo.
- [ ] Encrypted staging copy created under `~/.vault/staging`.
- [ ] Redacted report written under `~/.vault/imports`.

## Repo Hygiene

- [ ] `.env` ignored.
- [ ] Safe examples/templates retained only when value-free.
- [ ] Repo `AGENTS.md` documents the Infisical path.
- [ ] Runtime command uses `infisical run`.
- [ ] Generated local secret files are ignored.

## Final Report

- [ ] Destination path reported.
- [ ] Key names and count reported.
- [ ] Presence statuses reported.
- [ ] Plaintext removal status reported.
- [ ] Suspected typo keys called out without changing imported data.
