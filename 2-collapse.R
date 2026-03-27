library(nanoparquet)
library(gha)

month <- format(Sys.time(), "%Y-%m", tz = "America/Chicago")
paths <- Sys.glob(paste0("data/", month, "-*.parquet"))
gha_notice("Collapsing {length(paths)} daily files for {month}")

data <- paths |> lapply(\(path) {
  tryCatch(
    read_parquet(path),
    error = function(e) {
      gha_warning("Skipping corrupt file {path}: {conditionMessage(e)}")
      NULL
    }
  )
})
data <- do.call(rbind, data)
data <- data[!duplicated(data[c("id", "time")]), ]

dir.create("data/collapsed", showWarnings = FALSE)
write_parquet(data, sprintf("data/collapsed/%s.parquet", month))
