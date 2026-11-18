-- Chatter: experimental sounds that fire often, on two switches, both OFF at the
-- start of every session and independent of `:Sounds` (lua/sounds/init.lua):
--
--   claude    <leader>uC   a sound as Claude's text arrives
--   terminal  <leader>ui   typing and output together:
--     input                a sound per key typed in a terminal (Enter has its own)
--     output               a sound as a shell command prints lines
--
-- `:Chatter input` / `:Chatter output` switch the two halves separately.
--
-- The WAVs (sounds/chatter/<cue>_<1..4>.wav, pitch variants picked at random) come
-- from lua/sounds/gen.py. They are played by lua/sounds/player.lua, a long-lived
-- helper, because `afplay` per keystroke would lag and pile up.
local M = {}

local uv = vim.uv
local player = require("sounds.player")
-- the working watch and the candidates exist only in the terminal set for now
local function dir() return require("sounds").root("terminal") .. "/chatter" end
local VARIANTS = 4

M.config = {
  volume = 1.0, -- multiplied with require("sounds").config.volume
  skip_claude_in_terminal = true, -- typing a prompt to Claude isn't "terminal input"
  claude = {
    mode = "chunk", -- "chunk": a sound per `chunk` new characters; "line": per new line
    chunk = 20,
    cap = 12, -- most sounds per second
    volume = 1.0,
    -- Lua patterns for screen lines that are not Claude's text (spinner, input box,
    -- status bar, rules). A line matching any of them never counts as new text.
    ignore = {
      "^[%s\226\148-\150\128-\191|%-=+_]*$", -- only box-drawing / rule characters
      "^%s*────", -- a rule with a label in it
      "^%s*[^%w%s]+ [%w%-]+… %(", -- the spinner: "· Mustering… (2m 21s · ↓ 17k tokens)"
      "esc to interrupt",
      "shift%+tab to cycle",
      "for shortcuts",
      "ctrl%+o to expand",
      "^%s*❯", -- the input box
      "Tip:",
    },
    -- The "working" sound: a mechanical watch ticking while Claude thinks or runs a
    -- command (the mockup's candidate J; the player ticks it by itself, precisely).
    -- It belongs to the Claude switch; `:Chatter working` turns just this part on or off.
    working = {
      enabled = true,
      rate = 6, -- ticks a second (the terminal watch; other presets set their own in library/catalog.json)
      delay = 0, -- seconds of working before it starts (so quick answers stay quiet)
      pause_text = true, -- pause while Claude's text is arriving (those ticks have their own sound)
      text_quiet_ms = 700, -- ...until no new text for this long
      low_for_commands = true, -- lower and slower while a Bash command runs (needs the hooks)
      jitter_ms = 1.2, -- a real movement is never perfectly even
      volume = 1.0,
      finished_sound = true, -- play claude_done when Claude stops, unless the Stop hook just did
    },
  },
  input = { cap = 25, enter_cap = 8, volume = 1.0 },
  output = { cap = 20, volume = 1.0 },
}

M.state = { claude = false, input = false, output = false } -- never persisted

local LABEL = { claude = "Claude talking", input = "Terminal input", output = "Terminal output", terminal = "Terminal" }

local last_play = {} -- cue -> uv.now()
local last_key = {} -- terminal buffer -> uv.now() of the last key typed in it
local last_char = {} -- ... of the last key that was not Enter

local function play(cue, feature, cap)
  local cfg = M.config[feature]
  local now = uv.now()
  if last_play[cue] and now - last_play[cue] < 1000 / (cap or cfg.cap) then return false end
  last_play[cue] = now
  local volume = (require("sounds").config.volume or 0.5) * M.config.volume * (cfg.volume or 1)
  return player.play(require("sounds").chatter_path(cue, math.random(VARIANTS)), math.min(1, volume))
end

