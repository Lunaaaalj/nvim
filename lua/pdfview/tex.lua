-- LaTeX side of lua/pdfview: the preview split for the current VimTeX project,
-- SyncTeX in both directions, compile status in the winbar, live follow.
--
--   * forward: `synctex view` per line -> boxes, drawn as the accent highlight
--   * inverse: `synctex edit -o page:x:y:pdf` -> file + line (works from any
--     viewer whose PDF has a .synctex.gz, not just the preview)
--   * VimtexEventCompiling / CompileFailed / CompileSuccess drive the status;
--     with `follow`, a successful compile re-syncs to the cursor

local V = require("pdfview.viewer")
local R = require("pdfview.render")

local M = {}

M.viewer = nil ---@type table? the preview split's viewer
M.live = false -- forward-sync on CursorHold
local last ---@type string? "buf:line" last forward-synced, so live follow skips repeats

local function cfg() return require("pdfview").config end

-- The project's PDF according to VimTeX (what its own viewers open: it honours
-- the latexmk out_dir); nil until the first compile has produced one. v2.18 has
-- no b:vimtex.out().
local function pdf_for(buf)
  local ok, out = pcall(vim.api.nvim_buf_call, buf, function()
    return vim.fn.eval("exists('*b:vimtex.compiler.get_file') ? b:vimtex.compiler.get_file('pdf') : ''")
  end)
  if ok and type(out) == "string" and out ~= "" then return vim.fn.fnamemodify(out, ":p") end
end

local function preview(pdf)
  local v = M.viewer
  if v and vim.api.nvim_buf_is_valid(v.buf) then
    if v.pdf ~= pdf then v:set_pdf(pdf) end
    return v
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  pcall(vim.api.nvim_buf_set_name, buf, "pdfview://" .. vim.fs.basename(pdf))
  v = V.new(buf, pdf, "tex")
  M.viewer = v
  return v
end

