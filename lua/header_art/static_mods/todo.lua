-- TODO/FIXME/HACK/BUG counts for the project (async ripgrep, debounced after
-- writes) next to the diagnostics count, with the first FIXMEs listed.
local U = require("header_art.static_util")
local uv = vim.uv or vim.loop

local cache = { cwd = nil, counts = {}, top = {}, at = 0 }
local running, pending = false, nil
local PATTERN = [[\b(TODO|FIXME|HACK|BUG)(\([^)]*\))?:]]

local function scan()
  local cwd = vim.fn.getcwd()
  if cwd == vim.env.HOME or cwd == "/" or vim.fn.executable("rg") == 0 then return end
  if running then return end
  running = true
  pcall(vim.system, { "rg", "--no-heading", "--line-number", "--max-filesize", "1M", "--max-count", "50", "-e", PATTERN, cwd }, { text = true, timeout = 4000 }, function(res)
    vim.schedule(function()
      running = false
      local counts, top = {}, {}
      for line in (res.stdout or ""):gmatch("[^\n]+") do
        local file, lnum, text = line:match("^(.-):(%d+):(.*)$")
        local kw = text and text:match("(%u+)[%(:]")
        if file and kw and (kw == "TODO" or kw == "FIXME" or kw == "HACK" or kw == "BUG") then
          counts[kw] = (counts[kw] or 0) + 1
          if (kw == "FIXME" or kw == "BUG") and #top < 2 then
            top[#top + 1] = { kw = kw, file = file, lnum = tonumber(lnum), text = (text:gsub("^.-" .. kw .. "[^:]*:%s*", "")) }
          end
        end
      end
      cache = { cwd = cwd, counts = counts, top = top, at = os.time() }
      require("header_art.static").invalidate({ "todo" })
    end)
  end)
end

local function refresh()
  if pending then return end
  pending = vim.defer_fn(function() pending = nil; scan() end, 600)
end

return {
  id = "todo",
  title = "ATTENTION",
  badge = "7",
  on = { "BufWritePost", "DirChanged", "DiagnosticChanged" },
  available = function()
    if cache.cwd ~= vim.fn.getcwd() then scan() end
    return (vim.diagnostic.count()[1] or 0) + (vim.diagnostic.count()[2] or 0) > 0 or next(cache.counts) ~= nil
  end,
  render = function(w)
    if cache.cwd ~= vim.fn.getcwd() or os.time() - cache.at > 30 then refresh() end
    local c = vim.diagnostic.count()
    local e, wn = c[vim.diagnostic.severity.ERROR] or 0, c[vim.diagnostic.severity.WARN] or 0
    local out = { U.line({
      { "TODO ", "dim" }, { tostring(cache.counts.TODO or 0), "b" },
      { "   FIXME ", "dim" }, { tostring((cache.counts.FIXME or 0) + (cache.counts.BUG or 0)), (cache.counts.FIXME or 0) > 0 and "err" or "b" },
      { "   diagnostics ", "dim" }, { e .. "E", e > 0 and "err" or "ok" }, { " " .. wn .. "W", wn > 0 and "warn" or "dim" },
    }) }
    for _, t in ipairs(cache.top) do
      out[#out + 1] = U.row({ { t.kw .. " ", "err" }, { U.short_path(t.file, 2) .. ":" .. t.lnum, "mid" } }, { { t.text, "dim" } }, w, function() U.open_file(t.file, t.lnum) end)
    end
    return out
  end,
}