--- A terminal buffer running Claude (claudecode's panel or a claude_chats buffer).
local function is_claude(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "terminal" then return false end
  if vim.b[buf].claude_chat or vim.bo[buf].filetype == "claudecode" then return true end
  -- term://cwd//pid:command args — only the program counts, not a path or argument
  local cmd = vim.api.nvim_buf_get_name(buf):match("//%d+:(.*)$")
  local exe = cmd and cmd:match("^%S+")
  return exe ~= nil and exe:match("([^/]+)$") == "claude"
end

-- ---------------------------------------------------------------------------
-- Claude talking: new text on Claude's terminal screen
--
-- Claude's chat is the screen of a full-screen app, so lines are rewritten in
-- place (the spinner every second, the input box on every key). Only text that
-- is genuinely new may count: a row that merely grows (`old` is a prefix of
-- `new`) adds the difference, a line already seen (it moved, or was redrawn)
-- adds nothing, and ignore patterns drop the UI chrome.

local function norm(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "))
end

local function skipped(text, ignore)
  for _, pat in ipairs(ignore) do
    local ok, hit = pcall(string.find, text, pat)
    if ok and hit then return true end
  end
  return false
end

--- Remember a line of text as seen (bounded: the 800 most recent distinct lines).
local function remember(st, text)
  if st.seen[text] then return end
  st.seen[text] = true
  st.queue[#st.queue + 1] = text
  if #st.queue > 800 then st.seen[table.remove(st.queue, 1)] = nil end
end

--- Compare the screen rows `first..` (0-based) with what was seen before.
--- Returns the number of characters of new text and the number of new lines.
--- `st` is { rows = {}, nrows = 0, seen = {}, queue = {} } and is updated.
function M.account(st, first, lines, ignore)
  local added, fresh = 0, 0
  for i, raw in ipairs(lines) do
    local row = first + i - 1
    local text = norm(raw)
    local old = st.rows[row]
    if text ~= old then
      if old == nil then st.nrows = st.nrows + 1 end
      st.rows[row] = text
      if text ~= "" and not skipped(text, ignore) then
        if old and old ~= "" and #text > #old and text:sub(1, #old) == old then
          added = added + (#text - #old) -- a line growing as text streams in
          st.seen[old] = nil -- only its latest form matters if the screen scrolls it away
          remember(st, text)
        elseif not st.seen[text] then
          added, fresh = added + #text, fresh + 1
          remember(st, text)
        end
      end
    end
  end
  if st.nrows > 4000 then st.rows, st.nrows = {}, 0 end
  return added, fresh
end

local function new_state() return { rows = {}, nrows = 0, seen = {}, queue = {}, acc = 0 } end

local cstate, cattached = {}, {} -- per Claude buffer

-- state of the "working" sound (see the section below)
local wk = { running = false, set = nil, epoch = -1, since = nil, ticked = false, idle = 0, cmd = 0, cmd_at = 0, last_text = 0, timer = nil }

local function process(buf, st)
  local first, last = st.first, st.last
  st.first, st.last = nil, nil
  if not first or not M.state.claude or not vim.api.nvim_buf_is_valid(buf) then return end
  last = math.min(last, vim.api.nvim_buf_line_count(buf))
  first = math.max(first, last - 120)
  local lines = vim.api.nvim_buf_get_lines(buf, first, last, false)
  local cfg = M.config.claude
  local added, fresh = M.account(st, first, lines, cfg.ignore)
  if uv.now() - (last_key[buf] or 0) < 400 then return end -- the user is typing: that is the echo
  if added > 0 then wk.last_text = uv.now() end -- new text: the working sound steps aside
  if cfg.mode == "line" then
    if fresh > 0 then play("claude_line", "claude") end
  else
    st.acc = st.acc + added
    if st.acc >= cfg.chunk then
      st.acc = st.acc % cfg.chunk
      play("claude_line", "claude")
    end
  end
end

--- Take what is on screen now as already seen, so only new text makes a sound.
local function prime(buf, st)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  M.account(st, 0, lines, M.config.claude.ignore)
  st.acc = 0
end

local function attach_claude(buf)
  if cattached[buf] or not is_claude(buf) then return end
  cattached[buf] = true
  local st = new_state()
  cstate[buf] = st
  prime(buf, st)
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, b, _, first, _, new_last)
      if not M.state.claude then return end
      st.first = math.min(st.first or first, first)
      st.last = math.max(st.last or new_last, new_last)
      if not st.pending then
        st.pending = true
        vim.defer_fn(function()
          st.pending = false
          process(b, st)
        end, 30)
      end
    end,
    on_detach = function()
      cattached[buf], cstate[buf] = nil, nil
    end,
  })
end

local function scan_claude()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if cstate[buf] then
      prime(buf, cstate[buf])
    else
      attach_claude(buf)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Claude working: a watch ticking while Claude thinks or runs a command
--
-- "Working" is read from the status bar, the last line with text on Claude's
-- screen: it says `esc to interrupt` for as long as Claude is busy (thinking,
-- running a tool, writing). It is not read from the transcript, which can quote
-- that phrase. The screen cannot tell thinking from running a command (the
-- spinner is the same), so the lower pitch for commands comes from Claude Code's
-- own PreToolUse / PostToolUse hooks for Bash, via sounds.remote() -> M.command().
-- The ticks themselves are run by the player (lua/sounds/player.swift), which
-- schedules them on the audio clock; this code only starts, changes and stops it.

local function define_sets()
  local wdir = require("sounds").working().dir
  wk.defined = require("sounds").preset
  local function files(prefix) -- three tick variants, then three tock variants
    local t = {}
    for _, beat in ipairs({ "tick", "tock" }) do
      for n = 1, 3 do t[#t + 1] = ("%s/%s_%s_%d.wav"):format(wdir, prefix, beat, n) end
    end
    return t
  end
  player.define_set("watch", 3, files("working"))
  player.define_set("watch_low", 3, files("working_low"))
end

--- True when the status bar of a Claude terminal says Claude is busy.
local function screen_working(buf)
  local n = vim.api.nvim_buf_line_count(buf)
  local rows = vim.api.nvim_buf_get_lines(buf, math.max(0, n - 12), n, false)
  for i = #rows, 1, -1 do
    local t = rows[i]:gsub("%s+$", "")
    if t ~= "" then return t:find("esc to interrupt", 1, true) ~= nil end
  end
  return false
end

local function stop_train()
  if wk.running then
    player.train_stop()
    wk.running = false
  end
end

local function volume_for(cfg)
  local base = (require("sounds").config.volume or 0.5) * M.config.volume * (M.config.claude.volume or 1)
  return math.min(1, base * (cfg and cfg.volume or 1))
end

--- Claude just stopped: end the "working" period, with the finished sound.
local function finished()
  local cfg = M.config.claude.working
  if cfg.finished_sound and wk.ticked then
    local last = require("sounds").last_played("claude_done")
    if not (last and uv.now() - last < 1500) then -- the Stop hook already played it
      player.play(require("sounds").path("claude_done"), volume_for())
    end
  end
  wk.since, wk.cmd, wk.ticked, wk.idle = nil, 0, false, 0
end

local function eval_working()
  local cfg = M.config.claude.working
  if not (M.state.claude and cfg.enabled) then
    stop_train()
    wk.since, wk.ticked = nil, false
    return
  end
  local now = uv.now()
  if wk.cmd > 0 and now - wk.cmd_at > 10 * 60 * 1000 then wk.cmd = 0 end -- a missed PostToolUse
  local active = false
  for buf in pairs(cstate) do
    if vim.api.nvim_buf_is_valid(buf) and screen_working(buf) then
      active = true
      break
    end
  end
  if not active then
    stop_train()
    if wk.since then -- two quiet looks in a row (400 ms), so a flicker does not end it
      wk.idle = wk.idle + 1
      if wk.idle >= 2 then finished() end
    end
    return
  end
  wk.idle = 0
  wk.since = wk.since or now
  local pausing = cfg.pause_text and wk.cmd == 0 and (now - wk.last_text) < cfg.text_quiet_ms
  if pausing or (now - wk.since) < cfg.delay * 1000 then
    stop_train()
    return
  end
  if wk.defined ~= require("sounds").preset then -- another preset: its own beats and tempo
    stop_train()
    define_sets()
  end
  local low = cfg.low_for_commands and wk.cmd > 0
  local set = low and "watch_low" or "watch"
  local w = require("sounds").working()
  local rate = (low and w.rate_low or w.rate) or cfg.rate
  if wk.running and wk.set == set and wk.epoch == player.epoch() and player.status() == "ready" then return end
  if player.train(set, rate, volume_for(cfg), cfg.jitter_ms) then
    wk.running, wk.set, wk.epoch, wk.ticked = true, set, player.epoch(), true
  end
end

local function start_working()
  define_sets()
  if wk.timer then return end
  wk.timer = uv.new_timer()
  wk.timer:start(200, 200, vim.schedule_wrap(eval_working))
end

local function stop_working()
  if wk.timer then
    wk.timer:stop()
    wk.timer:close()
    wk.timer = nil
  end
  stop_train()
  wk.since, wk.cmd, wk.ticked, wk.idle = nil, 0, false, 0
end

--- The working sound's state, for debugging: { running, set, commands, ticked }.
function M.working() return { running = wk.running, set = wk.set, commands = wk.cmd, ticked = wk.ticked } end

--- A Bash command started (true) or finished (false): from Claude Code's hooks.
function M.command(on)
  wk.cmd = on and wk.cmd + 1 or math.max(0, wk.cmd - 1)
  if on then wk.cmd_at = uv.now() end
  vim.schedule(eval_working) -- change the pitch at once, not at the next 200 ms look
end

-- ---------------------------------------------------------------------------
-- Terminal input: keys typed in terminal mode

local key_ns = vim.api.nvim_create_namespace("sounds_chatter_keys")
local BACKSPACE = vim.keycode("<BS>")

local function on_key(key, typed)
  if vim.api.nvim_get_mode().mode ~= "t" then return end
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "terminal" then return end
  local k = (typed ~= nil and typed ~= "") and typed or key
  local now = uv.now()
  last_key[buf] = now -- Claude: the prompt is echoed into the transcript after Enter
  -- Enter does not count for terminal output: a command's output starts right
  -- after it (`ls` prints in a few ms), and that is exactly what should sound.
  if k ~= "\r" then last_char[buf] = now end
  if not M.state.input then return end
  if M.config.skip_claude_in_terminal and is_claude(buf) then return end
  local byte = k:byte(1)
  if k == "\r" then
    play("term_enter", "input", M.config.input.enter_cap)
  elseif k == BACKSPACE or k == "\127" or k == "\8" or (byte and byte >= 32 and byte ~= 127 and byte ~= 128) then
    play("term_key", "input")
  end
end

-- ---------------------------------------------------------------------------
-- Terminal output: lines printed while a shell command runs (the zsh prompt
-- hooks of lua/terminals mark the start and end with OSC 133;C and 133;D)

local running, oattached = {}, {}
-- Neovim refreshes a terminal buffer ~10 ms after the output arrives, but the marks
-- are seen at once: `ls` can start, print and end before the first `on_lines`.
-- So lines are still accepted for a moment after the end mark.
local GRACE_MS = 120
local grace = {}

local function attach_output(buf)
  if oattached[buf] then return end
  oattached[buf] = true
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, b)
      if not M.state.output then return end
      if not (running[b] or (grace[b] and uv.now() < grace[b])) then return end
      if uv.now() - (last_char[b] or 0) < 50 then return end -- an echo of what was typed
      play("term_out", "output")
    end,
    on_detach = function()
      oattached[buf], running[buf], grace[buf] = nil, nil, nil
    end,
  })
