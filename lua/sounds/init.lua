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
local dir = vim.fn.stdpath("config") .. "/sounds"

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
local last = {} -- cue -> uv.now() of its last play
local proc -- the running afplay (one at a time; a new cue cuts the old one)

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
  local path = ("%s/%s.wav"):format(dir, name)
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
function M.remote(name)
  M.emit("claude", name)
  return 0
end

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
  elseif sub == "test" then
    if not (arg and M.config.events[arg] ~= nil) then
      return vim.notify("Sounds test <" .. table.concat(order, "|") .. ">", vim.log.levels.WARN)
    end
    M.play(arg, true)
  else
    vim.notify("Sounds [on|off|toggle|test <cue>|demo]", vim.log.levels.WARN)
  end
end

function M.setup()
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
    desc = "Sound cues: on|off|toggle|test <cue>|demo",
    complete = function(_, line)
      local parts = vim.split(line, "%s+")
      if #parts <= 2 then return { "on", "off", "toggle", "test", "demo" } end
      if parts[2] == "test" then return order end
      return {}
    end,
  })
  vim.keymap.set("n", "<leader>uS", M.toggle, { desc = "Toggle sound cues" })
end

return M
