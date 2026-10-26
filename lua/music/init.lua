-- Apple Music controller: Neovim never plays audio itself, it drives the Music
-- app through `applemusic.js` (JXA) and keeps a local copy of its state.
--
-- Polling is adaptive (fast only while playing with the player open) and the
-- position is interpolated between polls, so the statusline and progress bar
-- tick every second without an osascript per tick. Any visible change fires
-- `User MusicChanged`.
local M = {}

local HERE = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
local SCRIPT = HERE .. "/applemusic.js"

M.config = {
  -- poll intervals (ms)
  interval = {
    open = 1000, -- player float visible
    playing = 3000,
    paused = 5000,
    closed = 15000, -- Music not running
  },
  seek_step = 10, -- seconds, h / l
  volume_step = 5,
}

-- running: Music.app is up. track: { id, name, artist, album, duration }.
-- position is as of `stamp` (uv.now ms); use M.position() for the live value.
M.state = { running = false, playing = false, state = "stopped", position = 0, stamp = 0 }

local uv = vim.uv
local timer, inflight, denied
M.player_open = false

local changed = vim.schedule_wrap(function()
  vim.api.nvim_exec_autocmds("User", { pattern = "MusicChanged", modeline = false })
end)

-- Run a bridge command; `cb(decoded)` on the main loop, `always()` either way.
-- Errors are reported once per message, and a denied Automation permission
-- stops polling for good. The timeout matters: while macOS shows its
-- "wants to control Music" prompt, Apple Events block for up to 2 minutes.
local last_err
function M.run(args, cb, always, timeout)
  local cmd = { "osascript", "-l", "JavaScript", SCRIPT }
  vim.list_extend(cmd, args)
  vim.system(cmd, { text = true, timeout = timeout or 8000 }, vim.schedule_wrap(function(res)
    if always then always() end
    local ok, data = pcall(vim.json.decode, res.stdout or "")
    if not ok or type(data) ~= "table" then
      local err = vim.trim(res.stderr or "")
      if res.signal ~= 0 or res.code == 124 then err = "Music did not answer (permission prompt open?)" end
      data = { error = err ~= "" and err or "no output" }
    end
    if data.error then
      if data.number == -1743 then
        denied = true
        M.stop()
        vim.notify("Music: Automation permission denied for this terminal.\n"
          .. "Allow it in System Settings → Privacy & Security → Automation.", vim.log.levels.ERROR)
      elseif data.error ~= last_err then
        vim.notify("Music: " .. data.error, vim.log.levels.WARN)
      end
      last_err = data.error
      return
    end
    last_err = nil
    if cb then cb(data) end
  end))
end

-- Fold a poll result into M.state; notifies only when something visible changed.
local function apply(p)
  if p.running == nil then return end
  local s, old = M.state, vim.deepcopy(M.state)
  s.running = p.running
  s.state = p.state or "stopped"
  s.playing = s.state == "playing"
  s.volume = p.volume
  s.shuffle = p.shuffle
  s.rep = p["repeat"]
  s.track = p.track
  s.position = p.position or 0
  s.stamp = uv.now()
  local function id(t) return t and t.id end
  -- a jump the interpolation didn't predict: seeked from Music.app itself
  local predicted = old.position + (old.playing and (s.stamp - old.stamp) / 1000 or 0)
  local moved = math.abs(s.position - predicted) > 2
  if s.running ~= old.running or s.state ~= old.state or id(s.track) ~= id(old.track)
    or s.volume ~= old.volume or s.shuffle ~= old.shuffle or s.rep ~= old.rep or moved then
    changed()
  end
end

-- Live playback position in seconds, extrapolated from the last poll.
function M.position()
  local s = M.state
  local pos = s.position or 0
  if s.playing then pos = pos + (uv.now() - s.stamp) / 1000 end
  local dur = s.track and s.track.duration
  if dur and dur > 0 then pos = math.min(pos, dur) end
  return pos
end

local function interval()
  local i, s = M.config.interval, M.state
  if not s.running then return i.closed end
  if M.player_open then return i.open end
  return s.playing and i.playing or i.paused
