-- Winbar breadcrumbs you can open: every part of the path (folders, the file,
-- the symbols from LSP or treesitter) is a menu of its siblings. Hovering a
-- file in a menu previews it in the window underneath. Replaces barbecue.nvim
-- + nvim-navic (dropbar has its own LSP/treesitter symbol sources).
--
-- Only ordinary file windows get a bar: terminals keep toggleterm's own winbar
-- (`terminals.winbar_label`), neo-tree its source selector, pdfview its status.

-- Which windows get a bar (the winbar check is separate: see `enable`).
local function wants(buf, win)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then return false end
  if vim.fn.win_gettype(win) ~= "" then return false end
  if vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype == "help" then return false end
  local stat = vim.uv.fs_stat(vim.api.nvim_buf_get_name(buf))
  return not (stat and stat.size > 1024 * 1024)
end

local BAR = "%{%v:lua.dropbar()%}"

local function highlights()
  local colors = require("defaults.colors")
  local set = function(name, def) vim.api.nvim_set_hl(0, name, def) end
  local normal = colors.fg("Normal") or 0xc0c0c0
  local muted = colors.fg("Comment") or normal
  local accent = colors.accent() or normal
  local base = vim.o.background == "light" and 0xffffff
    or (vim.g.ui_transparent and tonumber(colors.terminal_bg:sub(2), 16))
    or colors.bg()
  local band = colors.blend(normal, base, 0.12)

  -- The bar: the path recedes, the pick letters stand out in the accent.
  set("DropBarIconUISeparator", { fg = colors.blend(muted, base, 0.6) })
  set("DropBarIconUIPickPivot", { fg = accent, bold = true, reverse = true })
  set("DropBarCurrentContext", { bg = band })
  set("DropBarHover", { bg = band })
  set("DropBarKindFolder", { fg = muted })
  set("DropBarKindFile", { fg = normal, bold = true })

  -- Menus: the selected entry is a band (Visual/IncSearch are loud in most
  -- schemes); the previewed range in the source window is a fainter one.
  set("DropBarMenuHoverEntry", { bg = band, bold = true })
  set("DropBarMenuCurrentContext", { bg = band })
  set("DropBarMenuHoverSymbol", { bold = true })
  set("DropBarPreview", { bg = colors.blend(accent, base, 0.15) })
  set("DropBarFzfMatch", { fg = accent, bold = true })
  set("DropBarMenuFloatBorder", { fg = colors.blend(normal, base, 0.25) })
end

return {
  "Bekaboo/dropbar.nvim",
  event = { "BufReadPost", "BufNewFile" },
  keys = {
    { "<leader>;", function() require("dropbar.api").pick() end, desc = "Breadcrumbs: pick a segment" },
    { "[;", function() require("dropbar.api").goto_context_start() end, desc = "Breadcrumbs: start of current context" },
    { "];", function() require("dropbar.api").select_next_context() end, desc = "Breadcrumbs: next context" },
  },
  opts = {
    bar = {
      -- A window whose winbar is someone else's (toggleterm, pdfview) is left alone.
      enable = function(buf, win, _)
        local bar = vim.api.nvim_win_is_valid(win) and vim.wo[win].winbar or ""
        return (bar == "" or bar == BAR) and wants(buf, win)
      end,
    },
    menu = {
      win_configs = { border = "rounded" },
    },
  },
  config = function(_, opts)
    require("dropbar").setup(opts)
    highlights()
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("DropBarColors", { clear = true }),
      callback = highlights,
    })
    -- dropbar sets the bar with :setlocal, and a buffer shown in that window
    -- for the first time inherits it (`:enew`, a ref:// page, a scratch
    -- buffer, a terminal: buftype is set only at TermOpen, so claude_chats'
    -- buffers would keep it), where dropbar() would then draw a bar anyway.
    vim.api.nvim_create_autocmd({ "BufWinEnter", "TermOpen" }, {
      group = vim.api.nvim_create_augroup("DropBarScope", { clear = true }),
      callback = function(ev)
        for _, win in ipairs(vim.fn.win_findbuf(ev.buf)) do
          if vim.wo[win].winbar == BAR and not wants(ev.buf, win) then
            vim.wo[win][0].winbar = ""
          end
        end
      end,
    })
    -- Menus are floats: the global winblend = 10 would blend them into the
    -- text under them, which is exactly what the menu is drawn over.
    -- nvim_open_win takes no winblend; menus open focused, and their WinEnter
    -- fires before the menu buffer is in the window, so BufEnter does it.
    vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
      group = vim.api.nvim_create_augroup("DropBarMenuBlend", { clear = true }),
      callback = function()
        local ft = vim.bo.filetype
        if ft == "dropbar_menu" or ft == "dropbar_menu_fzf" then vim.wo.winblend = 0 end
      end,
    })
  end,
}
