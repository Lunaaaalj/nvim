-- Async data layer for the snacks dashboard. Fetches (and file-caches) three
-- things, none of which ever block startup:
--   * GitHub contribution calendar (rendered as a heatmap grid)
--   * GitHub open PR / review / issue counts
--   * Claude Code token usage per day (from local ~/.claude logs, via
--     scripts/claude_usage.py)
--
-- Flow: dashboard sections read whatever is in the cache (instant). On open we
-- kick off refresh() in the background; when a source returns we write its cache
-- and trigger a single Snacks.dashboard.update() so the view fills in. Stale
-- caches (older than the TTL) are refreshed; fresh ones are reused.
--
-- Everything degrades gracefully: no `gh` / not authed / no logs simply means
-- the corresponding section renders nothing.

local M = {}

local uv = vim.uv or vim.loop
local cache_dir = vim.fn.stdpath("cache") .. "/dashboard"
local TTL = 30 * 60 -- seconds before a cache is considered stale

local files = {
  contrib = cache_dir .. "/contrib.json",
  counts = cache_dir .. "/counts.json",
  usage = cache_dir .. "/usage.json",
}

-- GitHub-style green ramp for the contribution heatmap + usage bars. Hardcoded on
-- purpose: it's a deliberate homage to the GitHub graph and stays recognizable
-- across colorschemes. Re-applied on ColorScheme in case a scheme clears them.
function M.set_hl()
  local levels = {
    GhContrib0 = "#2d333b", -- empty / faint
    GhContrib1 = "#0e4429",
    GhContrib2 = "#006d32",
    GhContrib3 = "#26a641",
    GhContrib4 = "#39d353",
  }
  for name, fg in pairs(levels) do
    vim.api.nvim_set_hl(0, name, { fg = fg })
  end
end

-- ---------------------------------------------------------------------------
-- cache io
-- ---------------------------------------------------------------------------

local function read_json(path)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines or #lines == 0 then
    return nil
  end
  local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  return ok2 and data or nil
end

local function write_json_raw(path, str)
  vim.fn.mkdir(cache_dir, "p")
  pcall(vim.fn.writefile, vim.split(str, "\n"), path)
end

local function stale(path)
  local st = uv.fs_stat(path)
  if not st then
    return true
  end
  return (os.time() - st.mtime.sec) > TTL
end

M.contrib = function()
  return read_json(files.contrib)
end
M.counts = function()
  return read_json(files.counts)
end
M.usage = function()
  return read_json(files.usage)
end

-- ---------------------------------------------------------------------------
-- async refresh
-- ---------------------------------------------------------------------------

local function run(cmd, on_ok)
  local ok = pcall(vim.system, cmd, { text = true }, function(res)
    if res.code == 0 and res.stdout and res.stdout ~= "" then
      vim.schedule(function()
        on_ok(res.stdout)
      end)
    end
  end)
  return ok
end

-- A debounced dashboard refresh so multiple sources landing together only
-- trigger one re-render.
local update_scheduled = false
local function ping_dashboard()
  if update_scheduled then
    return
  end
  update_scheduled = true
  vim.defer_fn(function()
    update_scheduled = false
    pcall(function()
      if Snacks and Snacks.dashboard then
        Snacks.dashboard.update()
      end
    end)
  end, 80)
end

function M.refresh(force)
  -- GitHub contribution calendar (authenticated viewer; no hardcoded username)
  if force or stale(files.contrib) then
    local query =
      "query{viewer{contributionsCollection{contributionCalendar{totalContributions weeks{contributionDays{contributionCount weekday}}}}}}"
    run({ "gh", "api", "graphql", "-f", "query=" .. query }, function(out)
      local ok, data = pcall(vim.json.decode, out)
      local cal = ok and data and data.data and data.data.viewer
        and data.data.viewer.contributionsCollection
        and data.data.viewer.contributionsCollection.contributionCalendar
      if cal then
        write_json_raw(files.contrib, vim.json.encode(cal))
        ping_dashboard()
      end
    end)
  end

  -- Open PR / review-requested / assigned-issue counts
  if force or stale(files.counts) then
    local script = table.concat({
      [[printf '{"prs":%s,"review":%s,"issues":%s,"notifications":%s}' ]],
      [["$(gh search prs --author=@me --state=open --json number -q 'length' 2>/dev/null || echo 0)" ]],
      [["$(gh search prs --review-requested=@me --state=open --json number -q 'length' 2>/dev/null || echo 0)" ]],
      [["$(gh search issues --assignee=@me --state=open --json number -q 'length' 2>/dev/null || echo 0)" ]],
      [["$(gh api notifications --jq 'length' 2>/dev/null || echo 0)"]],
    })
    run({ "bash", "-lc", script }, function(out)
      if out:match("^%s*{") then
        write_json_raw(files.counts, out)
        ping_dashboard()
      end
    end)
  end

  -- Claude usage from local logs
  if force or stale(files.usage) then
    local py = vim.fn.stdpath("config") .. "/scripts/claude_usage.py"
    if vim.fn.filereadable(py) == 1 then
      run({ "python3", py, "14" }, function(out)
        if out:match("^%s*{") then
          write_json_raw(files.usage, out)
          ping_dashboard()
        end
      end)
    end
  end
