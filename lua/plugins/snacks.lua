-- snacks.nvim is already pulled in as a dependency of claudecode.nvim. This spec
-- turns on two of its modules:
--   * dashboard — a minimal, single-column start screen (see below)
--   * scroll    — smooth animated scrolling (pairs with smear_cursor); currently OFF
--
-- Dashboard, top to bottom, all centered: header art, a big block-digit clock + date
-- (lua/defaults/bigclock.lua), a
-- GitHub stats line (open PRs · issues · contributions · streak), and a one-line
-- key hint. Quiet colors: muted text (Comment fg) plus the scheme's own
-- foreground (Normal fg) for the clock, numbers and keys, so it matches every
-- theme, transparent or solid.
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

-- Fuzzy-pick a directory under $HOME and :cd into it. Snacks' `files` source
-- only lists files, so this streams `find` through the generic `proc` finder (no
-- fd/zoxide dependency). `find_args` is the expression after the start point and
-- `to_dir` turns one output line into the directory (relative to $HOME).
local function pick_cd(title, find_args, to_dir)
  local home = vim.fn.expand("~")
  Snacks.picker.pick({
    title = title,
    finder = "proc",
    cmd = "find",
    notify = false, -- find exits non-zero on TCC-protected dirs; results still stream
    cwd = home,
    args = vim.list_extend({ ".", "-mindepth", "1" }, find_args),
    transform = function(item)
      -- strip "./" (and the repo's "/.git"); must be idempotent: snacks applies
      -- `transform` twice (in the proc finder and again in the picker's item pipeline)
      item.file = to_dir(item.text)
      item.text = item.file
      item.cwd = home
      item.dir = true
    end,
    format = "file",
    preview = "directory",
    confirm = function(picker, item)
      picker:close()
      if not item then return end
      vim.cmd.cd(vim.fn.fnameescape(home .. "/" .. item.file))
      vim.notify("cwd → " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":~"))
    end,
  })
end

-- Any directory, pruning dotdirs, node_modules and ~/Library to keep the walk fast.
local function pick_dir()
  pick_cd("cd", {
    "-maxdepth", "5",
    "(", "-name", ".*", "-o", "-name", "node_modules", "-o", "-name", "__pycache__",
    "-o", "-path", "./Library", ")", "-prune",
    "-o", "-type", "d", "-print",
  }, function(line) return (line:gsub("^%./", "")) end)
end

-- Git repositories only: every directory that has a `.git` (dir or file, so
-- worktrees count) is listed once and not descended into. Dotdirs are pruned
-- except `.config`, where this very config lives; $HOME's own `.git` is skipped.
local function pick_repo()
  pick_cd("git repos", {
    "-maxdepth", "6",
    "(", "-path", "./Library", "-o", "-path", "./.git", "-o", "-name", "node_modules",
    "-o", "-name", "__pycache__",
    "-o", "(", "-name", ".?*", "!", "-name", ".git", "!", "-name", ".config", ")", ")", "-prune",
    "-o", "-name", ".git", "-prune", "-print",
  }, function(line) return (line:gsub("^%./", ""):gsub("/%.git$", "")) end)
end

-- One table drives both the visible hint line (entries with `hint`) and the
-- key bindings (every entry, as hidden items), so the two can't drift apart.
local keys = {
  { key = "f", hint = "find", action = ":lua Snacks.dashboard.pick('files')" },
  { key = "r", hint = "recent", action = ":lua Snacks.dashboard.pick('oldfiles')" },
  { key = "d", hint = "cd", action = pick_dir },
  { key = "R", hint = "repo", action = pick_repo },
  { key = "g", action = ":lua Snacks.dashboard.pick('live_grep')" },
  { key = "n", action = ":ene | startinsert" },
  { key = "p", action = ":lua Snacks.picker.projects()" },
  { key = "s", hint = "session", action = ":lua require('persistence').load()" },
  { key = "c", hint = "config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
  { key = "l", action = ":Lazy" },
  { key = "m", action = ":Mason" },
  { key = "G", action = ":Upstream" },
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

-- DashboardAccent is the scheme's own text colour (Normal fg, bold), not the
-- Function-fg accent: the dashboard should read like the scheme's text.
local function set_hl()
  local colors = require("defaults.colors")
  vim.api.nvim_set_hl(0, "DashboardAccent", { fg = colors.fg("Normal") or colors.accent(), bold = true })
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
    -- Smooth scrolling is OFF for now (it made the view and cursor jump back and
    -- forth on the dashboard). Set `enabled = true` to bring it back; the
    -- timings below are kept: snappier than the 200ms default so <C-d> / n / G
    -- don't feel laggy, with a short linear animation for held-key repeats.
    scroll = {
      enabled = false,
      animate = { duration = { step = 10, total = 140 }, easing = "outQuad" },
      animate_repeat = { delay = 100, duration = { step = 5, total = 50 }, easing = "linear" },
    },
    dashboard = {
      enabled = true,
      width = math.max(header_width, 60),
      sections = {
        { text = table.concat(header_lines, "\n"), align = "center", padding = 2, hl = "SnacksDashboardHeader" },
        -- Sections-as-functions re-run on every render, so the time stays current.
        function()
          local text = {}
          for _, row in ipairs(require("defaults.bigclock").render(os.date("%H:%M"))) do
            text[#text + 1] = { row, hl = "DashboardAccent" }
            text[#text + 1] = { "\n" }
          end
          text[#text + 1] = { "\n" } -- one blank row between the digits and the date
          text[#text + 1] = { os.date("%A · %d %B %Y"), hl = "DashboardMuted" }
          return { align = "center", padding = 2, text = text }
        end,
        -- Stats and key hints sit together as a two-line footer under the clock,
        -- so the whole block stays compact and the art keeps clear of one box.
        function()
          local stats = data.render_stats()
          return stats and { text = stats, align = "center", padding = 1 } or nil
        end,
        function()
          return { text = hint_line(), align = "center" }
        end,
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
