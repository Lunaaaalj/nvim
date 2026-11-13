# Sourced by R kernels wrapped by lua/notebook/kernel.lua before
# IRkernel::main(). Reads the plot style Neovim writes
# ($NVIM_PLOT_STYLE_R, lua/notebook/plots.lua) right before each plot, so a
# toggle or colorscheme change shows on the next plot: the PNG background
# (repr.plot.bg), base graphics colours (par) and the ggplot2 theme.
local({
  path <- Sys.getenv("NVIM_PLOT_STYLE_R")
  if (!nzchar(path)) return(invisible())
  seen <- NULL
  s <- NULL

  gg <- function() {
    if (is.null(s) || !("ggplot2" %in% loadedNamespaces())) return(invisible())
    g <- asNamespace("ggplot2")
    g$theme_set(g$theme_gray() + g$theme(
      plot.background = g$element_rect(fill = s$bg, colour = NA),
      panel.background = g$element_rect(fill = s$panel, colour = NA),
      legend.background = g$element_rect(fill = s$bg, colour = NA),
      legend.key = g$element_rect(fill = s$bg, colour = NA),
      strip.background = g$element_rect(fill = s$panel, colour = NA),
      text = g$element_text(colour = s$fg),
      axis.text = g$element_text(colour = s$muted),
      axis.ticks = g$element_line(colour = s$muted),
      panel.grid = g$element_line(colour = s$grid)
    ))
  }

  load <- function() {
    m <- file.mtime(path)
    if (is.na(m)) return(FALSE)
    if (!identical(m, seen)) {
      seen <<- m
      s <<- source(path, local = TRUE)$value
      # same figure size as matplotlib's default, resolution from Neovim
      options(repr.plot.bg = s$bg, repr.plot.res = s$dpi, repr.plot.width = 6.4, repr.plot.height = 4.8)
      gg()
    }
    TRUE
  }

  setHook("before.plot.new", function() {
    if (load()) par(fg = s$fg, col.axis = s$muted, col.lab = s$fg, col.main = s$fg, col.sub = s$fg, bg = s$bg)
  })
  setHook("before.grid.newpage", function() load())
  setHook(packageEvent("ggplot2", "onLoad"), function(...) gg())
  load()
})
