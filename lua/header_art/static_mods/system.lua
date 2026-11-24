-- Battery (pmset, async, every minute) and load average.
local U = require("header_art.static_util")
local uv = vim.uv or vim.loop

local bat, running, last_poll = nil, false, 0
local POLL_EVERY = 60 -- seconds between pmset runs

-- Never from render() unconditionally: the poll's callback re-renders this
-- module, so an unguarded poll in render() re-polled forever (~160 pmset
-- processes a second, found as a battery drain). The rate limit is the guard.
local function poll(force)
  if running or vim.fn.executable("pmset") == 0 then return end
  if not force and os.time() - last_poll < POLL_EVERY then return end
  last_poll = os.time()
  running = true
  pcall(vim.system, { "pmset", "-g", "batt" }, { text = true, timeout = 3000 }, function(res)
    vim.schedule(function()
      running = false
      local pct, state, left = (res.stdout or ""):match("(%d+)%%;%s*([%a ]-);%s*([%d:]+) remaining")
      if not pct then pct, state = (res.stdout or ""):match("(%d+)%%;%s*([%a ]-);") end
      bat = pct and { pct = tonumber(pct), state = state, left = left } or false
      require("header_art.static").invalidate({ "system" })
    end)
  end)
end

return {
  id = "system",
  title = "SYSTEM",
  every = 60,
  available = function()
    if bat == nil then poll(true) end
    return bat ~= false
  end,
  render = function(w)
    poll() -- rate limited: only the once-a-minute `every` tick gets past
    local l1, l2, l3 = uv.loadavg()
    local out = {}
    if bat then
      local full = math.floor(bat.pct / 10 + 0.5)
      out[#out + 1] = U.line({
        { "bat  ", "dim" }, { bat.pct .. "% ", "b" },
        { string.rep("▮", full), bat.pct < 20 and "err" or "ok" }, { string.rep("▯", 10 - full), "dim" },
        { bat.left and (" " .. bat.left) or (" " .. (bat.state or "")), "dim" },
      })
    end
    out[#out + 1] = U.line({ { "load ", "dim" }, { ("%.1f"):format(l1), "b" }, { ("  %.1f  %.1f"):format(l2, l3), "dim" } })
    return out
  end,
}
