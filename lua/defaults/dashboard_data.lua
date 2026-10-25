-- Async data layer for the snacks dashboard's stats line: open PRs, open
-- issues, contributions in the last year, and the current contribution streak.
--
-- Everything comes from ONE `gh api graphql` request (search `issueCount` is
-- exact, unlike `gh search … -q length`, which caps at gh's default limit of
-- 30). The result is file-cached at stdpath("cache")/dashboard/stats.json
-- with a 30-min TTL. The dashboard reads the cache instantly (never blocking
-- startup); refresh() runs in the background and a debounced
-- Snacks.dashboard.update() fills the view in when it returns.
--
-- Degrades gracefully: no `gh` / not authed / offline → no cache → the stats
-- line simply isn't rendered.

local M = {}

local uv = vim.uv or vim.loop
local cache_dir = vim.fn.stdpath("cache") .. "/dashboard"
local cache_file = cache_dir .. "/stats.json"
local TTL = 30 * 60 -- seconds before the cache is considered stale

M.opts = {
  -- which open issues to count: "assignee" (actionable) or "author" (filed by you)
  issues = "assignee",
}

function M.setup(opts)
  M.opts = vim.tbl_extend("force", M.opts, opts or {})
end

-- ---------------------------------------------------------------------------
-- cache io
-- ---------------------------------------------------------------------------

local function read_cache()
  if vim.fn.filereadable(cache_file) == 0 then return nil end
  local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(cache_file), "\n")) end)
  return ok and type(data) == "table" and data or nil
end

local function stale()
  local st = uv.fs_stat(cache_file)
  if not st or (os.time() - st.mtime.sec) > TTL then return true end
  -- a cache built for the other issues mode is stale too
  local c = read_cache()
  return not c or c.issues_kind ~= M.opts.issues
end

-- ---------------------------------------------------------------------------
-- async refresh
-- ---------------------------------------------------------------------------

-- Debounced dashboard redraw, so a refresh landing mid-render only re-renders once.
local update_scheduled = false
local function ping_dashboard()
  if update_scheduled then return end
  update_scheduled = true
  vim.defer_fn(function()
    update_scheduled = false
    pcall(function()
      if Snacks and Snacks.dashboard then Snacks.dashboard.update() end
    end)
  end, 80)
end

-- Consecutive days with > 0 contributions, ending today (local date). Today
-- may still be empty without breaking the streak, and calendar days after
-- today (GitHub's calendar runs on its own timezone) are ignored.
local function streak(days)
  local today = os.date("%Y-%m-%d")
  local i = #days
  while i >= 1 and days[i].date > today do i = i - 1 end
  if i >= 1 and days[i].date == today and days[i].count == 0 then i = i - 1 end
  local n = 0
  while i >= 1 and days[i].count > 0 do
    n, i = n + 1, i - 1
  end
  return n
end

local function query()
  return ([[query {
  viewer { contributionsCollection { contributionCalendar {
    totalContributions weeks { contributionDays { contributionCount date } } } } }
  prs: search(query: "is:pr is:open author:@me", type: ISSUE) { issueCount }
  issues: search(query: "is:issue is:open %s:@me", type: ISSUE) { issueCount }
}]]):format(M.opts.issues)
end

function M.refresh(force)
  if not force and not stale() then return end
  local kind = M.opts.issues
  pcall(vim.system, { "gh", "api", "graphql", "-f", "query=" .. query() }, { text = true }, function(res)
    if res.code ~= 0 or not res.stdout then return end
    vim.schedule(function()
      local ok, out = pcall(vim.json.decode, res.stdout)
      local d = ok and type(out) == "table" and out.data
      local cal = d and vim.tbl_get(d, "viewer", "contributionsCollection", "contributionCalendar")
      if not cal then return end
      local days = {}
      for _, week in ipairs(cal.weeks or {}) do
        for _, day in ipairs(week.contributionDays or {}) do
          days[#days + 1] = { date = day.date, count = day.contributionCount or 0 }
        end
      end
      table.sort(days, function(a, b) return a.date < b.date end)
      vim.fn.mkdir(cache_dir, "p")
      pcall(vim.fn.writefile, { vim.json.encode({
        prs = vim.tbl_get(d, "prs", "issueCount") or 0,
        issues = vim.tbl_get(d, "issues", "issueCount") or 0,
        issues_kind = kind,
        contributions = cal.totalContributions or 0,
        streak = streak(days),
      }) }, cache_file)
      ping_dashboard()
    end)
  end)
end

-- ---------------------------------------------------------------------------
-- renderer -> snacks dashboard Text[]
-- ---------------------------------------------------------------------------

local function thousands(n)
  local s = tostring(n)
  while true do
    local r, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
    s = r
    if k == 0 then return s end
  end
end

-- "4 open PRs · 3 issues · 1,284 contributions · 12 day streak", numbers in
-- the accent, labels muted. nil (line hidden) until the first fetch lands.
function M.render_stats()
  local c = read_cache()
  if not c then return nil end
  local parts = {
    { c.prs, c.prs == 1 and "open PR" or "open PRs" },
    { c.issues, c.issues == 1 and "issue" or "issues" },
    { c.contributions, c.contributions == 1 and "contribution" or "contributions" },
  }
  if (c.streak or 0) > 0 then parts[#parts + 1] = { c.streak, "day streak" } end
  local out = {}
  for i, p in ipairs(parts) do
    if i > 1 then out[#out + 1] = { "   ·   ", hl = "DashboardMuted" } end
    out[#out + 1] = { thousands(p[1] or 0), hl = "DashboardAccent" }
    out[#out + 1] = { " " .. p[2], hl = "DashboardMuted" }
  end
  return out
end

return M
