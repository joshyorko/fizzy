# MCP

Fizzy exposes an MCP endpoint at `/mcp`. It uses OAuth bearer tokens and JSON-RPC 2.0 over HTTP POST. It supports stateless MCP `2026-07-28` and legacy `2025-11-25` and `2025-06-18` clients. No request requires `Mcp-Session-Id`, sticky sessions, or a previous request to the same replica.

## Protocol versions

Modern requests declare their version and client capabilities in `params._meta`. Each POST also carries `MCP-Protocol-Version` and `Mcp-Method`. `Mcp-Name` is required only for named operations: the tool name for `tools/call`, or the resource URI for `resources/read`.

```http
POST /mcp
Authorization: Bearer <token>
Content-Type: application/json
Accept: application/json, text/event-stream
MCP-Protocol-Version: 2026-07-28
Mcp-Method: server/discover

{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}
```

`server/discover` returns `supportedVersions`, capabilities, and server identity in `_meta`. Modern results include `resultType: "complete"`. Header values must match their body fields; encoded `Mcp-Name` values use the specification's `=?base64?...?=` format.

| Condition | HTTP status | JSON-RPC code |
| --- | --- | --- |
| Missing or mismatched modern headers | 400 | -32020 |
| Unsupported protocol version | 400 | -32022, with requested and supported versions |
| Invalid modern request metadata | 400 | -32602 |
| Unknown modern method | 404 | -32601 |
| Invalid browser Origin | 403 | No JSON-RPC body |

Legacy clients retain `initialize`, `notifications/initialized`, and `ping`. Headerless requests without modern metadata use legacy behavior. Modern clients do not initialize and cannot send batches. GET and DELETE on `/mcp` return 405.

## Caching and optional features

Modern discovery and tool catalogs have a 60-second private cache hint. Resource catalogs and resource reads use `ttlMs: 0` and `cacheScope: "private"` so clients can observe card edits and access changes immediately. Cached results must never be shared across access tokens. MCP POST results are marked `Cache-Control: no-store`; JSON-RPC cache hints apply only to protocol-aware clients. Tool names and resource URIs have deterministic ordering.

Fizzy implements the protocol directly in Rails, without an MCP SDK dependency. The latest official [Ruby SDK release, v1.7.0](https://github.com/modelcontextprotocol/ruby-sdk/releases/tag/v1.7.0), adds client OAuth completion and bounds for retained initialization and subscription data; Fizzy has no equivalent retained transport state to migrate. It exposes synchronous tools and resources. It does not advertise Tasks, subscriptions, sampling, roots, or elicitation, so no MRTR or background-task state is introduced by this upgrade.

OAuth retains PKCE, resource audience checks, revocation, and existing ChatGPT, native-app, and loopback callbacks. Authorization responses include the issuer `iss` parameter. Dynamic client registration remains available for existing clients. The specification deprecates it in favor of Client ID Metadata Documents; Fizzy does not yet fetch those documents or advertise support for them.

Protocol reference checked on 2026-10-12 against [specification commit 1f520964](https://github.com/modelcontextprotocol/modelcontextprotocol/tree/1f520964b295d58494d944f2aea8a5ab51c79f77): [transport](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http), [discovery](https://modelcontextprotocol.io/specification/2026-07-28/server/discover), [caching](https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/caching), and [changes and deprecations](https://modelcontextprotocol.io/specification/2026-07-28/changelog).

## Scopes

Read tools require the `read` scope. Mutating tools require `read write`.

Mutating MCP tools currently include:

- `column_update`
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

## Column Colors

MCP `column_update` renames an active workflow column or changes its color:

```json
{
  "account_id": "1234567",
  "board_id": "03f5v9zkft4hj9qq0lsn9ohcm",
  "column_id": "03f5v9zkft4hj9qq0lsn9ohcn",
  "color": "Aqua"
}
```

Accepted color names are `Blue`, `Gray`, `Tan`, `Yellow`, `Lime`, `Aqua`, `Violet`, `Purple`, and `Pink`. The matching CSS variable values are accepted too.

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
