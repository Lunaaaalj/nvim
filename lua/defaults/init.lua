require("defaults.options")
require("defaults.keymaps")
require("defaults.lazy")
require("defaults.theme")
vim.cmd("colorscheme kanso")
vim.o.winbar = "%{%v:lua.require'nvim-navic'.get_location()%}"
vim.o.winbar = table.concat({
  "%{%v:lua.require'nvim-navic'.get_location()%}",
  "%=",
  "%#WinBar#",
  " ",
  "%f",
})
