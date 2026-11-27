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
-- defaults/colors.lua, re-applied on ColorScheme; toasts are solid surfaces on
-- the scheme's real background, so they read the same in transparent mode),
-- the keys, and the lualine refresh on `User MurmurChanged`. The centre's
-- filetype `murmur` is in cursorline.lua's `unmanaged_ft`.
local function set_hl()
  local c = require("defaults.colors")
  local hl = function(name, val) vim.api.nvim_set_hl(0, name, val) end
  local bg = c.bg()
  local fg = c.fg("Normal") or 0xd4be98
  local acc = c.accent() or fg
  local err = c.fg("DiagnosticError") or 0xea6962
  local muted = c.fg("Comment") or c.blend(fg, bg, 0.55)
  hl("MurmurNormal", { fg = fg, bg = c.blend(fg, bg, 0.07) })
  hl("MurmurErrorNormal", { fg = fg, bg = c.blend(err, bg, 0.16) })
  hl("MurmurIsland", { fg = fg, bg = c.blend(fg, bg, 0.10) })
  hl("MurmurIslandError", { fg = fg, bg = c.blend(err, bg, 0.20) })
  hl("MurmurCentre", { fg = fg, bg = c.blend(fg, bg, 0.05) })
  hl("MurmurSel", { bg = c.blend(acc, bg, 0.20) })
  hl("MurmurFlash", { fg = fg, bg = c.blend(acc, bg, 0.30) })
  hl("MurmurAccent", { fg = acc })
  hl("MurmurUnread", { fg = acc })
  hl("MurmurTitle", { fg = acc, bold = true })
  hl("MurmurSource", { fg = muted })
  hl("MurmurMuted", { fg = muted })
  hl("MurmurFaint", { fg = c.blend(muted, bg, 0.6) })
  hl("MurmurKey", { fg = c.blend(muted, bg, 0.75) })
  hl("MurmurChip", { fg = muted })
  hl("MurmurChipOn", { fg = bg, bg = acc, bold = true })
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
