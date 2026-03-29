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

pluck <- function(xs, name, default) {
  vapply(xs, \(x) x[[name]] %||% default, default)
}

df <- data.frame(
  time = .POSIXct(
    pluck(checkpoints, "lastUpdatedTimestamp", 0),
    tz = "America/Chicago"
  ),
  id = pluck(checkpoints, "id", ""),
  name = pluck(checkpoints, "name", ""),
  is_open = pluck(checkpoints, "isOpen", TRUE),
  wait_seconds = pluck(checkpoints, "waitSeconds", NA_real_)
)

today <- as.Date(format(Sys.time(), tz = "America/Chicago"))
day <- format(today, "%Y-%m-%d")
path <- file.path("data", paste0(day, ".parquet"))

if (file.exists(path)) {
  old <- tryCatch(
    read_parquet(path),
    error = function(e) {
      gha_warning("Corrupted parquet file: {path}")
      NULL
    }
  )
  if (!is.null(old)) {
    df <- rbind(old, df)
  }
}
write_parquet(df, path)
gha_notice("Wrote {nrow(df)} rows to {path}")
