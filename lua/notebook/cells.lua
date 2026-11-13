-- Cells (issue #40, phase 4): one parser for every notebook-like buffer.
--
--   ```{r}, ```{python echo=false}   Quarto / R Markdown chunks (any language)
--   ```python, ```r, ```julia        plain fences, ONLY these languages: a
--                                    ```bash or ```text block in prose is not
--                                    code to send to the kernel
--   # %%                             percent scripts (.py/.R/.jl); a
--                                    `# %% [markdown]` cell is skipped
--
-- Fences inside jupytext's `<!-- #region -->` … `<!-- #endregion -->` (a
-- markdown cell that contains a fence) are prose too.
local M = {}

M.languages = { python = "python", py = "python", r = "r", julia = "julia" }

---@class NotebookCell
---@field first integer   1-based line of the opening fence / `# %%` (0 = file start)
---@field last integer    1-based closing fence / last line of the cell
---@field from integer    first line of code
---@field to integer      last line of code (to < from: empty)
---@field lang string

local function percent_marker(l)
  return l:match("^%s*#%s*%%%%") ~= nil
end

--- Is this a percent script (a code filetype with `# %%` markers)?
function M.is_percent(buf)
  local ft = vim.bo[buf].filetype
  if ft ~= "python" and ft ~= "r" and ft ~= "julia" then return false end
  for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if percent_marker(l) then return true end
  end
  return false
end

