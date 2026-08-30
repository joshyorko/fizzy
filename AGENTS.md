# Fizzy

Fizzy is a kanban-style project management and issue tracker: cards move
across columns on boards, with comments, mentions, and assignments.

These instructions are defaults with reasons, not law — when the code in
front of you disagrees, take the better path and flag the conflict; invariants
(data loss, security, CI gates) are surfaced, not overridden. Attack your own
diff before calling it done.

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

## Multi-tenancy is URL-based

Accounts get a decimal `external_account_id` URL prefix (`/{account_id}/boards/...`).
`AccountSlug::Extractor` middleware sets `Current.account` and moves the slug
from `PATH_INFO` to `SCRIPT_NAME`, so Rails behaves as if mounted at that
path — route helpers and request specs that assume a bare root will mislead
you. Domain records are account-scoped; identity, session, and authentication
records are the global exceptions. Background jobs serialize and restore
`Current.account` themselves.

A global `Identity` (email-based) can hold `Users` in multiple accounts, so
an email address is not a single account membership. Board access is per-user
`Access` records.

## UUID primary keys

All tables use UUIDv7 keys, base36-encoded to 25 characters. Fixture UUIDs
are generated to sort older than any runtime record, so `.first`/`.last`
stay deterministic in tests — don't "fix" ordering by comparing insertion
order to id order.

## Search is sharded on MySQL, single-index on SQLite

Full-text search runs in the database, not Elasticsearch. On MySQL it is
sharded 16 ways by CRC32 of the account ID (`Search::Record::Trilogy`); on
SQLite it is a single FTS5 index (`Search::Record::SQLite`). Don't assume the
sharded shape when working under SQLite. Models in `app/models/search/`.

## Imports and exports

Data transfer between instances (`app/models/account/data_transfer/`,
`app/models/zip_file`) must work against both local and S3 storage, and
archives can exceed hundreds of gigabytes — stream, never buffer a whole
file.

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
