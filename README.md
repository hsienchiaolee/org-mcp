# org-mcp

An [MCP](https://modelcontextprotocol.io) (Model Context Protocol) server that exposes Org-mode's data model over stdio JSON-RPC 2.0.

## Requirements

- Emacs 29.1+
- Org-mode 9.6+

## Installation

With `use-package` (Emacs 29+):

```emacs-lisp
(use-package org-mcp
  :vc (:url "https://github.com/hsienchiaolee/org-mcp"))
```

With `use-package` + `straight.el`:

```emacs-lisp
(use-package org-mcp
  :straight (org-mcp :type git :host github :repo "hsienchiaolee/org-mcp"))
```

## Usage

### Batch mode

Run as a standalone process:

```sh
emacs --batch -Q -L /path/to/org-mcp -l org-mcp -f org-mcp-start
```

### Daemon mode

Start from a running Emacs daemon:

```emacs-lisp
(org-mcp-start)
```

### MCP client configuration

Add to your MCP client config (e.g. `claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "org-mcp": {
      "command": "emacs",
      "args": ["--batch", "-Q", "-L", "/path/to/org-mcp", "-l", "org-mcp", "-f", "org-mcp-start"]
    }
  }
}
```

## Tools

| Tool | Description |
|------|-------------|
| `org_get_entry` | Return full data for an entry by org-id |
| `org_query` | Query agenda files with s-expression filter |
| `org_get_children` | Return immediate children of an entry |
| `org_get_properties` | Return the property drawer (with optional inherit) |
| `org_set_state` | Set or clear the TODO keyword |
| `org_set_property` | Set or delete a property |
| `org_append_body` | Append text to body, optionally in a drawer |
| `org_capture` | Create a new entry from inline params or template |

## Notifications

When enabled, the server emits MCP notifications for Org-mode events:

- `org/entryStateChanged` — TODO state transitions
- `org/propertyChanged` — property modifications
- `org/entryCreated` — new entries created via `org_capture`

## Testing

```sh
make test              # run all tests
make test-rpc          # run only JSON-RPC tests
make test-query        # run only query tests
make test-mutate       # run only mutation tests
make test-notify       # run only notification tests
make test-server       # run only server tests
make test-integration  # run only integration tests
```

