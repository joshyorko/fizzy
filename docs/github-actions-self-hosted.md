# GitHub Actions Self-Hosted Deploy

This branch deploys Fizzy from a trusted self-hosted GitHub Actions runner.

The runner host only needs:

- Docker
- SSH access to the deploy target
- the GitHub Actions runner service
- Ruby through `rbenv`

The image build runs on GitHub's hosted `ubuntu-latest` runner, where `bundle exec kamal build push` builds the amd64 image and pushes it to GHCR. The trusted self-hosted runner is deploy-only: it uses Kamal with `--skip-push` to deploy the already-published image to the amd64 target host.

The hosted build sets `KAMAL_SKIP_SSH_CHECK=1` because it only needs Docker and GHCR access. SSH preflight still runs during deploy and diagnostics on the trusted runner.

## Branch model

- Keep self-hosted deployment work on the `self-hosted` branch.
- Set the fork default branch to `self-hosted` once the repo-side workflow is in place.
- The deploy-related workflows are `workflow_dispatch` only. Nothing auto-builds or auto-deploys on push.

## CI profile

`.github/workflows/ci-saas.yml` is the profile-aware CI wrapper despite the filename.

- `FIZZY_EDITION=saas` runs SaaS and OSS tests.
- `FIZZY_EDITION=oss` or `FIZZY_EDITION=self-hosted` runs the OSS profile.
- If `FIZZY_EDITION` is unset, `basecamp/fizzy` defaults to SaaS and downstream forks default to OSS.
- Pull requests targeting `self-hosted` default to OSS.

The sync workflow first tries to create a real merge candidate from `self-hosted` plus `basecamp/main`. If that merge conflicts, it leaves a conflict-alert PR whose checks may reflect upstream/SaaS state instead of the self-hosted profile. Resolve those conflicts from a branch based on `self-hosted`, then rerun the OSS/self-hosted profile.

## Repo secrets

Sync app secrets from `.env.kamal.local` into the fork with:

```bash
script/sync-github-secrets-from-kamal-env.sh joshyorko/fizzy
```

This pushes:

- `SECRET_KEY_BASE`
- `VAPID_PUBLIC_KEY`
- `VAPID_PRIVATE_KEY`
- `SMTP_USERNAME`
- `SMTP_PASSWORD`
- `S3_ACCESS_KEY_ID`
- `S3_SECRET_ACCESS_KEY`
- `CLOUDFLARED_TOKEN`
- `KAMAL_REGISTRY_PASSWORD` from `KAMAL_REGISTRY_PASSWORD` or `gh auth token`

If `config/master.key` exists locally, the script also syncs `RAILS_MASTER_KEY`.

## Runner install

Install and register the trusted runner as a system service with the repo script that matches the current deployment host.

The workflow expects the trusted runner to be able to SSH to the deploy target without prompting.

## Deploy workflow

`.github/workflows/deploy-self-hosted.yml` runs only by manual dispatch.

`.github/workflows/publish-image.yml` runs only by manual dispatch. It builds a single amd64 image with Kamal on a GitHub-hosted runner, pushes `ghcr.io/joshyorko/fizzy:sha-<short_sha>`, then hands that tag to `deploy-self-hosted.yml`.

## Diagnostics workflow

`.github/workflows/diagnostics-self-hosted.yml` runs only by manual dispatch and does not deploy anything.

Recommended first run:

1. Run `diagnostics-self-hosted.yml` with `command=summary`.
2. Run `diagnostics-self-hosted.yml` with `command=app_logs` if you want to prove Kamal can reach the current Fizzy app and stream logs.

Recommended order:

1. Run `diagnostics-self-hosted.yml` with `command=summary`.
2. Run `publish-image.yml`.
3. After the image exists in GHCR, run `deploy-self-hosted.yml`.

Diagnostics dispatch supports:

- `summary`: `kamal version`, `kamal details`, `kamal app version`, `kamal app containers`, and `kamal proxy details`
- `app_logs`: `kamal app logs --primary --lines N`
- `proxy_logs`: `kamal proxy logs --primary --lines N`
- `app_details`: `kamal app details`
- `proxy_details`: `kamal proxy details`
- `audit`: `kamal audit`

The diagnostics workflow:

- writes `.env.kamal.local` and `config/master.key` from GitHub secrets
- verifies the trusted runner can SSH to the deploy target
- runs the selected Kamal read-only diagnostic command set on the self-hosted runner
- fails the workflow if any selected Kamal check fails

Manual deploy dispatch supports:

- `deploy`: normal `kamal deploy`
- `setup`: first-time `kamal setup`

The workflow:

- writes `.env.kamal.local` and `config/master.key` from GitHub secrets
- waits for `ghcr.io/joshyorko/fizzy:sha-<short_sha>` to exist
- runs Kamal on the self-hosted runner
- runs `kamal setup --skip-push --version …` or `kamal deploy --skip-push --version …`

This matches the current Kamal docs:

- `registry/server` selects a non-local registry
- Kamal supports building and pushing a versioned image separately from deploy
- `kamal deploy --skip-push --version VERSION` deploys an already-published image
