# IAH security wait times

This repository uses GitHub Actions to scrape security checkpoint wait times from George Bush Intercontinental Airport (IAH) every 10 minutes from 4am to 10pm Central Time.

## Data

Wait times come from the Houston Airports API. Each observation records the checkpoint id, name, whether it's open, and the wait time in seconds, along with the timestamp from the API.

* `data/` contains daily parquet files (e.g. `2026-03-23.parquet`).
* `collapsed/` contains monthly parquet files that combine and deduplicate the daily files.

All dates and times use the `America/Chicago` timezone.
