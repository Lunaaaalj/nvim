-- Miller-column file explorer: the branch you are on as floating columns, a
-- preview of the entry under the cursor on the right, and file operations as
-- text edits (like oil), applied with `=` after a confirmation.
--
-- Neo-tree stays the default explorer (`use_as_default_explorer = false`), so
-- `:e .` and the neo-tree hijack are unchanged. Colours come from
-- defaults/colors.lua and follow neo-tree's conventions: directories bold,
-- git state as the name's colour only.

-- Git state of every path under the repo of `dir`, refreshed at most once per
-- second per repo (git runs async; columns repaint when it answers).
local git = { cache = {}, pending = {} }

local function repo_root(dir)
  local found = vim.fs.find(".git", { path = dir, upward = true })[1]
  return found and vim.fs.dirname(found)
end

-- porcelain XY → highlight group
local function git_group(xy)
  if xy == "??" then return "MiniFilesGitUntracked" end
  if xy:find("U") or xy == "AA" or xy == "DD" then return "MiniFilesGitConflict" end
  if xy:find("R") then return "MiniFilesGitRenamed" end
  if xy:find("D") then return "MiniFilesGitDeleted" end
  if xy:find("A") then return "MiniFilesGitAdded" end
  return "MiniFilesGitModified"
end

local ns = vim.api.nvim_create_namespace("minifiles_git")

local function paint(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local ok, MiniFiles = pcall(require, "mini.files")
  if not ok then return end
  for lnum = 1, vim.api.nvim_buf_line_count(buf) do
    local entry = MiniFiles.get_fs_entry(buf, lnum)
    if not entry then break end
    local root = repo_root(vim.fs.dirname(entry.path))
    local status = root and git.cache[root] and git.cache[root].map[entry.path]
    if status then
      -- The name follows the icon prefix: highlight from the first byte of
      -- the name to the end of the line.
      local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
      local col = line:find(entry.name, 1, true)
      if col then
        vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, col - 1, {
          end_col = #line, hl_group = status, priority = 150,
        })
      end
    end
  end
end

