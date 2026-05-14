# MCP

Fizzy exposes an MCP endpoint at `/mcp`. It uses OAuth bearer tokens and JSON-RPC 2.0 over HTTP POST.

## Scopes

Read tools require the `read` scope. Mutating tools require `read write`.

Mutating MCP tools currently include:

- `board_create`
- `card_create`
- `card_update`
- `move_card`
- `comment_create`

If a client can list cards but cannot create or update them, re-authorize it with `read write` or use a personal access token with `Read + Write` permission.

## Rich Text HTML

Card descriptions and comment bodies are Action Text rich text fields. Send HTML in the `description` or `body` string when formatting matters:

```json
{
  "description": "<p>John birthday outing</p><ul><li>Load QR codes before leaving</li><li>Confirm parking entrance</li></ul><p><a href=\"https://example.com\">Venue info</a></p>"
}
```

Plain text is accepted, but Markdown is not the rich text format. HTML is sanitized before storage.

## Board Creation

MCP `board_create` creates a board in the authenticated account and can optionally create initial columns:

```json
{
  "account_id": "1234567",
  "name": "Agent Heartbeat",
  "description": "<p>Tracks agent heartbeat work.</p>",
  "columns": ["Inbox", "In progress", "Done"]
}
```

`title` is accepted as an alias for `name`, and `initial_columns` is accepted as an alias for `columns`. The response includes the board, its URL, and the created columns. The returned board id can be used immediately with `card_create`.

## Golden Tickets

For agent workflow cards, use board-visible card state instead of hidden config.

A golden ticket is a normal card with:

- `#agent-instructions` tag
- card description as the agent prompt
- checklist steps for ordered work
- completion tag such as `#move-to-done`, `#close-on-complete`, or `#move-to-<column>`

MCP `card_create` and `card_update` accept helper fields for this:

```json
{
  "title": "Agent workflow",
  "description": "<p>Follow these board instructions.</p>",
  "tag_titles": ["#agent-instructions", "#move-to-done"],
  "steps": ["Read card context", "Update card with result"],
  "golden": true
}
```

`tag_titles` applies tags idempotently and strips leading `#`. `steps` creates missing checklist steps without duplicating existing matching step content. `golden` controls Fizzy's native golden marker.
