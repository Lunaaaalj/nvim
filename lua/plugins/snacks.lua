-- snacks.nvim is already pulled in as a dependency of claudecode.nvim. This spec
-- turns on two of its modules:
--   * dashboard — a static startup screen (see header swapping below)
--   * scroll    — smooth animated scrolling (pairs with smear_cursor)
--
-- Header art: drop any ASCII art into `dashboard-header.txt` in the config root
-- (e.g. paste from https://www.asciiart.eu or https://patorjk.com/software/taag)
-- and it is used verbatim — no Lua editing needed. With no file, the built-in
-- Python snake below is used. The dashboard background is transparent: its
-- `SnacksDashboardNormal` group is stripped in lua/defaults/init.lua alongside
-- the other transparent groups.
--
-- Live data (GitHub contribution heatmap, PR/issue counts, Claude token usage)
-- comes from lua/defaults/dashboard_data.lua. It is fetched asynchronously and
-- file-cached, so it never blocks startup and renders as plain text + highlights.

local data = require("defaults.dashboard_data")

-- Built-in fallback header: a coiled Python snake.
local default_header = [[
      ,;;;;;;;,
     ;;;;;;;;;;;,
     ;;;'  '  ;;;;
     ;;;  @ @  ;;;;        ____
     ;;;;; _  ;;;;'      /     \
      ';;;;;;;;;'       /  ~~~ <
        ';;;;;___,____,/
          ';;;;;;;;;;,
            ';;;;;;;;;;
              ';;;;;;;;]]

local function header()
  local path = vim.fn.stdpath("config") .. "/dashboard-header.txt"
  if vim.fn.filereadable(path) == 1 then
    return table.concat(vim.fn.readfile(path), "\n")
  end
  return default_header
end

-- Subtitle line: weekday/date + the running Neovim version.
local function subtitle()
  local v = vim.version()
  return os.date("%A, %d %B %Y") .. "   ·   v" .. v.major .. "." .. v.minor .. "." .. v.patch
end

-- Section helper: build a centered text block in the given pane, or hide the
-- section (return nil) when its data isn't cached yet.
local function block(text, pane)
  if not text then
    return nil
  end
  return { pane = pane, text = text, align = "center", padding = 1 }
end

return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    scroll = { enabled = true },
    dashboard = {
      enabled = true,
      -- Two-column layout. Snacks needs ~2*width + pane_gap columns of terminal
      -- width to show both panes; on narrower windows it collapses to one column.
      width = 58,
      pane_gap = 6,
      preset = {
        keys = {
          { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
          { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
          { icon = " ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
          { icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
          { icon = " ", key = "p", desc = "Projects", action = ":lua Snacks.picker.projects()" },
          { icon = " ", key = "s", desc = "Restore Session", action = ":lua require('persistence').load()" },
          { icon = " ", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
          { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy" },
          { icon = " ", key = "m", desc = "Mason", action = ":Mason" },
          { icon = " ", key = "q", desc = "Quit", action = ":qa" },
        },
      },
      sections = {
        -- ── LEFT PANE ───────────────────────────────────────────────────────
        -- Section-as-function: `text` must be a string/Text[], not a function, so
        -- the section itself is the function and calls header() to get the string.
        function()
          return { pane = 1, text = header(), align = "center", padding = 1, hl = "SnacksDashboardHeader" }
        end,
        -- Section-as-function so the date is current each time the dashboard opens.
        function()
          return { pane = 1, text = { { subtitle(), hl = "SnacksDashboardDesc" } }, align = "center", padding = 2 }
        end,
        { pane = 1, section = "keys", gap = 1, padding = 2 },
        { pane = 1, icon = " ", title = "Recent Files", section = "recent_files", indent = 2, padding = 1 },
        { pane = 1, section = "startup" },

        -- ── RIGHT PANE ──────────────────────────────────────────────────────
        -- GitHub contribution heatmap (title + grid + legend).
        function()
          local grid = data.render_contrib()
          if not grid then
            return nil
          end
          local out = {}
          vim.list_extend(out, data.contrib_title())
          out[#out + 1] = { "\n\n" }
          vim.list_extend(out, grid)
          return { pane = 2, text = out, align = "center", padding = 2 }
        end,
        -- GitHub PR / review / issue counts.
        function()
          return block(data.render_counts(), 2)
        end,
        -- Updates line: GitHub notifications + available plugin updates.
        function()
          return block(data.render_updates(), 2)
        end,
        -- Claude token-usage sparkline.
        function()
          return block(data.render_usage(), 2)
        end,
      },
    },
  },
  config = function(_, opts)
    require("snacks").setup(opts)
    data.set_hl()
    vim.api.nvim_create_autocmd("ColorScheme", { callback = data.set_hl })

    -- Kick off a background refresh now and whenever the dashboard opens; stale
    -- caches refresh, fresh ones are reused. Data fills in via a debounced
    -- Snacks.dashboard.update() when each source returns.
    data.refresh(false)
    vim.api.nvim_create_autocmd("User", {
      pattern = "SnacksDashboardOpened",
      callback = function()
        data.refresh(false)
      end,
    })
  end,
}
