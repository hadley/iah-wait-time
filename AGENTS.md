# iah-wait-time

Scrapes IAH (Houston) security checkpoint wait times every 10 minutes via GitHub Actions and publishes a static dashboard. All times are `America/Chicago`.

## Pipeline

- `1-scrape.R`: calls the Houston Airports API (httr2) and appends one row per checkpoint (time, id, name, is_open, wait_seconds) to a daily parquet file `data/YYYY-MM-DD.parquet`.
- `2-collapse.R`: combines and dedupes (by id + time) the current month's daily files into `data/collapsed/YYYY-MM.parquet`.
- `3-build.R`: reads the last 4 monthly files (from `data/collapsed/` in CI, `collapsed/` locally), computes summaries for a 4am-10pm "operational day" window, and writes `site/` (index.html from the template + data.json).
- `.github/workflows/scrape.yaml`: runs all three scripts on a `*/10 * * * *` cron. In CI the data lives on a separate data branch checked out at `data/`.

## Dashboard

- Dashboard source: `dashboard/template.html` (Preact + htm, vendored in `dashboard/vendor`). `3-build.R` builds `site/` (index.html + data.json).
- After any change to the dashboard, always rebuild the rendered preview and show it in the Positron Viewer so the user can look at it: copy `site/` to a scratch dir, copy `dashboard/template.html` over its `index.html`, serve it with `python3 -m http.server`, and open the localhost URL with `workbench.action.positronPreview.openUrl`.

## Other

- `DESCRIPTION` lists R dependencies (gha, httr2, nanoparquet, jsonlite); `R/` is currently empty.
- `plan.md` holds working notes/plans.
