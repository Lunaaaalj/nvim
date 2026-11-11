-- Telescope picker for the dashboard background art, modelled on the
-- colorscheme picker (<leader>cs): moving the selection previews the piece
-- live, <CR> keeps it (persisted across restarts), <Esc> puts the old one back.
--
-- The preview pane animates the piece itself (header_art.render_frame), so the
-- picker is useful from any buffer, not only over the dashboard. When the
-- dashboard is visible behind the picker, it switches live too.

local art = require("header_art")
local pieces = require("header_art.pieces")

local M = {}

local OFF = "off"
local labels = {
  plasma = "plasma   · drifting interference waves",
  torus = "torus    · a spinning donut",
  orb = "orb      · a lit sphere",
  rings = "rings    · ripples from the centre",
  flow = "flow     · particles in a flow field",
  terrain = "terrain  · rolling ridgelines",
  galaxy = "galaxy   · an Sc spiral around the content",
  galaxies = "galaxies · four small spirals in the free corners",
  descent = "descent  · gradient probes on a loss surface, ripples in the wells",
  [OFF] = "off      · static braille header",
}

local uv = vim.uv or vim.loop
local pns = vim.api.nvim_create_namespace("header_art_preview")

function M.open()
  local ok = pcall(require, "telescope")
  if not ok then return vim.notify("header_art: Telescope is not available", vim.log.levels.WARN) end
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local previewers = require("telescope.previewers")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local conf = require("telescope.config").values

  local before = art.options()
  local original = before.enabled and before.piece or OFF
  -- current choice first, like the colorscheme picker
  local results = { original }
  for _, name in ipairs(vim.list_extend(vim.deepcopy(pieces.names), { OFF })) do
    if name ~= original then results[#results + 1] = name end
  end

  -- One animation timer for the preview pane, re-targeted on every selection.
  local timer, cache, t, current = nil, {}, 0, nil
  local function stop()
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
  end

  local function paint(self)
    local buf, win = self.state.bufnr, self.state.winid
    if not (buf and vim.api.nvim_buf_is_valid(buf) and win and vim.api.nvim_win_is_valid(win)) then return false end
    local w, h = vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win)
    local lines, marks
    if current == OFF then
      lines, marks = {}, {}
      for _ = 1, math.floor(h / 2) - 1 do lines[#lines + 1] = "" end
      local msg = "art off: the dashboard shows the braille header"
      lines[#lines + 1] = string.rep(" ", math.max(0, math.floor((w - #msg) / 2))) .. msg
    else
      lines, marks = art.render_frame(current, w, h, t, cache)
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_clear_namespace(buf, pns, 0, -1)
    for _, m in ipairs(marks) do
      vim.api.nvim_buf_set_extmark(buf, pns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
    end
    return true
  end

  local previewer = previewers.new_buffer_previewer({
    title = "Preview",
    define_preview = function(self, entry)
      current = entry.value
      art.apply(current ~= OFF and current or nil, false) -- live on the dashboard, if shown
      vim.wo[self.state.winid].wrap = false
      stop()
      if not paint(self) or current == OFF then return end
      local fps = math.max(1, before.fps)
      local last = uv.hrtime()
      timer = uv.new_timer()
      timer:start(0, math.floor(1000 / fps), vim.schedule_wrap(function()
        if not timer then return end
        local now = uv.hrtime()
        t = t + math.min(0.25, (now - last) / 1e9) * before.speed
        last = now
        if not paint(self) then stop() end
      end))
    end,
    teardown = stop,
  })

  local chosen = false
  pickers
    .new({}, {
      prompt_title = "Dashboard art",
      finder = finders.new_table({
        results = results,
        entry_maker = function(name)
          return { value = name, display = labels[name] or name, ordinal = name }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = previewer,
      attach_mappings = function(bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          chosen = true
          actions.close(bufnr)
          if not entry then return end
          art.apply(entry.value ~= OFF and entry.value or nil, true)
          vim.notify("Dashboard art: " .. entry.value)
        end)
        actions.close:enhance({
          post = function()
            stop()
            if not chosen then art.apply(original ~= OFF and original or nil, false) end
          end,
        })
        return true
      end,
    })
    :find()
end

return M