local function parse_percent(lines, lang)
  local cells, start = {}, nil
  local function close(upto)
    if start == nil then return end
    local hdr = lines[start] or ""
    if start == 0 or not hdr:lower():find("%[markdown%]") then
      local to = upto
      while to > start and not (lines[to] or ""):find("%S") do to = to - 1 end
      local c = { first = start, last = upto, from = start + 1, to = to, lang = lang }
      -- code before the first marker counts only when there is some
      if start > 0 or c.to >= c.from then cells[#cells + 1] = c end
    end
  end
  start = 0
  for i, l in ipairs(lines) do
    if percent_marker(l) then
      close(i - 1)
      start = i
    end
  end
  close(#lines)
  return cells
end

local function parse_fences(lines)
  local cells, open, region = {}, nil, false
  for i, l in ipairs(lines) do
    if not open then
      if l:match("^%s*<!%-%-%s*#region") then
        region = true
      elseif l:match("^%s*<!%-%-%s*#endregion") then
        region = false
      elseif not region then
        local ticks, info = l:match("^(```+)%s*(.-)%s*$")
        if ticks then
          local lang = info:match("^{%s*([%w_]+)") -- ```{r ...}
          if not lang and info ~= "" then
            local plain = info:match("^([%w_]+)$")
            lang = plain and M.languages[plain:lower()] and plain or nil
          end
          if lang then
            open = { first = i, ticks = #ticks, lang = M.languages[lang:lower()] or lang:lower() }
          elseif info ~= "" then
            open = { first = i, ticks = #ticks, skip = true } -- ```bash: walk past it
          end
        end
      end
    else
      local ticks = l:match("^(```+)%s*$")
      if ticks and #ticks >= open.ticks then
        if not open.skip then
          cells[#cells + 1] = { first = open.first, last = i, from = open.first + 1, to = i - 1, lang = open.lang }
        end
        open = nil
      end
    end
  end
  return cells
end

---@return NotebookCell[]
function M.parse(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if M.is_percent(buf) then return parse_percent(lines, vim.bo[buf].filetype) end
  return parse_fences(lines)
end

--- Cell containing `line` (default: cursor), its index, and all cells.
function M.at(line, buf)
  buf = buf or vim.api.nvim_get_current_buf()
  line = line or vim.api.nvim_win_get_cursor(0)[1]
  local cells = M.parse(buf)
  for i, c in ipairs(cells) do
    if line >= math.max(c.first, 1) and line <= c.last then return c, i, cells end
  end
  return nil, nil, cells
end

-- ---------------------------------------------------------------------------
-- Running (through Molten, kernel started on demand)

local function eval(cells)
  cells = vim.tbl_filter(function(c) return c.to >= c.from end, cells)
  if #cells == 0 then return end
  local repl = require("notebook.repl")
  if require("notebook").engine() == "repl" and repl.supports(cells[1].lang) then
    return repl.run(cells)
  end
  require("notebook.kernel").ensure(function()
    for _, c in ipairs(cells) do
      vim.fn.MoltenEvaluateRange(c.from, c.to)
    end
  end)
end

function M.run_cell()
  local c = M.at()
  if not c then return vim.notify("Not inside a code cell", vim.log.levels.WARN) end
  eval({ c })
end

--- Run the cell, then move to the next one (creating it at the end).
function M.run_and_next()
  local c, i, cells = M.at()
  if not c then return M.goto_cell(1) end
  eval({ c })
  local nxt = cells[i + 1]
  if nxt then
    vim.api.nvim_win_set_cursor(0, { nxt.from, 0 })
  else
    M.new_cell(true)
  end
end

function M.run_all()
  eval(M.parse())
end

--- Cells above the cursor (`above`), or the current one and everything below.
function M.run_split(above)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local _, i, cells = M.at(line)
  local pick = {}
  for j, cell in ipairs(cells) do
    local is_above = i and j < i or (not i and cell.last < line)
    if is_above == above then pick[#pick + 1] = cell end
  end
  eval(pick)
end

function M.run_line()
  local l = vim.api.nvim_win_get_cursor(0)[1]
  if require("notebook").engine() == "repl" then
    local c = M.at(l) or { lang = vim.bo.filetype }
    if require("notebook.repl").supports(c.lang) then
      return require("notebook.repl").run({ { from = l, to = l, lang = c.lang } })
    end
  end
  require("notebook.kernel").ensure(function() vim.fn.MoltenEvaluateRange(l, l) end)
end

function M.run_visual()
  vim.cmd("normal! \27") -- leave visual mode so '< and '> are set
  require("notebook.kernel").ensure(function()
    -- separate calls: MoltenEvaluateVisual takes args, so `|` would be one
    vim.cmd("MoltenEvaluateVisual")
    vim.cmd("normal! gv")
  end)
end

-- ---------------------------------------------------------------------------
-- Moving and editing

--- Jump `count` cells forward (negative: back), to the first code line.
--- Back from inside a cell goes to its top first, like `[[`.
function M.goto_cell(count)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local cells, target, seen = M.parse(), nil, 0
  local first, last, step = 1, #cells, 1
  if count < 0 then first, last, step = #cells, 1, -1 end
  for j = first, last, step do
    local c = cells[j]
    if (count > 0 and c.from > line) or (count < 0 and c.from < line) then
      seen = seen + 1
      if seen == math.abs(count) then target = c break end
    end
  end
  if target then
    vim.cmd("normal! m'")
    vim.api.nvim_win_set_cursor(0, { math.max(target.from, 1), 0 })
  end
end

--- Insert an empty cell below (or above) the current one, same language.
function M.new_cell(below)
  local buf = vim.api.nvim_get_current_buf()
  local c, _, cells = M.at()
  local lang = (c or cells[#cells] or {}).lang or require("notebook.kernel").wanted(buf)
  local lines, at
  if M.is_percent(buf) then
    lines = { "# %%", "" }
    at = c and (below and c.last or math.max(c.first - 1, 0)) or vim.api.nvim_win_get_cursor(0)[1]
  else
    -- keep the buffer's fence style: curly if any cell uses it
    local curly = false
    for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      if l:match("^```+%s*{") then curly = true break end
    end
    local open = curly and ("```{%s}"):format(lang) or ("```" .. lang)
    lines = { "", open, "", "```" }
    at = c and (below and c.last or c.first - 1) or vim.api.nvim_win_get_cursor(0)[1]
  end
  vim.api.nvim_buf_set_lines(buf, at, at, false, lines)
  local code = at + (M.is_percent(buf) and 2 or 3)
  vim.api.nvim_win_set_cursor(0, { code, 0 })
end

--- Text object: inner = the code lines, around = with the fences / marker.
function M.select(around)
  local c = M.at()
  if not c then return end
  local from, to = c.from, c.to
  if around then from, to = math.max(c.first, 1), c.last end
  if to < from then return end
  vim.cmd("normal! \27")
  vim.api.nvim_win_set_cursor(0, { from, 0 })
  vim.cmd("normal! V")
  vim.api.nvim_win_set_cursor(0, { to, 0 })
end

-- ---------------------------------------------------------------------------
-- Dim cell separators

local ns = vim.api.nvim_create_namespace("notebook_cells")

function M.decorate(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local n = vim.api.nvim_buf_line_count(buf)
  for _, c in ipairs(M.parse(buf)) do
    for _, l in ipairs({ c.first, c.last }) do
      local text = l >= 1 and l <= n and vim.api.nvim_buf_get_lines(buf, l - 1, l, false)[1] or nil
      -- the closing line of a percent cell is code, not a separator
      if text and (text:match("^%s*```") or text:match("^%s*#%s*%%%%")) then
        vim.api.nvim_buf_set_extmark(buf, ns, l - 1, 0, {
          end_col = #text, hl_group = "NotebookCellFence", priority = 200,
        })
      end
    end
  end
end

return M
