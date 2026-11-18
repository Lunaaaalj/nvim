-- A long-lived sound player for the chatter cues (lua/sounds/chatter.lua).
--
-- `afplay` needs about 850 ms to exit even for an 8 ms file, so one process per
-- keystroke would pile up and lag behind typing. player.swift stays alive, keeps
-- every WAV decoded, and plays overlapping sounds. It is compiled once, on first
-- use, into stdpath("cache")/sounds/player (needs `swiftc`, from the Xcode
-- command line tools); until it is ready, sounds are dropped rather than queued.
-- It exits when its stdin closes, so it never outlives Neovim.
local M = {}

local uv = vim.uv
local src = vim.fn.stdpath("config") .. "/lua/sounds/player.swift"
local bin_dir = vim.fn.stdpath("cache") .. "/sounds"
local bin = bin_dir .. "/player"

local state = "idle" -- idle | building | starting | ready | failed
local job
local defs = {} -- train sets, resent whenever the helper (re)starts
local epoch = 0 -- bumped each time the helper becomes ready, so callers can tell it restarted

local function send(line)
  if job then return pcall(job.write, job, line .. "\n") end
  return false
end

local function send_defs()
  for name, d in pairs(defs) do
    send("trainset\t" .. name .. "\t" .. d.ntick .. "\t" .. table.concat(d.paths, "\t"))
  end
end

local function warn(msg)
  vim.schedule(function() vim.notify_once("Sounds: " .. msg, vim.log.levels.WARN, { title = "Sounds" }) end)
end

local function stale()
  local b, s = uv.fs_stat(bin), uv.fs_stat(src)
  return s ~= nil and (b == nil or b.mtime.sec < s.mtime.sec)
end

--- Build (if needed) and start the helper. Safe to call often.
function M.start()
  if state ~= "idle" then return end
  if #vim.api.nvim_list_uis() == 0 or vim.env.SSH_CONNECTION then return end
  if stale() then
    if vim.fn.executable("swiftc") ~= 1 then
      state = "failed"
      return warn("the chatter sounds need `swiftc` (xcode-select --install) to build their player")
    end
    state = "building"
    vim.fn.mkdir(bin_dir, "p")
    vim.schedule(function() vim.notify("Building the sound player (first use, a few seconds)…", vim.log.levels.INFO, { title = "Sounds" }) end)
    vim.system({ "swiftc", "-O", "-o", bin .. ".tmp", src }, { text = true }, vim.schedule_wrap(function(res)
      if res.code ~= 0 then
        state = "failed"
        return warn("building the player failed: " .. vim.trim((res.stderr or ""):sub(-300)))
      end
      uv.fs_rename(bin .. ".tmp", bin)
      state = "idle"
      M.start()
    end))
    return
  end
  state = "starting"
  local ok, handle = pcall(vim.system, { bin }, {
    stdin = true,
    text = true,
    stdout = function(_, data)
      if data and data:find("ready", 1, true) then
        state = "ready"
        vim.schedule(function()
          epoch = epoch + 1
          send_defs()
        end)
      end
    end,
    stderr = function(_, data)
      if data and data:match("%S") then warn(vim.trim(data)) end
    end,
  }, vim.schedule_wrap(function()
    job = nil
    if state ~= "failed" then state = "idle" end
  end))
  if ok then
    job = handle
  else
    state = "failed"
    warn("could not start the player: " .. tostring(handle))
  end
end

--- Play a WAV at `volume` (0..1). Returns false when the player isn't ready (the
--- sound is dropped; this also kicks off the build/start for next time).
function M.play(path, volume)
  if state ~= "ready" or not job then
    M.start()
    return false
  end
  local ok = pcall(job.write, job, ("play %.3f %s\n"):format(volume, path))
  return ok
end

--- Define a train set: the first `ntick` paths are ticks, the rest tocks (they alternate).
function M.define_set(name, ntick, paths)
  defs[name] = { ntick = ntick, paths = paths }
  if state == "ready" then
    send("trainset\t" .. name .. "\t" .. ntick .. "\t" .. table.concat(paths, "\t"))
  end
end

--- Start, or change, the train: `rate` ticks a second, `volume` 0..1, `jitter_ms` of
--- unevenness. The helper schedules the ticks itself, ahead on the audio clock.
--- Returns false when the helper is not ready (nothing is queued).
function M.train(set, rate, volume, jitter_ms)
  if state ~= "ready" or not job then
    M.start()
    return false
  end
  return send(("train %s %.3f %.3f %.2f"):format(set, rate, volume, jitter_ms or 0))
end

function M.train_stop() send("train_stop") end

--- Changes each time the helper restarts; a train started before that is gone.
function M.epoch() return epoch end

function M.status() return state end

function M.stop()
  if job then
    pcall(job.write, job, "quit\n")
    pcall(job.kill, job, 15)
    job = nil
  end
  if state ~= "failed" then state = "idle" end
end

return M
