---
name: Keep DESCRIPTION in sync with script dependencies
description: Always update DESCRIPTION Imports when adding/removing packages from analysis scripts
type: feedback
---

When adding or removing `library()` calls in analysis scripts (e.g. 1-scrape.R, 2-collapse.R), also update the `Imports` field in `DESCRIPTION` to match.

**Why:** The GitHub Actions workflow uses `r-lib/actions/setup-r-dependencies@v2` which installs packages based on DESCRIPTION. If it's out of sync, the action will fail.
**How to apply:** After any change to `library()` calls in scripts, check DESCRIPTION Imports and update accordingly.
