-- Flash on yank: the yanked text briefly highlights and fades out. Only yank is
-- enabled; paste/search/undo would hijack p/P, n/N and u/<C-r>.
return {
  "rachartier/tiny-glimmer.nvim",
  event = "VeryLazy",
  opts = {
    -- the fade goes Visual -> Normal; Normal has no bg when transparent, so
    -- fade toward what is actually behind the editor
    transparency_color = require("defaults.colors").terminal_bg,
    autoreload = true, -- re-read Visual/Normal after :colorscheme
    overwrite = {
      yank = { enabled = true, default_animation = "fade" },
      paste = { enabled = false },
      search = { enabled = false },
      undo = { enabled = false },
      redo = { enabled = false },
    },
    animations = {
      fade = { max_duration = 350, min_duration = 250, easing = "outQuad" },
    },
  },
}