end

-- ---------------------------------------------------------------------------
-- renderers -> snacks dashboard Text[] (a single block; "\n" segments break lines)
-- ---------------------------------------------------------------------------

local function level(count)
  if count <= 0 then
    return 0
  elseif count <= 2 then
    return 1
  elseif count <= 5 then
    return 2
  elseif count <= 9 then
    return 3
  else
    return 4
  end
end

-- GitHub contribution heatmap: 7 rows (weekday) x up to 53 columns (week).
function M.render_contrib()
  local cal = M.contrib()
  if not cal or not cal.weeks then
    return nil
  end
  -- index counts by [week][weekday]
  local grid = {}
  for wi, week in ipairs(cal.weeks) do
    grid[wi] = {}
    for _, day in ipairs(week.contributionDays or {}) do
      grid[wi][day.weekday] = day.contributionCount
    end
  end
  local out = {}
  for wd = 0, 6 do
    for wi = 1, #cal.weeks do
      local c = grid[wi][wd]
      if c == nil then
        out[#out + 1] = { " " } -- pad ragged first/last week
      else
        out[#out + 1] = { "■", hl = "GhContrib" .. level(c) }
      end
    end
    if wd < 6 then
      out[#out + 1] = { "\n" }
    end
  end
  -- legend
  out[#out + 1] = { "\n\n" }
  out[#out + 1] = { "less ", hl = "SnacksDashboardDesc" }
  for l = 0, 4 do
    out[#out + 1] = { "■", hl = "GhContrib" .. l }
  end
  out[#out + 1] = { " more", hl = "SnacksDashboardDesc" }
  return out
end

function M.contrib_title()
  local cal = M.contrib()
  local total = cal and cal.totalContributions or nil
  local label = total and (" " .. total .. " contributions this year") or " GitHub activity"
  return { { label, hl = "SnacksDashboardTitle" } }
end

function M.render_counts()
  local c = M.counts()
  if not c then
    return nil
  end
  return {
    { "  " .. (c.prs or 0) .. " open PR", hl = "SnacksDashboardDesc" },
    { "   ", hl = "SnacksDashboardDesc" },
    { "  " .. (c.review or 0) .. " to review", hl = "SnacksDashboardDesc" },
    { "   ", hl = "SnacksDashboardDesc" },
    { "  " .. (c.issues or 0) .. " issues", hl = "SnacksDashboardDesc" },
  }
end

-- "Updates" line: unread GitHub notifications (from the counts cache) + the
-- number of plugin updates lazy.nvim's background checker has found.
function M.render_updates()
  local segs = {}
  local c = M.counts()
  if c and c.notifications ~= nil then
    segs[#segs + 1] = { " " .. c.notifications .. " notifications", hl = "SnacksDashboardDesc" }
  end
  local ok, status = pcall(require, "lazy.status")
  local upd = ok and status.updates() -- a count string, or nil when up to date
  if #segs > 0 then
    segs[#segs + 1] = { "   ", hl = "SnacksDashboardDesc" }
  end
  if upd then
    segs[#segs + 1] = { "󰏔 " .. upd .. " plugin updates", hl = "SnacksDashboardTitle" }
  else
    segs[#segs + 1] = { "󰏔 plugins up to date", hl = "SnacksDashboardDesc" }
  end
  return segs
end

local function humanize(n)
  n = n or 0
  if n >= 1e9 then
    return string.format("%.1fB", n / 1e9)
  elseif n >= 1e6 then
    return string.format("%.1fM", n / 1e6)
  elseif n >= 1e3 then
    return string.format("%.1fk", n / 1e3)
  end
  return tostring(n)
end

-- Claude usage: a colored sparkline of the last 14 days + headline numbers.
function M.render_usage()
  local u = M.usage()
  if not u or not u.days then
    return nil
  end
  local bars = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
  local max = 1
  for _, d in ipairs(u.days) do
    max = math.max(max, d.tokens or 0)
  end
  local out = {
    { "󰚩 Claude  ", hl = "SnacksDashboardTitle" },
    { "today " .. humanize(u.today) .. "  ·  14d " .. humanize(u.total), hl = "SnacksDashboardDesc" },
    { "\n" },
  }
  for _, d in ipairs(u.days) do
    local t = d.tokens or 0
    local idx = t <= 0 and 1 or math.max(1, math.min(#bars, math.ceil(t / max * #bars)))
    out[#out + 1] = { bars[idx] .. " ", hl = "GhContrib" .. (t <= 0 and 0 or level(math.ceil(t / max * 10))) }
  end
  return out
end

return M
