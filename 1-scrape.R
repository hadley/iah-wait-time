library(gha)
library(httr2)
library(nanoparquet)

gha_notice("Scraping at {Sys.time()}")

resp <- request("https://api.houstonairports.mobi/wait-times/checkpoint/iah") |>
  req_headers(
    `Api-Key` = "9ACB3B733BE94B11A03B6E84CA87E895",
    `Api-Version` = "120"
  ) |>
  req_perform()

data <- resp_body_json(resp)
checkpoints <- data$data$wait_times

df <- data.frame(
  time = .POSIXct(
    vapply(checkpoints, `[[`, 0, "lastUpdatedTimestamp"),
    tz = "America/Chicago"
  ),
  id = vapply(checkpoints, `[[`, "", "id"),
  name = vapply(checkpoints, `[[`, "", "name"),
  is_open = vapply(checkpoints, `[[`, TRUE, "isOpen"),
  wait_seconds = vapply(checkpoints, `[[`, 0, "waitSeconds")
)

today <- as.Date(format(Sys.time(), tz = "America/Chicago"))
day <- format(today, "%Y-%m-%d")
path <- file.path("data", paste0(day, ".parquet"))

if (file.exists(path)) {
  append_parquet(df, path)
} else {
  write_parquet(df, path)
}
gha_notice("Wrote {nrow(df)} rows to {path}")
