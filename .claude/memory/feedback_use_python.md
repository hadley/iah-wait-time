---
name: Use Python not R for network requests
description: R REPL is DNS-sandboxed so can't make network requests; use Python REPL or bash curl instead
type: feedback
---

R REPL cannot resolve DNS / make network requests from this machine. Use Python REPL or bash curl for testing API calls.

**Why:** R is sandboxed in a way that blocks outbound network access.
**How to apply:** When needing to test API calls or fetch web content interactively, use mcp__python__repl or bash curl, not mcp__r__repl.
