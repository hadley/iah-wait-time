library(nanoparquet)
library(jsonlite)

# Dashboard window: 4am to 10pm Central
DAY_START_HOUR <- 4
DAY_END_HOUR <- 22
n_hours <- DAY_END_HOUR - DAY_START_HOUR

# In CI, the data branch is checked out at data/; locally use collapsed/
paths <- Sys.glob("data/collapsed/*.parquet")
if (length(paths) == 0) paths <- Sys.glob("collapsed/*.parquet")
stopifnot("No collapsed parquet files found" = length(paths) > 0)
# Monthly files; 4 months covers the 12-week profiles below
paths <- utils::tail(sort(paths), 4)

df <- do.call(rbind, lapply(paths, read_parquet))
# Parquet round-trips POSIXct as UTC; all downstream hour/date math is in CT
df$time <- .POSIXct(as.numeric(df$time), tz = "America/Chicago")
df <- df[!duplicated(df[c("id", "time")]), ]
df <- df[order(df$time), ]

lt <- as.POSIXlt(df$time)
df$wait_min <- df$wait_seconds / 60
df$hour <- lt$hour
df$date <- as.Date(df$time, tz = "America/Chicago")
df$wday <- lt$wday
df$min_of_day <- lt$hour * 60 + lt$min

# Operational day starts at 4am (so midnight-4am belongs to the previous day)
df$op_day <- df$date - (df$min_of_day < DAY_START_HOUR * 60)
# x position: minutes since 4am; only points within the window are plotted
df$x <- df$min_of_day - DAY_START_HOUR * 60
df$in_window <- df$hour >= DAY_START_HOUR & df$hour < DAY_END_HOUR

open <- df[df$is_open & !is.na(df$wait_min), ]

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

# A single "today" for every checkpoint, so a quiet checkpoint never shows an
# older day as today
today_day <- max(df$op_day)
today_wday <- as.POSIXlt(today_day)$wday

# Typical-day profile: same weekday as today over the last 12 weeks.
# Hours with too few observations (usually when a checkpoint is normally
# closed) are left blank rather than estimated from a handful of points.
min_obs <- 5
profile_data <- function(o) {
  o[o$wday == today_wday & o$in_window & o$op_day < today_day &
    o$op_day >= today_day - 12 * 7, ]
}

agg <- function(x, f) if (length(x) < min_obs) NA_real_ else round(f(x), 1)

latest_name <- tapply(df$name, df$id, \(x) x[length(x)])
ids <- intersect(names(latest_name), keep_ids)

mk_checkpoint <- function(id) {
  d <- df[df$id == id, ]
  o <- open[open$id == id, ]
  r <- profile_data(o)
  last <- d[nrow(d), ]
  nm <- parse_name(latest_name[[id]])

  hours <- DAY_START_HOUR:(DAY_END_HOUR - 1)
  hourly <- vapply(hours, \(h) agg(r$wait_min[r$hour == h], median), numeric(1))
  p95 <- vapply(hours, \(h) agg(r$wait_min[r$hour == h], \(x) quantile(x, 0.95, names = FALSE)), numeric(1))

  t <- o[o$op_day == today_day & o$in_window, ]
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
  weekday = format(today_day, "%A"),
  dayStartHour = DAY_START_HOUR,
  dayEndHour = DAY_END_HOUR,
  checkpoints = checkpoints
)

# Static page + vendored JS; data lives in data.json so the page can refetch it
dir.create("site/vendor", recursive = TRUE, showWarnings = FALSE)
file.copy("dashboard/template.html", "site/index.html", overwrite = TRUE)
file.copy(Sys.glob("dashboard/vendor/*.js"), "site/vendor", overwrite = TRUE)
write_json(payload, "site/data.json", auto_unbox = TRUE, na = "null", digits = 4)
message("Wrote site/ (", length(checkpoints), " checkpoints)")
