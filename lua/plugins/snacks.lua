-- snacks.nvim is already pulled in as a dependency of claudecode.nvim. This spec
-- turns on two of its modules:
--   * dashboard — a minimal, single-column start screen (see below)
--   * scroll    — smooth animated scrolling (pairs with smear_cursor)
--
-- Dashboard, top to bottom, all centered: header art, a live clock + date, a
-- GitHub stats line (open PRs · issues · contributions · streak), and a one-line
-- key hint. Quiet colors: muted text plus ONE accent taken from the active
-- scheme, so it matches every theme, transparent or solid.
--
-- Header art: drop any ASCII art into `dashboard-header.txt` in the config root
-- (e.g. paste from https://www.asciiart.eu or https://patorjk.com/software/taag)
-- and it is used verbatim — no Lua editing needed. With no file, the built-in
-- Python snake below is used. The dashboard width follows the art's widest
-- line. The background is transparent: `SnacksDashboardNormal` is stripped in
-- lua/defaults/init.lua alongside the other transparent groups.
--
-- The stats come from lua/defaults/dashboard_data.lua (one async, file-cached
-- `gh api graphql` call), so they never block startup.

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

local header_lines = (function()
  local path = vim.fn.stdpath("config") .. "/dashboard-header.txt"
  if vim.fn.filereadable(path) == 1 then return vim.fn.readfile(path) end
  return vim.split(default_header, "\n")
end)()

local header_width = 0
for _, l in ipairs(header_lines) do
  header_width = math.max(header_width, vim.api.nvim_strwidth(l))
end

-- One table drives both the visible hint line (entries with `hint`) and the
-- key bindings (every entry, as hidden items), so the two can't drift apart.
local keys = {
  { key = "f", hint = "find", action = ":lua Snacks.dashboard.pick('files')" },
  { key = "r", hint = "recent", action = ":lua Snacks.dashboard.pick('oldfiles')" },
  { key = "g", action = ":lua Snacks.dashboard.pick('live_grep')" },
  { key = "n", action = ":ene | startinsert" },
  { key = "p", action = ":lua Snacks.picker.projects()" },
  { key = "s", hint = "session", action = ":lua require('persistence').load()" },
  { key = "c", hint = "config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
  { key = "l", action = ":Lazy" },
  { key = "m", action = ":Mason" },
  { key = "q", hint = "quit", action = ":qa" },
}

local function hint_line()
  local out = {}
  for _, k in ipairs(keys) do
    if k.hint then
      if #out > 0 then out[#out + 1] = { "  ·  ", hl = "DashboardMuted" } end
      out[#out + 1] = { k.key, hl = "DashboardAccent" }
      out[#out + 1] = { " " .. k.hint, hl = "DashboardMuted" }
    end
  end
  return out
end

local function set_hl()
  local colors = require("defaults.colors")
  vim.api.nvim_set_hl(0, "DashboardAccent", { fg = colors.accent(), bold = true })
  vim.api.nvim_set_hl(0, "DashboardMuted", { fg = colors.fg("Comment") })
end

-- Live clock: a uv timer that fires on each minute boundary, but only while a
-- dashboard window is visible. It stops itself otherwise, so it never runs
-- while editing.
local timer
local function dashboard_visible()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "snacks_dashboard" then return true end
  end
  return false
end
local function stop_clock()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end
local function start_clock()
  if timer then return end
  timer = (vim.uv or vim.loop).new_timer()
  local ms_to_minute = (60 - tonumber(os.date("%S"))) * 1000
  timer:start(ms_to_minute, 60 * 1000, vim.schedule_wrap(function()
    if not dashboard_visible() then return stop_clock() end
    Snacks.dashboard.update()
  end))
end

return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    scroll = { enabled = true },
    dashboard = {
      enabled = true,
      width = math.max(header_width, 60),
      sections = {
        { text = table.concat(header_lines, "\n"), align = "center", padding = 2, hl = "SnacksDashboardHeader" },
        -- Sections-as-functions re-run on every render, so the time stays current.
        function()
          local time = os.date("%H:%M"):gsub(".", "%0 "):sub(1, -2) -- "1 4 : 3 2", a little larger
          return {
            align = "center",
            padding = 2,
            text = {
              { time, hl = "DashboardAccent" },
              { "\n" },
              { os.date("%A · %d %B %Y"), hl = "DashboardMuted" },
            },
          }
        end,
        function()
          local stats = data.render_stats()
          return stats and { text = stats, align = "center", padding = 2 } or nil
        end,
        { text = hint_line(), align = "center" },
        -- every key stays bound, without its own row
        vim.tbl_map(function(k) return { key = k.key, action = k.action, hidden = true } end, keys),
      },
    },
  },
  config = function(_, opts)
    require("snacks").setup(opts)
    data.setup({ issues = "assignee" }) -- or "author"
    set_hl()

    local grp = vim.api.nvim_create_augroup("DashboardLive", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", { group = grp, callback = set_hl })
    -- Refresh stats (stale cache only) and run the clock while the dashboard is up.
    data.refresh(false)
    vim.api.nvim_create_autocmd("User", {
      group = grp,
      pattern = "SnacksDashboardOpened",
      callback = function()
        data.refresh(false)
        start_clock()
      end,
    })
    vim.api.nvim_create_autocmd("BufEnter", {
      group = grp,
      callback = function()
        if vim.bo.filetype == "snacks_dashboard" then start_clock() end
      end,
    })
    vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout" }, {
      group = grp,
      callback = function(ev)
        if vim.bo[ev.buf].filetype == "snacks_dashboard" then vim.schedule(function()
          if not dashboard_visible() then stop_clock() end
        end) end
      end,
    })

    -- One-time cleanup of the caches from the old multi-source dashboard.
    for _, f in ipairs({ "contrib.json", "counts.json", "usage.json" }) do
      vim.fn.delete(vim.fn.stdpath("cache") .. "/dashboard/" .. f)
    end
  end,
}
