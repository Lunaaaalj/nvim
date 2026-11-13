# R_PROFILE_USER for the pinned R REPL inside Neovim (lua/notebook/repl.lua).
#
# With R_PROFILE_USER set, R reads nothing else, so first source the profile
# R would have read: a previous $R_PROFILE_USER, else ./.Rprofile (renv),
# else ~/.Rprofile.
local({
  orig <- Sys.getenv("NVIM_R_PROFILE_ORIG")
  if (!nzchar(orig)) orig <- if (file.exists(".Rprofile")) ".Rprofile" else path.expand("~/.Rprofile")
  if (file.exists(orig)) source(orig)
})

# Plots back into Neovim: a Neovim :terminal can't draw kitty graphics, so
# plots go to an invisible recording device, and after each top-level command
# whose display list changed, it is replayed into a PNG that the parent Neovim
# ($NVIM) shows in its image split. Incremental base graphics (plot() then
# lines()) keep working, because the device stays open. Colours: the plot
# paper (kernel_startup.R hooks + the style's bg).
if (interactive() && nzchar(Sys.getenv("NVIM")) && nzchar(Sys.getenv("NVIM_PLOT_STYLE_R"))) local({
  startup <- file.path(dirname(Sys.getenv("R_PROFILE_USER")), "kernel_startup.R")
  if (file.exists(startup)) source(startup)
  style <- function() {
    tryCatch(source(Sys.getenv("NVIM_PLOT_STYLE_R"), local = TRUE)$value,
      error = function(e) list(bg = "white", dpi = 100))
  }
  dir <- file.path(tempdir(), "nvim-plots")
  dir.create(dir, showWarnings = FALSE)
  options(device = function(...) {
    grDevices::pdf(NULL, width = 6.4, height = 4.8)
    grDevices::dev.control(displaylist = "enable")
  })
  last <- NULL
  n <- 0L
  notify <- function(f) {
    expr <- sprintf("v:lua.require'notebook.plots'.show_file('%s')", f)
    system2(Sys.getenv("NVIM_PROG", "nvim"),
      c("--server", shQuote(Sys.getenv("NVIM")), "--remote-expr", shQuote(expr)),
      stdout = FALSE, stderr = FALSE, wait = FALSE)
  }
  invisible(addTaskCallback(function(...) {
    if (grDevices::dev.cur() > 1) {
      p <- tryCatch(grDevices::recordPlot(), error = function(e) NULL)
      if (!is.null(p) && length(p[[1]]) > 0 && !identical(p[[1]], last)) {
        last <<- p[[1]]
        n <<- n + 1L
        s <- style()
        f <- file.path(dir, sprintf("plot-%d-%d.png", Sys.getpid(), n))
        cur <- grDevices::dev.cur()
        grDevices::png(f, width = 6.4, height = 4.8, units = "in", res = s$dpi, bg = s$bg)
        try(grDevices::replayPlot(p), silent = TRUE)
        grDevices::dev.off()
        grDevices::dev.set(cur)
        notify(f)
      }
    }
    TRUE
  }, name = "nvim-plots"))
})
