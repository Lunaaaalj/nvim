-- murmur.nvim: calmer notifications + a notification centre. Developed in its
-- own repo; see its README / :help murmur. It replaces vim.notify (noice's
-- notify is off) and noice routes its messages to it through the "murmur" view
-- backend the plugin ships (see lua/plugins/noice.lua).
--
-- Chosen in the "Murmur Notification Deck" mockup
-- (https://claude.ai/artifact/JTgLK2yNDCue5r218dMjF1): the island layout
-- (a pill in the middle of the bufferline row), the wipe motion and the drawer
-- centre.
--
-- Glue that lives here, not in the plugin: theme-derived colours (through
-- defaults/colors.lua, re-applied on ColorScheme; toasts are solid surfaces in
-- the scheme's popup-menu colours, so they read the same in transparent mode),
-- the keys, and the lualine refresh on `User MurmurChanged`. The centre's
-- filetype `murmur` is in cursorline.lua's `unmanaged_ft`.

-- Colours come from the scheme's own floating UI, not from a blend on its
-- background: schemes that are transparent by design (Ámbar Cielo) draw no
-- Normal/NormalFloat background at all, and blending on colors.bg()'s
-- fallback gave neutral black panels that matched nothing. The popup menu is
-- the one surface every scheme paints, so murmur's floats look like the
-- completion menu, its selection like PmenuSel and its titles like FloatTitle.
local function set_hl()
  local c = require("defaults.colors")
  local hl = function(name, val) vim.api.nvim_set_hl(0, name, val) end
  local bg_of = function(g) return c.attrs(g).bg end
  local fg = c.fg("Normal") or 0xd4be98
  local surface = bg_of("NormalFloat") or bg_of("Pmenu") or c.blend(fg, c.bg(), 0.08)
  local text = c.fg("Pmenu", "NormalFloat", "Normal") or fg
  local sel = bg_of("PmenuSel") or bg_of("Visual") or c.blend(fg, surface, 0.2)
  local title = c.fg("FloatTitle", "Title") or c.accent() or fg
  local err = c.fg("DiagnosticError") or 0xea6962
  local muted = c.fg("Comment") or c.blend(text, surface, 0.55)
  local faint = c.fg("NonText") or c.blend(muted, surface, 0.6)
  hl("MurmurNormal", { fg = text, bg = surface })
  hl("MurmurErrorNormal", { fg = text, bg = c.blend(err, surface, 0.22) })
  hl("MurmurIsland", { fg = text, bg = surface })
  hl("MurmurIslandError", { fg = text, bg = c.blend(err, surface, 0.25) })
  hl("MurmurCentre", { fg = text, bg = surface })
  hl("MurmurSel", { bg = sel })
  hl("MurmurFlash", { fg = text, bg = c.blend(title, surface, 0.3) })
  hl("MurmurAccent", { fg = title })
  hl("MurmurUnread", { fg = title })
  hl("MurmurTitle", { fg = title, bold = true })
  hl("MurmurSource", { fg = muted })
  hl("MurmurMuted", { fg = muted })
  hl("MurmurFaint", { fg = faint })
  hl("MurmurKey", { fg = faint })
  hl("MurmurChip", { fg = muted })
  hl("MurmurChipOn", { fg = text, bg = sel, bold = true })
  require("murmur.hl").derive() -- island caps follow MurmurIsland's bg
end

local function centre(mode)
  return function() require("murmur").toggle(mode) end
end

return {
  dir = "~/Downloads/GitHub/murmur.nvim",
  name = "murmur.nvim",
  lazy = false,
  priority = 900, -- replace vim.notify before other plugins start talking
  keys = {
    { "<leader>sn", centre(), desc = "Notifications: centre (drawer)" },
    { "<leader>sN", function() require("murmur").open("inbox") end, desc = "Notifications: search (inbox)" },
    { "<leader>sl", centre("log"), desc = "Notifications: log" },
    { "<leader>sd", function() require("murmur").dismiss() end, desc = "Notifications: dismiss" },
    {
      "<leader>uN",
      function()
        local on = require("murmur").set_focus()
        vim.api.nvim_echo({ { "Focus mode " .. (on and "on: only errors pop up" or "off") } }, false, {})
      end,
      desc = "Toggle notification focus mode",
    },
  },
  opts = {
    layout = "island",
    motion = "wipe",
    centre = "drawer",
  },
  config = function(_, opts)
    require("murmur").setup(opts)
    local group = vim.api.nvim_create_augroup("murmur_glue", { clear = true })
    set_hl()
    vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_hl })
    -- the "◆ N new" / focus segment in lualine
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "MurmurChanged",
      callback = function()
        local ok, lualine = pcall(require, "lualine")
        if ok then lualine.refresh({ place = { "statusline" } }) end
      end,
    })
  end,
}
