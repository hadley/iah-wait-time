library(nanoparquet)
library(jsonlite)

# In CI, the data branch is checked out at data/; locally use collapsed/
paths <- Sys.glob("data/collapsed/*.parquet")
if (length(paths) == 0) paths <- Sys.glob("collapsed/*.parquet")
stopifnot("No collapsed parquet files found" = length(paths) > 0)

df <- do.call(rbind, lapply(paths, read_parquet))
# Parquet round-trips POSIXct as UTC; all downstream hour/date math is in CT
df$time <- .POSIXct(as.numeric(df$time), tz = "America/Chicago")
df <- df[!duplicated(df[c("id", "time")]), ]
df <- df[order(df$time), ]

lt <- as.POSIXlt(df$time)
df$wait_min <- df$wait_seconds / 60
df$hour <- lt$hour
df$date <- as.Date(df$time, tz = "America/Chicago")
df$min_of_day <- lt$hour * 60 + lt$min

# Operational day runs 4am-4am; x position within that day
df$op_day <- df$date - (df$min_of_day < 240)
df$x <- (df$min_of_day - 240) %% 1440

open <- df[df$is_open & !is.na(df$wait_min), ]

agg <- function(x, f) if (length(x) == 0) NA_real_ else round(f(x), 1)

parse_name <- function(name) {
  lane <- "Standard"
  if (grepl("PreCheck", name)) {
    lane <- "PreCheck"
  } else if (grepl("Premier", name)) {
    lane <- "Premier"
  } else if (grepl("Customs|Immigration", name, ignore.case = TRUE)) {
    lane <- "Customs"
  }
  terminal <- sub(" (Standard|PreCheck|Premier)$", "", name)
  terminal <- sub("^IAH ", "", terminal)
  if (lane == "Customs") terminal <- "Int'l arrivals"
  list(terminal = terminal, lane = lane)
}

# Keep only checkpoints reporting regularly: >= 20 observations in last 14 days
recent_report_cutoff <- max(df$time) - 14 * 86400
recent_counts <- table(open$id[open$time >= recent_report_cutoff])
keep_ids <- names(recent_counts)[recent_counts >= 20]

# Typical-day profile uses the last 90 days so it reflects current conditions
cutoff <- max(df$time) - 90 * 86400
recent <- open[open$time >= cutoff, ]

latest_name <- tapply(df$name, df$id, \(x) x[length(x)])
ids <- intersect(names(latest_name), keep_ids)

mk_checkpoint <- function(id) {
  d <- df[df$id == id, ]
  o <- open[open$id == id, ]
  r <- recent[recent$id == id, ]
  last <- d[nrow(d), ]
  nm <- parse_name(latest_name[[id]])

  hourly <- vapply(0:23, \(h) agg(r$wait_min[r$hour == h], median), numeric(1))
  p95 <- vapply(0:23, \(h) agg(r$wait_min[r$hour == h], \(x) quantile(x, 0.95, names = FALSE)), numeric(1))
  # Reorder so the day starts at 4am
  ord <- c(4:23, 0:3) + 1
  hourly <- hourly[ord]
  p95 <- p95[ord]

  today_day <- max(o$op_day)
  t <- o[o$op_day == today_day, ]
  today <- lapply(seq_len(nrow(t)), \(i) c(t$x[i], round(t$wait_min[i], 1)))

  list(
    id = id,
    group = sub("^(Terminal [A-Z]).*$", "\\1", nm$terminal),
    terminal = nm$terminal,
    lane = nm$lane,
    open = last$is_open,
    waitMin = if (is.na(last$wait_min)) NA else round(last$wait_min, 0),
    updated = format(last$time, "%Y-%m-%dT%H:%M:%S%z"),
    today = today,
    hourly = unname(hourly),
    p95 = unname(p95)
  )
}

checkpoints <- lapply(ids, mk_checkpoint)
lane_order <- c(Standard = 1, PreCheck = 2, Premier = 3, Customs = 4)
groups <- vapply(checkpoints, \(x) x$group, character(1))
terminals <- vapply(checkpoints, \(x) x$terminal, character(1))
ord <- order(
  groups == "Int'l arrivals",
  groups,
  terminals,
  lane_order[vapply(checkpoints, \(x) x$lane, character(1))]
)
checkpoints <- checkpoints[ord]

payload <- list(
  generated = format(Sys.time(), tz = "America/Chicago", "%Y-%m-%dT%H:%M:%S%z"),
  checkpoints = checkpoints
)

json <- toJSON(payload, auto_unbox = TRUE, na = "null", digits = 4)
template <- paste(readLines("dashboard/template.html", warn = FALSE), collapse = "\n")
html <- sub(
  "<!--DATA-->",
  paste0("<script>window.DATA = ", json, ";</script>"),
  template,
  fixed = TRUE
)

dir.create("site", showWarnings = FALSE)
writeLines(html, "site/index.html")
message("Wrote site/index.html (", nchar(html), " bytes)")
