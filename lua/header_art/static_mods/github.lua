-- Review requests, my open PRs (with check state) and assigned issues, from
-- dashboard_data's cache (one gh request every 30 min). <CR> opens the item in
-- the browser.
local U = require("header_art.static_util")

local function data()
  local ok, d = pcall(function() return require("defaults.dashboard_data").stats() end)
  return ok and type(d) == "table" and d.v and d or nil
end

local function item(n, w, right)
  local repo = n.repo and n.repo:match("[^/]+$") or ""
  return U.row({
    { "  " }, { repo .. " ", "mid" }, { "#" .. n.number .. " ", "dim" }, { n.title or "" },
  }, right or { { U.age(U.iso_epoch(n.updated) or os.time()), "dim" } }, w, function() vim.ui.open(n.url) end)
end

local CHECK = { pass = { "pass", "ok" }, fail = { "fail", "err" }, pending = { "...", "warn" } }

return {
  id = "github",
  title = "GITHUB",
  badge = "G",
  on = { "User DashboardDataChanged", "User UpstreamChanged" },
  available = function() return data() ~= nil end,
  render = function(w)
    local d = data() or {}
    local out = {}
    local function head(sym, cls, text, bold) out[#out + 1] = U.line({ { sym .. " ", cls }, { text, bold and "b" or "dim" } }) end
    local rv = d.reviews or { count = 0, nodes = {} }
    if rv.count > 0 then head("◆", "acc", rv.count .. (rv.count == 1 and " review request" or " review requests"), true)
    else head("◇", "dim", "no reviews waiting") end
    for i, n in ipairs(rv.nodes or {}) do if i <= 2 then out[#out + 1] = item(n, w) end end
    if (d.prs or 0) > 0 then
      head("●", d.failing and d.failing > 0 and "err" or "ok", d.prs .. (d.prs == 1 and " open PR" or " open PRs"), true)
      for i, n in ipairs(d.pr_nodes or {}) do
        local c = CHECK[n.checks or ""]
        if i <= 2 then out[#out + 1] = item(n, w, c and { { c[1], c[2] } } or nil) end
      end
    end
    if (d.issues or 0) > 0 then
      head("◇", "warn", d.issues .. (d.issues == 1 and " issue assigned" or " issues assigned"), true)
      for i, n in ipairs(d.issue_nodes or {}) do if i <= 2 then out[#out + 1] = item(n, w) end end
    end
    local spark = {}
    for i = math.max(1, #(d.days or {}) - 13), #(d.days or {}) do spark[#spark + 1] = d.days[i].count end
    out[#out + 1] = U.line({
      { "contributions ", "dim" }, { tostring(d.contributions or 0), "mid" }, { "  streak ", "dim" }, { (d.streak or 0) .. "d", "acc" },
      { "  " .. U.spark(spark), "acc" },
    })
    return out
  end,
}