end

local schedule
function M.poll()
  if inflight or denied then return end
  inflight = true
  M.run({ "poll" }, apply, function() inflight = false end)
  schedule()
end

-- One-shot timer re-armed after every poll, so the interval follows the state.
schedule = function()
  if denied then return end
  timer = timer or uv.new_timer()
  timer:stop()
  timer:start(interval(), 0, vim.schedule_wrap(M.poll))
end

function M.stop()
  if timer then timer:stop() end
end

-- Send a command and adopt the state it returns, so the UI reacts at once.
local function exec(args, timeout, done)
  M.run(args, function(p)
    apply(p)
    -- `play`/`next` answer mid-transition, before the new track exists
    if p.running and not p.track then vim.defer_fn(M.poll, 600) end
    schedule()
    if done then done() end
  end, nil, timeout)
end

local function command(...)
  exec({ ... })
end

local function require_running(fn)
  return function(...)
    if not M.state.running then
      vim.notify("Music is not running (<leader>Mo, then <Space> to launch)", vim.log.levels.INFO)
      return
    end
    return fn(...)
  end
end

-- Start Music.app in the background (no window), then poll until it answers.
function M.launch(then_cmd)
  vim.system({ "open", "-g", "-j", "-a", "Music" }, {}, vim.schedule_wrap(function()
    local tries = 0
    local function wait()
      tries = tries + 1
      M.run({ "poll" }, function(p)
        apply(p)
        if p.running then
          if then_cmd then command(then_cmd) end
          schedule()
        elseif tries < 20 then
          vim.defer_fn(wait, 500)
        end
      end)
    end
    wait()
  end))
end

function M.toggle()
  if not M.state.running then return M.launch("playpause") end
  -- optimistic flip so the icon changes before osascript returns
  M.state.position, M.state.stamp = M.position(), uv.now()
  M.state.playing = not M.state.playing
  changed()
  command("playpause")
end

M.next = require_running(function() command("next") end)
M.prev = require_running(function() command("prev") end)
M.shuffle = require_running(function() command("shuffle") end)
M.cycle_repeat = require_running(function() command("repeat") end)

-- Seek by `delta` seconds (relative), clamped to the track.
M.seek = require_running(function(delta)
  local pos = math.max(0, M.position() + delta)
  local dur = M.state.track and M.state.track.duration
  if dur and dur > 0 then pos = math.min(pos, dur - 1) end
  M.state.position, M.state.stamp = pos, uv.now()
  changed()
  command("seek", tostring(pos))
end)

M.volume = require_running(function(delta)
  local v = math.min(100, math.max(0, (M.state.volume or 50) + delta))
  M.state.volume = v
  changed()
  command("volume", tostring(v))
end)

-- Play a playlist (by persistent id, or "library"), optionally from a track.
function M.play(playlist, track)
  command("play", playlist, track)
end

-- The Neovim Queue playlist (applemusic.js): Music has no scriptable Up Next,
-- so albums, artists and queued songs are copied there and played from it.
-- Each song is a lookup in Music (~12 ms), so big fills get a long timeout.
local function queue_cmd(args, n, done)
  if n > 40 then vim.notify(("Music: queueing %d songs…"):format(n)) end
  exec(args, 10000 + n * 50, done)
end

