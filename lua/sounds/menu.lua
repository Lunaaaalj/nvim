-- The sounds menu (<leader>uS / :SoundsMenu): one float for everything that used to
-- have its own key. From it you can
--   * switch sounds on or off for this session (the master switch),
--   * turn each event cue on or off and change which sound it plays,
--   * switch the chatter sounds (Claude talking, terminal keys / Enter / output,
--     the working watch), which stay session-only like the master switch,
--   * change the preset (a whole style of sounds) and the volume.
--
-- Cue switches, chosen sounds, volume and preset persist (stdpath("state")/sounds.json,
-- see lua/sounds/init.lua); `enabled` and the chatter switches never do.
local sounds = require("sounds")
local colors = require("defaults.colors")

local M = {}

local ns = vim.api.nvim_create_namespace("sounds_menu")
local W = 92
local ui = {} -- { buf, win, items = { [line] = item }, order = { lines of items } }

local function chatter() return require("sounds.chatter") end

--- Rows of the Chatter section: label, hint, the switch it flips, and its sound's cue.
local CHATTER_ROWS = {
  { id = "claude", label = "Claude talking", hint = "a tick as Claude's text arrives", cue = "claude_line", feature = "claude" },
  { id = "input", label = "Terminal keys", hint = "a tick per key typed", cue = "term_key", feature = "input" },
  { id = "enter", label = "Terminal Enter", hint = "(shares the keys switch)", cue = "term_enter", feature = "input" },
  { id = "output", label = "Terminal output", hint = "a tick per output line of a command", cue = "term_out", feature = "output" },
  { id = "working", label = "Working watch", hint = "a ticking watch while Claude works", feature = "working" },
}

local function working_on() return chatter().config.claude.working.enabled end

local function chatter_on(row)
  if row.feature == "working" then return working_on() end
  return chatter().state[row.feature]
end

local function set_hl()
  local acc = colors.accent()
  local bg = vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false }).bg
    or vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
    or tonumber(colors.terminal_bg:sub(2), 16)
  vim.api.nvim_set_hl(0, "SoundsAccent", { fg = acc })
  vim.api.nvim_set_hl(0, "SoundsTitle", { fg = acc, bold = true })
  vim.api.nvim_set_hl(0, "SoundsMuted", { fg = colors.fg("Comment") })
  vim.api.nvim_set_hl(0, "SoundsSel", { bg = colors.blend(acc, bg, 0.22) })
end

local function valid() return ui.win and vim.api.nvim_win_is_valid(ui.win) end

local function pad(text, w)
  local len = vim.fn.strdisplaywidth(text)
  if len >= w then return vim.fn.strcharpart(text, 0, math.max(0, w - 1)) .. (len > w and "…" or "") end
  return text .. (" "):rep(w - len)
end

-- ---------------------------------------------------------------------------
-- Content

--- Name of the sound `cue` plays ("Cupertino · Tink"), starred when it is not the preset's own.
local function sound_name(cue)
  local text = sounds.describe(cue)
  if text == "" then return "" end
  return text .. (sounds.letter(cue) ~= sounds.default_letter(cue) and " *" or "")
end

