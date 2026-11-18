-- Sound cues for editor events (save, git, Claude, compile, tests, debugger…).
--
-- Neovim has no audio: cues are WAVs in `sounds/` (synthesized by
-- lua/sounds/gen.py) played through macOS `afplay`. Opt-in per session:
-- `enabled` starts false and is never persisted. See `:help nvim-config-sounds`.
--
-- Two switches per sound: `config.events[cue]` (a cue off everywhere) and
-- `config.sources[source]` (a source off, whatever cue it would play).
local M = {}

local uv = vim.uv
local base = vim.fn.stdpath("config") .. "/sounds"
local state_file = vim.fn.stdpath("state") .. "/sounds.json"

-- A preset is a style of sounds for every event. Seven families live in a shared library
-- (`sounds/library/<family>/`: `<cue>.wav`, `chatter/<cue>_<1..4>.wav`, and for four of them
-- the working-watch beats; `library/catalog.json` names everything, all written by gen.py),
-- and a library preset is just "play this family for every cue", with per-cue overrides from
-- the menu (any family can play any cue). "terminal" is the original sci-fi set and lives in
-- `sounds/` itself, with its own letters A/B/C per cue (`sounds/catalog.json`).
-- To add a preset, add a family to gen.py's LIBRARY and a line here.
M.library = base .. "/library"
M.presets = {
  cupertino = { label = "Cupertino", desc = "soft, rounded, Apple-like: a timbre per job", family = "cupertino" },
  mission_control = { label = "Mission Control", desc = "radio comms: key-up tones, squelch, telemetry", family = "mission_control" },
  sonar = { label = "Sonar", desc = "dark pings, and the echoes carry the meaning", family = "sonar" },
  whisper = { label = "Whisper", desc = "haptic thumps, ticks and breaths", family = "whisper" },
  ledger = { label = "Ledger", desc = "pure sines, a soft decay: calm and neutral", family = "ledger" },
  muted_keys = { label = "Muted keys", desc = "a softly struck, damped tine: warmer", family = "muted_keys" },
  advisory = { label = "Advisory", desc = "flat gated tones, like an instrument panel", family = "advisory" },
  terminal = { label = "Terminal", desc = "gated beeps and low pulses, a sci-fi computer" },
}
M.preset_order = { "cupertino", "mission_control", "sonar", "whisper", "ledger", "muted_keys", "advisory", "terminal" }
M.preset = "cupertino" -- the default; a saved choice (sounds.json) wins
M.picks = {} -- preset -> { cue = family | letter } overrides of the preset's own pick

M.config = {
  volume = 0.5, -- afplay -v, 0..1
  events = { -- per-cue switches
    save = true,
    commit = true,
    pull = true,
    push = true,
    checkout = true,
    claude_start = true,
    claude_done = true,
    claude_input = true,
    breakpoint = true,
    ok = true,
    fail = true,
  },
  sources = { -- per-source switches (who asked for a cue)
    save = true, -- BufWritePost
    git = true, -- reflog: commit / pull / push / checkout
    git_fail = true, -- a git command that exited non-zero in a terminal
    compile = true, -- VimTeX
    terminal = true, -- a terminal command that ran >= notify_after
    tests = true, -- neotest runs
    debug = true, -- nvim-dap stops and exits
    upstream = true, -- GitHub float writes
    claude = true, -- Claude Code hooks
  },
  min_gap = { save = 1500, claude_start = 800, default = 300 }, -- ms between two plays of one cue
}

M.enabled = false

local order = {
  "save", "commit", "pull", "push", "checkout",
  "claude_start", "claude_done", "claude_input", "breakpoint",
  "ok", "fail",
}
M.order = order