local function refresh(root, buf)
  local c = git.cache[root]
  if c and vim.uv.now() - c.time < 1000 then return paint(buf) end
  if git.pending[root] then
    table.insert(git.pending[root], buf)
    return
  end
  git.pending[root] = { buf }
  vim.system({ "git", "-C", root, "status", "--porcelain", "-z", "--untracked-files=all" }, { text = true }, function(out)
    vim.schedule(function()
      local map = {}
      if out.code == 0 then
        local items = vim.split(out.stdout or "", "\0", { plain = true })
        local i = 1
        while i <= #items do
          local item = items[i]
          if #item > 3 then
            local xy, path = item:sub(1, 2), item:sub(4)
            if xy:find("R") or xy:find("C") then i = i + 1 end -- next item is the source path
            local group = git_group(xy)
            local full = root .. "/" .. path
            map[full] = group
            -- A changed file marks every folder above it (bold folder names
            -- carry the colour, like neo-tree's single dot).
            local dir = vim.fs.dirname(full)
            while dir and #dir > #root and not map[dir] do
              map[dir] = "MiniFilesGitModified"
              dir = vim.fs.dirname(dir)
            end
          end
          i = i + 1
        end
      end
      git.cache[root] = { time = vim.uv.now(), map = map }
      for _, b in ipairs(git.pending[root] or {}) do paint(b) end
      git.pending[root] = nil
    end)
  end)
end

local function highlights()
  local colors = require("defaults.colors")
  local set = function(name, def) vim.api.nvim_set_hl(0, name, def) end
  local normal = colors.fg("Normal") or 0xc0c0c0
  local muted = colors.fg("Comment") or normal
  local accent = colors.accent() or normal
  local base = vim.o.background == "light" and 0xffffff
    or (vim.g.ui_transparent and tonumber(colors.terminal_bg:sub(2), 16))
    or colors.bg()

  set("MiniFilesDirectory", { fg = normal, bold = true })
  set("MiniFilesFile", { fg = normal })
  set("MiniFilesTitle", { fg = muted })
  set("MiniFilesTitleFocused", { fg = accent, bold = true })
  set("MiniFilesBorder", { fg = colors.blend(normal, base, 0.25) })
  set("MiniFilesBorderModified", { fg = accent })
  -- cursorline.lua blanks CursorLine in transparent mode, and the explorer's
  -- selection *is* its cursorline, so it gets its own band (as neo-tree does).
  local band = vim.g.ui_transparent and colors.blend(normal, base, 0.10)
    or vim.api.nvim_get_hl(0, { name = "CursorLine", link = false }).bg
    or colors.blend(normal, base, 0.10)
  set("MiniFilesCursorLine", { bg = band, bold = true })

  local added = colors.fg("GitSignsAdd", "Added", "DiagnosticOk")
  local changed = colors.fg("GitSignsChange", "Changed", "DiagnosticWarn")
  local removed = colors.fg("GitSignsDelete", "Removed", "DiagnosticError")
  set("MiniFilesGitAdded", { fg = added })
  set("MiniFilesGitUntracked", { fg = added, italic = true })
  set("MiniFilesGitModified", { fg = changed })
  set("MiniFilesGitDeleted", { fg = removed })
  set("MiniFilesGitRenamed", { fg = colors.fg("Special") or accent })
  set("MiniFilesGitConflict", { fg = colors.fg("DiagnosticError") or removed, bold = true })
end

-- Open the entry under the cursor in a split of the window the explorer was
-- opened from, then close the explorer.
local function open_split(cmd)
  return function()
    local MiniFiles = require("mini.files")
    local entry = MiniFiles.get_fs_entry()
    if not entry or entry.fs_type ~= "file" then return end
    local target = MiniFiles.get_explorer_state().target_window
    MiniFiles.close()
    vim.api.nvim_win_call(target, function() vim.cmd(cmd .. " " .. vim.fn.fnameescape(entry.path)) end)
  end
end

return {
  "echasnovski/mini.files",
  version = "*",
  keys = {
    {
      "<leader>e",
      function()
        local MiniFiles = require("mini.files")
        local path = vim.api.nvim_buf_get_name(0)
        -- Unnamed / non-file buffers (dashboard, terminals): start at the cwd.
        if path == "" or vim.bo.buftype ~= "" or not vim.uv.fs_stat(path) then path = nil end
        if not MiniFiles.close() then MiniFiles.open(path) end
      end,
      desc = "Files: columns at the current file",
    },
    {
      "<leader>E",
      function()
        local MiniFiles = require("mini.files")
        if not MiniFiles.close() then MiniFiles.open(vim.uv.cwd(), false) end
      end,
      desc = "Files: columns at the cwd",
    },
  },
  opts = {
    mappings = {
      go_in = "l",
      go_in_plus = "<CR>", -- open a file and close; enter a folder
      go_out = "h",
      go_out_plus = "H",
      synchronize = "=",
    },
    options = {
      use_as_default_explorer = false, -- neo-tree / oil keep directory buffers
      permanent_delete = false, -- deletes go to mini.files' trash
    },
    windows = {
      preview = true,
      width_focus = 32,
      width_nofocus = 20,
      width_preview = 50,
    },
  },
  config = function(_, opts)
    require("mini.files").setup(opts)
    highlights()

    local group = vim.api.nvim_create_augroup("MiniFilesConfig", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = highlights })

    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "MiniFilesBufferUpdate",
      callback = function(ev)
        local buf = ev.data.buf_id
        local entry = require("mini.files").get_fs_entry(buf, 1)
        local root = entry and repo_root(vim.fs.dirname(entry.path))
        if root then refresh(root, buf) end
      end,
    })

    -- Writing through `=` changes git state: drop the cache so it is re-read.
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = { "MiniFilesActionCreate", "MiniFilesActionDelete", "MiniFilesActionRename", "MiniFilesActionMove", "MiniFilesActionCopy" },
      callback = function() git.cache = {} end,
    })

    -- Floats get the global winblend = 10; columns of text over a blended
    -- editor are hard to read, so the explorer is opaque.
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "MiniFilesWindowOpen",
      callback = function(ev) vim.wo[ev.data.win_id].winblend = 0 end,
    })

    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "MiniFilesBufferCreate",
      callback = function(ev)
        local buf = ev.data.buf_id
        local map = function(lhs, rhs, desc) vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc }) end
        map("<C-v>", open_split("vsplit"), "Open in a vertical split")
        map("<C-x>", open_split("split"), "Open in a horizontal split")
        map("<C-t>", open_split("tabedit"), "Open in a new tab")
        -- Dotfiles show by default (no filter); g. hides them for this explorer.
        map("g.", function()
          vim.g.minifiles_hide_dotfiles = not vim.g.minifiles_hide_dotfiles
          local hide = vim.g.minifiles_hide_dotfiles
          require("mini.files").refresh({
            content = { filter = function(e) return not (hide and vim.startswith(e.name, ".")) end },
          })
        end, "Toggle dotfiles")
        map("gy", function()
          local entry = require("mini.files").get_fs_entry()
          if not entry then return end
          vim.fn.setreg("+", entry.path)
          vim.notify("Copied " .. vim.fn.fnamemodify(entry.path, ":~"), vim.log.levels.INFO)
        end, "Yank absolute path")
        map("gO", function()
          local entry = require("mini.files").get_fs_entry()
          if entry then vim.system({ "open", "-R", entry.path }) end
        end, "Reveal in Finder")
      end,
    })
  end,
}
