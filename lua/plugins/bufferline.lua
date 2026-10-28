-- Colours for every bufferline group, derived from the active scheme. A function
-- (not a table) so bufferline re-runs it on each ColorScheme, including the
-- reloads done by the transparency / background toggles.
--
-- bufferline's own defaults key the separators and the underline (`sp`) off
-- TabLineSel's bg: correct against a solid tabline, but with the bg stripped
-- they show up as stray bars and a bright block. So: no separator glyphs at all
-- (tabs are spaced by padding), and the active buffer gets an accent underline.
local function highlights(defaults)
  local c = require("defaults.colors")
  local accent = c.accent()
  local text = c.fg("Normal")
  local muted = c.fg("Comment", "NonText")
  local rule = c.fg("WinSeparator", "VertSplit", "Comment")
  -- buffers shown in another window: halfway between muted and full text
  local visible = (text and muted) and c.blend(text, muted, 0.5) or text

  local hl = {}
  for name, attrs in pairs(defaults.highlights) do
    hl[name] = {}
    if vim.g.ui_transparent then hl[name].bg = "NONE" end
    if attrs.underline then hl[name].sp = accent end
  end

  local function set(name, attrs) hl[name] = vim.tbl_extend("force", hl[name] or {}, attrs) end

  for _, name in ipairs({ "fill", "background", "tab", "close_button", "duplicate", "trunc_marker" }) do
    set(name, { fg = muted })
  end
  for _, name in ipairs({ "buffer_visible", "close_button_visible", "duplicate_visible", "tab_selected" }) do
    set(name, { fg = visible })
  end
  set("buffer_selected", { fg = text, bold = true, italic = false })
  set("close_button_selected", { fg = text })
  set("duplicate_selected", { fg = muted, italic = true })
  set("duplicate", { italic = true })
  set("duplicate_visible", { italic = true })

  set("modified", { fg = muted })
  set("modified_visible", { fg = visible })
  set("modified_selected", { fg = accent })

  -- buffers draw no separators now; tabpage separators (several tabs) still do
  for _, name in ipairs({ "separator", "separator_visible", "separator_selected", "tab_separator", "tab_separator_selected" }) do
    set(name, { fg = rule })
  end
  set("indicator_selected", { fg = accent, sp = accent })
  -- the line under the neo-tree title continues the tree's window separator
  set("offset_separator", { fg = rule })
  return hl
end

return {
  "akinsho/bufferline.nvim",
  version = "*",
  dependencies = "nvim-tree/nvim-web-devicons",
  opts = {
    options = {
      mode = "buffers",
      -- Overwrite our groups on every ColorScheme. With the default (themable)
      -- they are set with `:hi default`, so the first values -- computed against
      -- the builtin scheme before the persisted one loads -- stick for good.
      themable = false,
      -- Accent underline under the active buffer instead of a filled block —
      -- reads cleanly against the transparent background.
      indicator = { style = "underline" },
      separator_style = { "", "" },
      diagnostics = "nvim_lsp",
      diagnostics_indicator = function(count, level)
        local icon = level:match("error") and " " or " "
        return " " .. icon .. count
      end,
      color_icons = true,
      show_buffer_close_icons = false,
      show_close_icon = false,
      always_show_bufferline = true,
      modified_icon = "●",
      left_trunc_marker = "",
      right_trunc_marker = "",
      hover = { enabled = true, delay = 150, reveal = { "close" } },
      offsets = {
        {
          filetype = "neo-tree",
          -- active neo-tree source (icon + name), since its tabs are icon-only
          text = function() return require("neotree_tabs").active_label() end,
          highlight = "Directory",
          text_align = "left",
          separator = true,
        },
      },
    },
    highlights = highlights,
  },
}
