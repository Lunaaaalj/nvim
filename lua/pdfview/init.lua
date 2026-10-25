-- In-terminal PDF viewer drawn with kitty's graphics protocol.
--
--   lua/pdfview/render.lua  rasterising + caches (pdftoppm, ImageMagick, poppler)
--   lua/pdfview/viewer.lua  one viewer per PDF buffer: navigation, zoom, spread,
--                           search, links, highlights, keymaps
--   lua/pdfview/tex.lua     LaTeX preview split, SyncTeX, compile status
--   lua/pdfview/store.lua   per-PDF page/zoom memory
--
-- This file is required at startup (lua/defaults/init.lua) only to claim
-- *.pdf buffers and clean up; everything else loads on first use.

local M = {}

M.config = {
  min_width = 0.25, -- the preview split fits the page's height, within these
  max_width = 0.6, -- fractions of the editor width
  follow = true, -- after a successful compile, jump to the cursor's page
  colors = "theme", -- default for new PDFs: "theme" (scheme fg, transparent paper) | "paper"
  zoom_step = 1.2,
  scroll = 0.15, -- j/k step, as a fraction of the visible height
  prefetch = true, -- render the neighbouring pages in the background
}

local root = vim.fn.stdpath("cache") .. "/pdfview"

function M.supported()
  if not (_G.Snacks and Snacks.image.supports_terminal()) then return false end
  for _, bin in ipairs({ "pdftoppm", "pdfinfo", "pdftohtml", "pdftotext", "magick", "synctex" }) do
    if vim.fn.executable(bin) == 0 then return false end
  end
  return true
end

-- snacks.image claims *.pdf as well (first page only, as a picture): drop it
-- from its formats before its one-time setup, and remove its handler if that
-- setup already ran.
local function claim_from_snacks()
  local cfg = Snacks.image.config
  cfg.formats = vim.tbl_filter(function(f) return f ~= "pdf" end, cfg.formats or {})
  Snacks.image.setup()
  pcall(vim.api.nvim_clear_autocmds, { group = "snacks.image", event = "BufReadCmd", pattern = "*.pdf" })
end

-- BufReadCmd for *.pdf: the buffer becomes a viewer.
function M.open_file(ev)
  local buf, file = ev.buf, vim.fn.fnamemodify(ev.match, ":p")
  vim.bo[buf].buftype = "nowrite" -- has a name (so sessions keep it), never written
  vim.bo[buf].swapfile = false
  if not M.supported() then
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "PDF: " .. file, "", "This terminal can't draw images; opened in the system viewer instead.",
    })
    vim.bo[buf].modifiable, vim.bo[buf].modified = false, false
    vim.ui.open(file)
    return
  end
  claim_from_snacks()
  local V = require("pdfview.viewer")
  local v = V.get(buf) or V.new(buf, file, "file")
  vim.schedule(function() v:render() end)
end

-- Sessions (lua/plugins/persistence.lua). The preview's nofile buffer can't be
-- restored by :mksession, so it is closed before the save and re-launched from
-- the remembered TeX file afterwards. PDF files restore on their own: they
-- have a name and come back through BufReadCmd.
local reopen ---@type fun()?

function M.session_save_pre()
  vim.g.Session_pdfview = ""
  reopen = nil
  local tex = package.loaded["pdfview.tex"]
  local v = tex and tex.viewer
  local win = v and vim.api.nvim_buf_is_valid(v.buf) and v:win()
  if not win then return end
  local tw = v.tex_win
  local src = tw and vim.api.nvim_win_is_valid(tw) and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(tw))
  if not src or src == "" then return end
  vim.g.Session_pdfview = vim.json.encode({ tex = src })
  vim.api.nvim_win_close(win, true)
  reopen = function()
    local cur = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(tw)
    tex.view()
    if vim.api.nvim_win_is_valid(cur) then vim.api.nvim_set_current_win(cur) end
  end
end

function M.session_save_post()
  local exiting = vim.v.exiting ~= nil and vim.v.exiting ~= vim.NIL
  if reopen and not exiting then reopen() end
  reopen = nil
end

function M.session_restore()
  local ok, s = pcall(vim.json.decode, vim.g.Session_pdfview or "")
  if not (ok and type(s) == "table" and s.tex) then return end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == s.tex then
      local cur = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_win(win)
      require("pdfview.tex").view()
      if vim.api.nvim_win_is_valid(cur) then vim.api.nvim_set_current_win(cur) end
      return
    end
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("pdfview.file", { clear = true })
  vim.api.nvim_create_autocmd("BufReadCmd", { group = group, pattern = "*.pdf", callback = M.open_file })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if package.loaded["pdfview.store"] then require("pdfview.store").flush() end
      if package.loaded["pdfview.render"] then require("pdfview.render").clear() end
    end,
  })
  -- Each Neovim renders into cache/pdfview/<pid>; sweep dirs left by dead ones.
  vim.defer_fn(function()
    if vim.fn.isdirectory(root) == 0 then return end
    for name in vim.fs.dir(root) do
      local pid = tonumber(name)
      if pid and pid ~= vim.fn.getpid() and not vim.uv.kill(pid, 0) then vim.fn.delete(root .. "/" .. name, "rf") end
    end
  end, 3000)
end

return M
