# Fizzy

Guidance for AI coding agents working with this repository.

Fizzy is a kanban-style project management and issue tracker: cards move across columns on boards, with comments, mentions, and assignments.

## Deploy

Default branch: `main`

Self-hosted deploys run Kamal against `config/deploy.yml` — see `docs/kamal-deployment.md`.

## SaaS mode

For local agent work, `tmp/saas.txt` is the checkout-level SaaS switch used by `bin/setup`. When present, read `saas/AGENTS.md` before continuing. Otherwise, do not apply its instructions.

## Repository Workflow

This working copy is for `joshyorko/fizzy`, which is a downstream fork of `basecamp/fizzy`.

- Treat `joshyorko/fizzy` as the default GitHub repository for pushes and pull requests.
- Treat `self-hosted` as a downstream branch in `joshyorko/fizzy`, not as an upstream contribution branch.
- Do not open pull requests against `basecamp/fizzy` unless the user explicitly asks for an upstream PR.
- Before opening any PR, verify both the head repo and the base repo so the PR is created in the intended downstream repository.
- If the user asks for a PR "in mine" or "in Josh's repo", that means `joshyorko/fizzy`, not `basecamp/fizzy`.

## Architecture Overview

### Multi-Tenancy (URL-Based)

Fizzy uses **URL path-based multi-tenancy**:
- Accounts have a unique decimal `external_account_id` used in URL prefixes
- URLs are prefixed: `/{account_id}/boards/...`
- Middleware (`AccountSlug::Extractor`) extracts the account ID from the URL and sets `Current.account`
- The slug is moved from `PATH_INFO` to `SCRIPT_NAME`, making Rails think it's "mounted" at that path
- Tenant-scoped domain records are account-isolated; global identity, session, and authentication records are exceptions
- Background jobs automatically serialize and restore account context

**Key insight**: This architecture allows multi-tenancy without subdomains or separate databases, making local development and testing simpler.

### Authentication & Authorization

Passwordless magic link authentication. A global `Identity` (email-based) can have `Users` in multiple Accounts, so an email is not a single account membership. Users have roles: owner, admin, member, system. Board-level access control via `Access` records.

### Entropy System

Cards automatically "postpone" (move to "not now") after inactivity:
- Account-level default entropy period
- Board-level entropy override
- Prevents endless todo lists from accumulating
- Configurable via Account/Board settings

### UUID Primary Keys

All tables use UUIDs (UUIDv7 format, base36-encoded as 25-char strings):
- Custom fixture UUID generation maintains deterministic ordering for tests
- Fixtures are always "older" than runtime records
- `.first`/`.last` work correctly in tests

### Background Jobs (Solid Queue)

Database-backed job queue (no Redis):
- Custom `FizzyActiveJobExtensions` prepended to ActiveJob
- Jobs automatically capture/restore `Current.account`
- Mission Control::Jobs for monitoring

Recurring tasks are declared in `config/recurring.yml`.

### Sharded Full-Text Search

Full-text search runs in the database, not Elasticsearch. On MySQL it is sharded 16 ways by CRC32 of the account ID (`Search::Record::Trilogy`); on SQLite it is a single FTS5 index (`Search::Record::SQLite`). Don't assume the sharded shape when working under SQLite. Models in `app/models/search/`.

### Imports and exports

Allow people to move between OSS and SAAS Fizzy instances:
- Exports/Imports can be written to/read from local or S3 storage depending on the config of the instance (both must be supported)
- Must be able to handle very large ZIP files (500+GB)
- Models in `app/models/account/data_transfer/`, `app/models/zip_file`

## Tools

### Chrome MCP (Local Dev)

URL: `http://app.fizzy.localhost:3006`
Login: david@example.com (passwordless magic link auth - check rails console for link)

Use Chrome MCP tools to interact with the running dev app for UI testing and debugging.

### Fizzy MCP / API

- MCP endpoint: `/mcp`
- Read tools use `read`; mutating tools require `read write` or a Read + Write personal access token.
- Current mutating MCP tools: `column_update`, `card_create`, `card_update`, `move_card`, `comment_create`.
- Card descriptions and comment bodies are Action Text rich text. Send sanitized HTML in `description`/`body` for lists, links, bold text, and paragraphs; do not rely on Markdown rendering.
- For agent workflow cards, use board-visible golden tickets: tag the card `#agent-instructions`, put the agent prompt in the description, use card steps for ordered work, and add completion tags like `#move-to-done`, `#close-on-complete`, or `#move-to-<column>`.
- MCP `card_create`/`card_update` support `tag_titles`, `steps`, and `golden` for golden-ticket setup. `tag_titles` is idempotent and strips leading `#`; `steps` skips duplicate matching step content.

## Coding style

Before editing or reviewing code, read STYLE.md.