end

local function on_term_request(ev)
  local seq = type(ev.data) == "table" and ev.data.sequence or ev.data or ""
  if seq:find("^\27%]133;C") then
    running[ev.buf], grace[ev.buf] = true, nil
    if M.state.output and not is_claude(ev.buf) then attach_output(ev.buf) end
  elseif seq:find("^\27%]133;D") then
    running[ev.buf] = nil
    grace[ev.buf] = uv.now() + GRACE_MS
  end
end

-- ---------------------------------------------------------------------------
-- Switches

local function any_on() return M.state.claude or M.state.input or M.state.output end

local keys_hooked = false
local function sync_hooks()
  if any_on() and not keys_hooked then
    vim.on_key(on_key, key_ns)
    keys_hooked = true
  elseif not any_on() and keys_hooked then
    vim.on_key(nil, key_ns)
    keys_hooked = false
  end
  if not any_on() then player.stop() end
end

local function set_one(feature, on)
  M.state[feature] = on and true or false
  if M.state[feature] then player.start() end
  if feature == "claude" then
    if M.state.claude then
      scan_claude()
      start_working()
    else
      stop_working()
    end
  end
end

--- Switch a feature: "claude", "input", "output", or "terminal" (input + output).
function M.set(feature, on, silent)
  if feature == "terminal" then
    set_one("input", on)
    set_one("output", on)
    on = M.state.input
  else
    set_one(feature, on)
    on = M.state[feature]
  end
  sync_hooks()
  if silent then return end
  vim.notify(LABEL[feature] .. " sounds " .. (on and "on" or "off"), vim.log.levels.INFO, { title = "Sounds" })