-- What the menu shows for each cue: its text and the source that plays it.
M.info = {
  save = { "Save", "a file is written", "save" },
  commit = { "Commit", "git commit (reflog)", "git" },
  pull = { "Pull", "pull / merge / rebase finished", "git" },
  push = { "Push", "git push", "git" },
  checkout = { "Checkout", "branch switch", "git" },
  claude_start = { "Claude starts", "you sent a prompt", "claude" },
  claude_done = { "Claude done", "Claude stopped", "claude" },
  claude_input = { "Claude asks", "Claude needs you", "claude" },
  breakpoint = { "Breakpoint", "the debugger stopped", "debug" },
  ok = { "Success", "compile / command / tests / exit 0", "compile" },
  fail = { "Failure", "compile / command / tests failed", "compile" },
}
local last = {} -- cue -> uv.now() of its last play
local proc -- the running afplay (one at a time; a new cue cuts the old one)

local catalogs = {}

local function is_library(preset) return M.presets[preset or M.preset].family ~= nil end

--- The catalog in use. Library presets: `{ families = {{key, label}}, events = {cue = {family = name}},
--- chatter = {...}, working = {family = {name, rate, rate_low}} }`; terminal: `{ events = {cue = {letter = name}},
--- picks, chatter, chatter_picks }`.
function M.catalog(preset)
  local which = is_library(preset) and "library" or "terminal"
  if catalogs[which] == nil then
    local f = io.open((which == "library" and M.library or base) .. "/catalog.json")
    local ok, data = false, nil
    if f then
      ok, data = pcall(vim.json.decode, f:read("*a"))
      f:close()
    end
    catalogs[which] = ok and data or false
  end
  return catalogs[which] or { families = {}, events = {}, chatter = {}, working = {}, picks = {}, chatter_picks = {} }
end

--- Folder holding the sounds of `preset`'s own family (terminal: `sounds/`).
function M.root(preset)
  local p = M.presets[preset or M.preset]
  return p.family and (M.library .. "/" .. p.family) or base
end

--- What the preset plays for `cue` unless overridden: a family key (library) or a letter (terminal).
function M.default_letter(cue)
  local p = M.presets[M.preset]
  if p.family then return p.family end
  local cat = M.catalog()
  return cat.picks[cue] or cat.chatter_picks[cue]
end