-- Replace the queue with `ids` and play from the `start`th (1-based).
function M.queue_set(start, ids, done)
  local args = { "queue_set", tostring(start) }
  queue_cmd(vim.list_extend(args, ids), #ids, done)
end

-- Append `ids`; starts playing them when nothing is playing.
function M.queue_add(ids, done)
  queue_cmd(vim.list_extend({ "queue_add" }, ids), #ids, done)
end

-- Album art for track `id` as a PNG in the cache, or nil when it has none.
-- Exported once per track: raw data → .dat (a neutral name, since magick reads
-- `.raw` as a camera RAW) → 512px PNG stamped `-density 1`, so snacks shrinks
-- it to fit the window instead of sizing it by DPI.
--
-- At most ART_JOBS exports run at once (a grid of covers would otherwise start
-- one osascript per album); `urgent` (the now-playing card) jumps the line.
local art_dir = vim.fn.stdpath("cache") .. "/music"
local no_art, art_waiting = {}, {}
local ART_JOBS, art_running, art_pending = 3, 0, {}

local function art_next()
  while art_running < ART_JOBS and #art_pending > 0 do
    art_running = art_running + 1
    table.remove(art_pending, 1)()
  end
end

local function export(id, png, done)
  local dat = ("%s/%s.dat"):format(art_dir, id)
  local function finish(path)
    art_running = art_running - 1
    done(path)
    art_next()
  end
  vim.system({ "osascript", HERE .. "/artwork.applescript", id, dat }, { text = true, timeout = 8000 }, function(res)
    if vim.trim(res.stdout or "") ~= "ok" then return vim.schedule(function() finish(nil) end) end
    vim.system({ "magick", dat, "-resize", "512x512>", "-density", "1", png }, {}, vim.schedule_wrap(function(r)
      os.remove(dat)
      finish(r.code == 0 and png or nil)
    end))
  end)
end

function M.artwork(id, cb, urgent)
  local png = ("%s/%s.png"):format(art_dir, id)
  if uv.fs_stat(png) then return cb(png) end
  if no_art[id] or id == "stream" then return cb(nil) end
  if art_waiting[id] then return table.insert(art_waiting[id], cb) end
  art_waiting[id] = { cb }
  vim.fn.mkdir(art_dir, "p")
  local job = function()
    export(id, png, function(path)
      if not path then no_art[id] = true end
      local cbs = art_waiting[id]
      art_waiting[id] = nil
      for _, f in ipairs(cbs) do f(path) end
    end)
  end
  table.insert(art_pending, urgent and 1 or #art_pending + 1, job)
  art_next()
end

local function fmt_time(sec)
  sec = math.floor(sec or 0)
  return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end
M.fmt_time = fmt_time

-- Statusline text: "♪ Artist – Title 1:23". Empty when nothing is loaded.
-- Reads only cached state: lualine calls this on every redraw.
function M.statusline()
  local s = M.state
  if not s.running or not s.track then return "" end
  local t = s.track
  local label = t.artist ~= "" and (t.artist .. " – " .. t.name) or t.name
  local max = math.max(12, math.floor(vim.o.columns / 4))
  if vim.fn.strchars(label) > max then
    label = vim.fn.strcharpart(label, 0, max - 1) .. "…"
  end
  local icon = s.playing and "󰎈" or "󰏤"
  return ("%s %s %s"):format(icon, label, fmt_time(M.position()))
end

-- Theme-derived groups shared by the player, picker and statusline.
local function set_hl()
  local colors = require("defaults.colors")
  local acc = colors.accent()
  vim.api.nvim_set_hl(0, "MusicAccent", { fg = acc })
  vim.api.nvim_set_hl(0, "MusicTitle", { fg = acc, bold = true })
  vim.api.nvim_set_hl(0, "MusicMuted", { fg = colors.fg("Comment") })
  -- browser selection: a tint of the accent over whatever is behind the float
  local bg = vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false }).bg
    or vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
    or tonumber(colors.terminal_bg:sub(2), 16)
  vim.api.nvim_set_hl(0, "MusicSel", { bg = colors.blend(acc, bg, 0.22) })
  vim.api.nvim_set_hl(0, "MusicSelTitle", { fg = acc, bg = colors.blend(acc, bg, 0.22), bold = true })
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  local group = vim.api.nvim_create_augroup("music", { clear = true })
  set_hl()
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_hl })
  -- first poll off the startup path; FocusGained catches a Music launched
  -- while we sat on the slow "closed" interval
  vim.defer_fn(M.poll, 1500)
  vim.api.nvim_create_autocmd("FocusGained", { group = group, callback = function() M.poll() end })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MusicChanged",
    callback = function()
      local ok, lualine = pcall(require, "lualine")
      if ok then lualine.refresh({ place = { "statusline" } }) end
    end,
  })
end

return M