end

function M.toggle(feature)
  if feature == "terminal" then
    -- on unless both halves are already on (so a half-on state turns fully on)
    M.set("terminal", not (M.state.input and M.state.output))
  else
    M.set(feature, not M.state[feature])
  end
end

local CUES = { "claude_line", "claude_para", "term_key", "term_enter", "term_out" }
local CUE_FEATURE = { claude_line = "claude", claude_para = "claude", term_key = "input", term_enter = "input", term_out = "output" }

local function command(opts)
  local a, b = opts.fargs[1], opts.fargs[2]
  if a == "test" then
    if not (b and CUE_FEATURE[b]) then return vim.notify("Chatter test <" .. table.concat(CUES, "|") .. "> [A-F]", vim.log.levels.WARN) end
    player.start()
    local letter = opts.fargs[3]
    local ok
    if letter then
      -- audition any of the six candidates of a cue through the real player
      local path = ("%s/candidates/%s_%s.wav"):format(dir(), b, letter:upper())
      local cfg = M.config[CUE_FEATURE[b]]
      local vol = (require("sounds").config.volume or 0.5) * M.config.volume * (cfg.volume or 1)
      ok = uv.fs_stat(path) ~= nil and player.play(path, math.min(1, vol))
    else
      last_play[b] = nil
      ok = play(b, CUE_FEATURE[b], 1000)
    end
    if not ok then vim.notify("Not played: the sound player is still starting (try again), or there is no such candidate.", vim.log.levels.INFO, { title = "Sounds" }) end
    return
  end
  if a == "working" then
    local w = M.config.claude.working
    if b == "on" then w.enabled = true elseif b == "off" then w.enabled = false else w.enabled = not w.enabled end
    if not w.enabled then stop_train() end
    return vim.notify("Claude working sound " .. (w.enabled and "on" or "off") .. (M.state.claude and "" or " (the Claude switch is off)"), vim.log.levels.INFO, { title = "Sounds" })
  end
  local feature = ({ claude = "claude", terminal = "terminal", input = "input", output = "output" })[a or ""]
  local targets = a == "all" and { "claude", "terminal" } or (feature and { feature })
  if not targets then
    return vim.notify("Chatter {claude|terminal|input|output|all} [on|off|toggle] | test {cue} [A-F]", vim.log.levels.WARN)
  end
  for _, f in ipairs(targets) do
    if b == "on" then M.set(f, true)
    elseif b == "off" then M.set(f, false)
    else M.toggle(f) end
  end
end

function M.setup()
  math.randomseed(uv.hrtime() % 2147483647)
  local group = vim.api.nvim_create_augroup("SoundsChatter", { clear = true })
  vim.on_key(nil, key_ns)
  keys_hooked = false
  vim.api.nvim_create_autocmd("TermRequest", { group = group, callback = on_term_request })
  vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter" }, {
    group = group,
    callback = function(ev)
      if not M.state.claude or vim.bo[ev.buf].buftype ~= "terminal" then return end
      -- the buffer's name and filetype are set a moment after TermOpen
      vim.defer_fn(function() attach_claude(ev.buf) end, 100)
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = function() player.stop() end })

  vim.api.nvim_create_user_command("Chatter", command, {
    nargs = "*",
    desc = "Chatter sounds: {claude|terminal|input|output|all} [on|off|toggle] | test {cue} [A-F]",
    complete = function(_, line)
      local parts = vim.split(line, "%s+")
      if #parts <= 2 then return { "claude", "working", "terminal", "input", "output", "all", "test" } end
      if parts[2] == "test" then
        if #parts <= 3 then return CUES end
        return { "A", "B", "C", "D", "E", "F" }
      end
      return { "on", "off", "toggle" }
    end,
  })
end

return M