--- The choices for `cue`: `{ { key, label, name } }` (families for library presets, letters for terminal).
function M.options(cue)
  local cat = M.catalog()
  local out = {}
  if is_library() then
    local names = cat.events[cue] or cat.chatter[cue] or {}
    for _, fam in ipairs(cat.families) do
      if names[fam.key] then out[#out + 1] = { key = fam.key, label = fam.label, name = names[fam.key] } end
    end
  else
    local names = cat.events[cue] or cat.chatter[cue] or {}
    for letter, name in pairs(names) do out[#out + 1] = { key = letter, label = letter, name = name } end
    table.sort(out, function(a, b) return a.key < b.key end)
  end
  return out
end

--- Key in use for `cue` (an event or a chatter cue): the user's choice, else the preset's.
function M.letter(cue)
  local mine = M.picks[M.preset] and M.picks[M.preset][cue]
  if mine then
    for _, o in ipairs(M.options(cue)) do
      if o.key == mine then return mine end
    end
  end
  return M.default_letter(cue)
end

local function overridden(cue) return M.letter(cue) ~= M.default_letter(cue) end

--- "Cupertino · Tink" (library) or "B Pulse triple" (terminal): what the menu shows for a cue.
function M.describe(cue)
  for _, o in ipairs(M.options(cue)) do
    if o.key == M.letter(cue) then
      return is_library() and (o.label .. " · " .. o.name) or (o.key .. " " .. o.name)
    end
  end
  return ""
end

--- WAV of an event in the active preset.
function M.path(name)
  if is_library() then return ("%s/%s/%s.wav"):format(M.library, M.letter(name), name) end
  if overridden(name) then return ("%s/candidates/%s_%s.wav"):format(base, name, M.letter(name)) end
  return ("%s/%s.wav"):format(base, name)
end

--- WAV of a chatter cue, pitch variant `n` (1..4).
function M.chatter_path(cue, n)
  if is_library() then return ("%s/%s/chatter/%s_%d.wav"):format(M.library, M.letter(cue), cue, n) end
  if overridden(cue) then return ("%s/chatter/alt/%s_%s_%d.wav"):format(base, cue, M.letter(cue), n) end
  return ("%s/chatter/%s_%d.wav"):format(base, cue, n)
end

--- The working watch of the active preset: `{ dir = <chatter folder>, rate, rate_low }`. Families
--- without their own beats (and terminal) use the terminal watch (rate nil = the config's).
function M.working()
  local p = M.presets[M.preset]
  if p.family then
    local w = M.catalog().working[p.family]
    if w then return { dir = ("%s/%s/chatter"):format(M.library, p.family), rate = w.rate, rate_low = w.rate_low } end
  end
  return { dir = base .. "/chatter" }
end

local function save_state()
  local out = { preset = M.preset, volume = M.config.volume, events = M.config.events, picks = M.picks }
  local f = io.open(state_file, "w")
  if not f then return end
  f:write(vim.json.encode(out))
  f:close()
end
M.save = save_state

local function load_state()
  local f = io.open(state_file)
  if not f then return end
  local ok, data = pcall(vim.json.decode, f:read("*a"))
  f:close()
  if not ok or type(data) ~= "table" then return end
  if data.preset and M.presets[data.preset] then M.preset = data.preset end
  if type(data.volume) == "number" then M.config.volume = math.max(0, math.min(1, data.volume)) end
  for k, v in pairs(type(data.events) == "table" and data.events or {}) do
    if M.config.events[k] ~= nil and type(v) == "boolean" then M.config.events[k] = v end
  end
  if type(data.picks) == "table" then M.picks = data.picks end
end

--- Change the preset (persisted).
function M.set_preset(name)
  if not M.presets[name] then return end
  M.preset = name
  save_state()
end

--- Use letter `letter` for `cue` in the active preset (persisted); nil = the preset's own pick.
function M.set_letter(cue, letter)
  M.picks[M.preset] = M.picks[M.preset] or {}
  M.picks[M.preset][cue] = letter
  save_state()
end

function M.set_event(cue, on)
  M.config.events[cue] = on and true or false
  save_state()
end

function M.set_volume(v)
  M.config.volume = math.max(0, math.min(1, v))
  save_state()
end

local function can_play()
  if #vim.api.nvim_list_uis() == 0 then return false end -- headless
  if vim.env.SSH_CONNECTION then return false end
  return vim.fn.executable("afplay") == 1
end

--- Play a cue. `force` skips the enabled/event/gap checks (tests, demo).
function M.play(name, force)
  if not force then
    if not M.enabled or not M.config.events[name] then return end
    local gap = M.config.min_gap[name] or M.config.min_gap.default
    local now = uv.now()
    if last[name] and now - last[name] < gap then return end
    last[name] = now
  end
  local path = M.path(name)
  if not can_play() or uv.fs_stat(path) == nil then return end
  if proc then pcall(proc.kill, proc, 15) end
  proc = vim.system({ "afplay", "-v", ("%.2f"):format(M.config.volume), path }, {}, function()
    proc = nil
  end)
end

--- Play `name` on behalf of `source` (skipped when that source is switched off).
function M.emit(source, name)
  if M.config.sources[source] == false then return end
  M.play(name)
end

--- Entry point for `nvim --remote-expr` (Claude Code hooks): always returns a value.
--- `claude_cmd_start` / `claude_cmd_end` (PreToolUse / PostToolUse for Bash) are not
--- cues: they tell the chatter "working" sound that a command is running.
function M.remote(name)
  if name == "claude_cmd_start" or name == "claude_cmd_end" then
    local ok, chatter = pcall(require, "sounds.chatter")
    if ok then chatter.command(name == "claude_cmd_start") end
    return 0
  end
  M.emit("claude", name)
  return 0
end

--- uv.now() of the last time `name` was played through play(), or nil.
function M.last_played(name) return last[name] end

-- git subcommands whose failure is worth a sound. Not `diff`/`grep`/`status`…:
-- those exit 1 for answers, not errors.
local git_writes = {}
for _, s in ipairs({
  "commit", "push", "pull", "merge", "rebase", "checkout", "switch", "fetch", "cherry-pick",
  "revert", "stash", "add", "clone", "tag", "branch", "reset", "restore", "am", "apply", "bisect",
}) do
  git_writes[s] = true
end
-- options that take a separate argument: `git -C dir push`, `git -c k=v commit`
local git_opt_arg = { ["-C"] = true, ["-c"] = true, ["--git-dir"] = true, ["--work-tree"] = true }

--- True when `cmd` (a shell command line) starts with a git command that changes things.
function M.is_git_write(cmd)
  if type(cmd) ~= "string" then return false end
  local toks = vim.split(vim.trim(cmd), "%s+")
  if toks[1] ~= "git" then return false end
  local i = 2
  while toks[i] do
    local t = toks[i]
    if git_opt_arg[t] then
      i = i + 2
    elseif t:sub(1, 1) == "-" then
      i = i + 1
    else
      return git_writes[t] == true
    end
  end
  return false
end

function M.set(on)
  M.enabled = on and true or false
  if M.enabled then
    require("sounds.git").start()
    M.play("ok", true)
  else
    require("sounds.git").stop()
    if proc then pcall(proc.kill, proc, 15) end
  end
  vim.notify("Sounds " .. (M.enabled and "on" or "off"), vim.log.levels.INFO, { title = "Sounds" })
end

function M.toggle() M.set(not M.enabled) end

--- Every cue in turn, 700 ms apart (for tuning gen.py by ear).
function M.demo()
  for i, name in ipairs(order) do
    vim.defer_fn(function()
      vim.notify(name, vim.log.levels.INFO, { title = "Sounds demo" })
      M.play(name, true)
    end, (i - 1) * 700)
  end
end

local function command(opts)
  local sub, arg = opts.fargs[1] or "toggle", opts.fargs[2]
  if sub == "on" then M.set(true)
  elseif sub == "off" then M.set(false)
  elseif sub == "toggle" then M.toggle()
  elseif sub == "demo" then M.demo()
  elseif sub == "menu" then require("sounds.menu").open()
  elseif sub == "test" then
    if not (arg and M.config.events[arg] ~= nil) then
      return vim.notify("Sounds test <" .. table.concat(order, "|") .. ">", vim.log.levels.WARN)
    end
    M.play(arg, true)
  else
    vim.notify("Sounds [on|off|toggle|menu|test <cue>|demo]", vim.log.levels.WARN)
  end
end

function M.setup()
  load_state() -- cue switches, volume, preset and chosen sounds persist; `enabled` never does
  local group = vim.api.nvim_create_augroup("Sounds", { clear = true })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function() M.emit("save", "save") end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "VimtexEventCompileSuccess",
    callback = function() M.emit("compile", "ok") end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "VimtexEventCompileFailed",
    callback = function() M.emit("compile", "fail") end,
  })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      if M.enabled then require("sounds.git").start() end
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function() require("sounds.git").stop() end,
  })

  vim.api.nvim_create_user_command("Sounds", command, {
    nargs = "*",
    desc = "Sound cues: on|off|toggle|menu|test <cue>|demo",
    complete = function(_, line)
      local parts = vim.split(line, "%s+")
      if #parts <= 2 then return { "on", "off", "toggle", "menu", "test", "demo" } end
      if parts[2] == "test" then return order end
      return {}
    end,
  })
  vim.keymap.set("n", "<leader>uS", function() require("sounds.menu").open() end, { desc = "Sounds menu" })
  vim.api.nvim_create_user_command("SoundsMenu", function() require("sounds.menu").open() end, { desc = "Sounds menu" })

  -- The experimental chatter sounds (Claude talking, terminal input / output) have
  -- their own switches and are not controlled by `enabled` above.
  require("sounds.chatter").setup()
end

return M