local function build()
  local rows, items = {}, {}
  local function add(segs, item)
    rows[#rows + 1] = segs
    if item then items[#rows] = item end
  end
  local function heading(text)
    add({ { "" } })
    add({ { " " .. text, "SoundsTitle" } })
  end
  local box = function(on) return on and "󰄲 " or "󰄱 " end

  local p = sounds.presets[sounds.preset]
  local vol = math.floor(sounds.config.volume * 10 + 0.5)
  add({
    { " Sounds ", "SoundsTitle" },
    { sounds.enabled and "󰝚 on " or "󰝛 off", sounds.enabled and "SoundsAccent" or "SoundsMuted" },
    { "   volume " },
    { ("▮"):rep(vol), "SoundsAccent" },
    { ("▯"):rep(10 - vol), "SoundsMuted" },
    { (" %d%%"):format(math.floor(sounds.config.volume * 100 + 0.5)), "SoundsMuted" },
  }, { kind = "master" })
  add({
    { " Preset " , "SoundsMuted" },
    { p.label, "SoundsAccent" },
    { "  " .. p.desc, "SoundsMuted" },
  }, { kind = "preset" })

  heading("Events")
  for _, cue in ipairs(sounds.order) do
    local info = sounds.info[cue]
    local on = sounds.config.events[cue]
    add({
      { " " .. box(on), on and "SoundsAccent" or "SoundsMuted" },
      { pad(info[1], 17), on and nil or "SoundsMuted" },
      { pad(sound_name(cue), 34), "SoundsAccent" },
      { info[2], "SoundsMuted" },
    }, { kind = "event", cue = cue })
  end

  heading("Chatter · off every session")
  for _, r in ipairs(CHATTER_ROWS) do
    local on = chatter_on(r)
    add({
      { " " .. box(on), on and "SoundsAccent" or "SoundsMuted" },
      { pad(r.label, 17), on and nil or "SoundsMuted" },
      { pad(r.cue and sound_name(r.cue) or "", 34), "SoundsAccent" },
      { r.hint, "SoundsMuted" },
    }, { kind = "chatter", row = r })
  end
  return rows, items
end

local function render()
  if not valid() then return end
  local rows, items = build()
  local lines, marks = {}, {}
  for i, segs in ipairs(rows) do
    local line = ""
    for _, seg in ipairs(segs) do
      local start = #line
      line = line .. seg[1]
      if seg[2] then marks[#marks + 1] = { i - 1, start, #line, seg[2] } end
    end
    lines[i] = line
  end
  vim.bo[ui.buf].modifiable = true
  vim.api.nvim_buf_set_lines(ui.buf, 0, -1, false, lines)
  vim.bo[ui.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(ui.buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(ui.buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
  ui.items = items
  ui.order = {}
  for l in pairs(items) do ui.order[#ui.order + 1] = l end
  table.sort(ui.order)
  vim.api.nvim_win_set_config(ui.win, { height = #lines })
end

-- ---------------------------------------------------------------------------
-- Actions

local function current()
  if not valid() then return end
  local line = vim.api.nvim_win_get_cursor(ui.win)[1]
  return ui.items[line], line
end

local function refresh()
  local _, line = current()
  render()
  if line and valid() then pcall(vim.api.nvim_win_set_cursor, ui.win, { line, 0 }) end
end

--- Move to the next / previous row that does something (headings are skipped).
local function move(dir)
  local _, line = current()
  local target
  if dir > 0 then
    for _, l in ipairs(ui.order) do if l > line then target = l break end end
  else
    for i = #ui.order, 1, -1 do if ui.order[i] < line then target = ui.order[i] break end end
  end
  if target then vim.api.nvim_win_set_cursor(ui.win, { target, 0 }) end
end

local function play_item(item)
  if item.kind == "event" then
    sounds.play(item.cue, true)
  elseif item.kind == "chatter" and item.row.cue then
    local player = require("sounds.player")
    player.start()
    local vol = math.min(1, (sounds.config.volume or 0.5) * chatter().config.volume)
    if not player.play(sounds.chatter_path(item.row.cue, 2), vol) then
      vim.notify("The sound player is still starting; try again.", vim.log.levels.INFO, { title = "Sounds" })
    end
  elseif item.kind == "master" or item.kind == "preset" then
    sounds.play("ok", true)
  end
end

local function toggle(item)
  if item.kind == "master" then
    sounds.toggle()
  elseif item.kind == "event" then
    sounds.set_event(item.cue, not sounds.config.events[item.cue])
  elseif item.kind == "chatter" then
    local r = item.row
    if r.feature == "working" then
      vim.cmd("Chatter working toggle")
    else
      chatter().set(r.feature, not chatter().state[r.feature], true)
    end
  elseif item.kind == "preset" then
    return M.cycle_preset(1)
  end
  refresh()
end

function M.cycle_preset(d)
  local order = sounds.preset_order
  local idx = 1
  for i, name in ipairs(order) do if name == sounds.preset then idx = i end end
  sounds.set_preset(order[(idx - 1 + d) % #order + 1])
  refresh()
  sounds.play("ok", true)
end

--- Pick which sound a cue plays (any family of the library, or the terminal's letters); it plays after.
local function choose(item)
  local cue, label
  if item.kind == "event" then
    cue, label = item.cue, sounds.info[item.cue][1]
  elseif item.kind == "chatter" and item.row.cue then
    cue, label = item.row.cue, item.row.label
  else
    return
  end
  local options = sounds.options(cue)
  if #options == 0 then return end
  local own, current = sounds.default_letter(cue), sounds.letter(cue)
  vim.ui.select(options, {
    prompt = "Sound for " .. label,
    format_item = function(o)
      return ("%s  %s%s%s"):format(o.label, o.name, o.key == own and "  (preset)" or "", o.key == current and "  ●" or "")
    end,
  }, function(o)
    if not o then return end
    sounds.set_letter(cue, o.key ~= own and o.key or nil)
    refresh()
    play_item(item)
  end)
end

local function reset(item)
  local cue = item.cue or (item.row and item.row.cue)
  if not cue then return end
  sounds.set_letter(cue, nil)
  refresh()
  play_item(item)
end

local function volume(d)
  sounds.set_volume(sounds.config.volume + d * 0.1)
  refresh()
  sounds.play("ok", true)
end

function M.close()
  if valid() then vim.api.nvim_win_close(ui.win, true) end
  ui.win = nil
end

function M.open()
  if valid() then return vim.api.nvim_set_current_win(ui.win) end
  set_hl()
  ui.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[ui.buf].bufhidden = "wipe"
  vim.bo[ui.buf].filetype = "soundmenu"
  local h = 24
  local w = math.min(W, vim.o.columns - 4)
  ui.win = vim.api.nvim_open_win(ui.buf, true, {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - h) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - w) / 2)),
    width = w,
    height = h,
    style = "minimal",
    border = "rounded",
    title = " 󰎈 Sounds ",
    title_pos = "center",
    footer = { { " ⏎ switch · s sound · r reset · t test · p preset · +/- volume · q ", "SoundsMuted" } },
    footer_pos = "center",
  })
  vim.wo[ui.win].cursorline = true
  vim.wo[ui.win].cursorlineopt = "line"
  vim.wo[ui.win].winblend = 0
  vim.wo[ui.win].winhighlight = "CursorLine:SoundsSel,FloatBorder:SoundsAccent"
  render()
  vim.api.nvim_win_set_cursor(ui.win, { ui.order[1], 0 })

  local function map(keys, fn)
    for _, k in ipairs(type(keys) == "table" and keys or { keys }) do
      vim.keymap.set("n", k, fn, { buffer = ui.buf, nowait = true, silent = true })
    end
  end
  local function on_item(fn)
    return function()
      local item = current()
      if item then fn(item) end
    end
  end
  map({ "j", "<Down>", "<C-n>" }, function() move(1) end)
  map({ "k", "<Up>", "<C-p>" }, function() move(-1) end)
  map({ "<CR>", "<Space>", "x" }, on_item(toggle))
  map("s", on_item(choose))
  map("r", on_item(reset))
  map("t", on_item(play_item))
  map("m", function() sounds.toggle() refresh() end)
  map("p", function() M.cycle_preset(1) end)
  map("P", function() M.cycle_preset(-1) end)
  map({ "+", "=", "l" }, function() volume(1) end)
  map({ "-", "_", "h" }, function() volume(-1) end)
  map({ "q", "<Esc>" }, M.close)

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(ui.win),
    once = true,
    callback = function() ui.win = nil end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", { buffer = ui.buf, callback = set_hl })
end

return M
