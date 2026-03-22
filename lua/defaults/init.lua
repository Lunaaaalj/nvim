require("defaults.options")
require("defaults.keymaps")
require("defaults.lazy")

-- Load persisted colorscheme, fallback to kanso
local cs_file = vim.fn.stdpath("config") .. "/.colorscheme"
local ok, cs = pcall(vim.fn.readfile, cs_file)
vim.cmd("colorscheme " .. (ok and cs[1] or "kanso"))

-- Colorscheme picker: opens Telescope with live preview; selection is persisted
vim.keymap.set("n", "<leader>cs", function()
  require("telescope.builtin").colorscheme({ enable_preview = true })
end, { desc = "Pick colorscheme" })

-- Override colorscheme command to auto-persist any :colorscheme call
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function(ev)
    vim.fn.writefile({ ev.match }, cs_file)
  end,
})