-- `synctex view` output -> { { page, x0, y0, x1, y1 } } in points.
local function parse_view(stdout)
  local recs, cur = {}, nil
  for line in (stdout or ""):gmatch("[^\n]+") do
    local k, val = line:match("^(%a+):(.*)$")
    if k == "Page" then
      cur = { page = tonumber(val) }
      recs[#recs + 1] = cur
    elseif cur and (k == "h" or k == "v" or k == "W" or k == "H") then
      cur[k] = tonumber(val)
    end
  end
  local boxes = {}
  for _, r in ipairs(recs) do
    if r.page and r.h and r.v and r.W and r.H then
      -- h/v: left edge and baseline; extend a little below for descenders
      boxes[#boxes + 1] = { r.page, r.h, r.v - r.H, r.h + r.W, r.v + r.H * 0.3 }
    end
  end
  return boxes
end

-- Forward search: show viewer `v` at lines l1..l2 of `win`'s buffer and
-- highlight them on the page.
function M.sync(v, win, l1, l2)
  local buf = vim.api.nvim_win_get_buf(win)
  local file = vim.api.nvim_buf_get_name(buf)
  local cur = vim.api.nvim_win_get_cursor(win)
  l1 = l1 or cur[1]
  l2 = math.min(l2 or l1, l1 + 60) -- one synctex process per line; keep it sane
  last = buf .. ":" .. l1
  local results, pending = {}, l2 - l1 + 1
  for l = l1, l2 do
    R.run({ "synctex", "view", "-i", ("%d:%d:%s"):format(l, cur[2] + 1, file), "-o", v.pdf }, function(res)
      results[l] = parse_view(res.stdout)
      pending = pending - 1
      if pending > 0 then return end
      local page, boxes = nil, {}
      for i = l1, l2 do
        for _, b in ipairs(results[i] or {}) do
          page = page or b[1]
          if b[1] == page then boxes[#boxes + 1] = { b[2], b[3], b[4], b[5] } end
        end
      end
      if page then
        v.sync_marks = { page = page, boxes = boxes }
        v:reveal(page, boxes[1][2], boxes[#boxes][4])
      end
      v:winbar()
      v:render()
    end)
  end
end

-- Open (or refresh) the preview and forward-search to the cursor -- or, from
-- visual mode, the selected lines. Falls back to Skim where images can't be
-- drawn.
function M.view()
  local l1, l2
  if vim.fn.mode():find("^[vV\22]") then
    l1, l2 = vim.fn.line("v"), vim.fn.line(".")
    if l1 > l2 then l1, l2 = l2, l1 end
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  end
  if not require("pdfview").supported() then return vim.cmd("VimtexView") end
  local pdf = pdf_for(0)
  if not pdf then return V.notify("No PDF yet -- compile first (<leader>ll)") end
  M.setup()
  local v = preview(pdf)
  v.tex_win = vim.api.nvim_get_current_win()
  if not v:win() then v:open_split() end
  M.sync(v, v.tex_win, l1, l2)
end

-- Put the cursor on `file`:`line` in a source window, then mark that line on
-- the page so the jump is visible on both sides.
function M.jump(v, file, line)
  if v.float then v:toggle_float() end -- don't land behind the reading float
  local win = v.tex_win
  if not (win and vim.api.nvim_win_is_valid(win) and win ~= v:win()) then
    local alt = vim.fn.win_getid(vim.fn.winnr("#"))
    if alt ~= 0 and alt ~= v:win() and vim.api.nvim_win_get_config(alt).relative == "" then
      win = alt
    else -- the PDF is the only window: split one off for the source
      vim.cmd("leftabove vsplit")
      win = vim.api.nvim_get_current_win()
    end
  end
  vim.api.nvim_set_current_win(win)
  if vim.fn.simplify(vim.api.nvim_buf_get_name(0)) ~= file then vim.cmd.edit(vim.fn.fnameescape(file)) end
  line = math.min(line, vim.api.nvim_buf_line_count(0))
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.cmd("normal! zz")
  vim.hl.range(0, vim.api.nvim_create_namespace("pdfview"), "IncSearch", { line - 1, 0 }, { line - 1, -1 }, { timeout = 600 })
  if v.kind == "tex" then v.tex_win = win end
  M.sync(v, win)
end

-- Inverse search from page point (x, y) of viewer `v`.
function M.inverse(v, page, x, y)
  R.run({ "synctex", "edit", "-o", ("%d:%.2f:%.2f:%s"):format(page, x, y, v.pdf) }, function(res)
    local out = res.stdout or ""
    local file, line = out:match("Input:([^\n]+)"), tonumber(out:match("Line:(%d+)"))
    if not (file and line) then
      return V.notify(v.kind == "file" and "No SyncTeX data for this PDF" or "No source found here", vim.log.levels.INFO)
    end
    M.jump(v, vim.fn.simplify(file), line) -- synctex reports paths like dir/./file.tex
  end)
end

function M.toggle_live()
  M.live = not M.live
  last = nil
  if M.viewer and vim.api.nvim_buf_is_valid(M.viewer.buf) then M.viewer:winbar() end
  V.notify("Live follow " .. (M.live and "on" or "off"), vim.log.levels.INFO)
end

local did_setup = false
function M.setup()
  if did_setup then return end
  did_setup = true
  local group = vim.api.nvim_create_augroup("pdfview.tex", { clear = true })
  local function viewer()
    local v = M.viewer
    if v and vim.api.nvim_buf_is_valid(v.buf) then return v end
  end
  -- the events fire in the buffer being compiled: ignore other projects
  local function ours(v)
    local pdf = pdf_for(0)
    return pdf == nil or pdf == v.pdf
  end
  local function status(s)
    return function()
      local v = viewer()
      if not (v and ours(v)) then return end
      v.status = s
      v:winbar()
    end
  end
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "VimtexEventCompiling", callback = status("compiling") })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "VimtexEventCompileFailed", callback = status("failed") })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "VimtexEventCompileSuccess",
    callback = function()
      local v = viewer()
      if not (v and ours(v)) then return end
      v.status = nil
      if not v:win() then return end
      local tw = v.tex_win
      if cfg().follow and tw and vim.api.nvim_win_is_valid(tw) and vim.bo[vim.api.nvim_win_get_buf(tw)].filetype == "tex" then
        M.sync(v, tw)
      else
        v:winbar()
        v:render()
      end
    end,
  })
  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    pattern = "*.tex",
    callback = function(ev)
      local v = viewer()
      if not (M.live and v and v:win() and ours(v)) then return end
      local win = vim.api.nvim_get_current_win()
      if last ~= ev.buf .. ":" .. vim.api.nvim_win_get_cursor(win)[1] then
        v.tex_win = win
        M.sync(v, win)
      end
    end,
  })
end

return M
