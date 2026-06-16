-- Renders color codes (#aabbcc, rgb(), color names, etc.) with their actual
-- color inline. Handy when tweaking the colorschemes under lua/plugins/.
return {
  "NvChad/nvim-colorizer.lua",
  event = { "BufReadPre", "BufNewFile" },
  opts = {
    filetypes = { "*" },
    user_default_options = {
      RGB = true, -- #RGB
      RRGGBB = true, -- #RRGGBB
      names = false, -- don't colorize bare words like "red" (too noisy in prose)
      RRGGBBAA = true, -- #RRGGBBAA
      rgb_fn = true, -- rgb() / rgba()
      hsl_fn = true, -- hsl() / hsla()
      css = true, -- enable css features (rgb_fn, hsl_fn, names, ...)
      mode = "background", -- swatch behind the value
      tailwind = false,
    },
  },
}
