-- Jump between the git worktrees of the current repository.
--
-- `pick()` lists `git worktree list --porcelain` in a Snacks picker (preview =
-- that worktree's status + recent log) and `switch()` :cd's into the chosen
-- one. If the current buffer is a file inside the worktree being left, the
-- same relative path is opened in the new one (when it exists there), so you
-- don't keep editing the old checkout's copy. `:Worktree [name]` does the same
-- from the command line, with completion on branch / directory names.

local M = {}

-- Directory git should run in: the current file's dir if it is a real file,
-- else the cwd.
local function anchor()
  local name = vim.api.nvim_buf_get_name(0)
  if vim.bo.buftype == "" and name ~= "" and vim.uv.fs_stat(name) then
    return vim.fs.dirname(name)
  end
  return vim.fn.getcwd()
end

local function git(dir, args)
  local res = vim.system(vim.list_extend({ "git", "-C", dir }, args), { text = true }):wait()
  if res.code ~= 0 then return nil end
  return vim.trim(res.stdout)
end

---@class worktree
---@field path string
---@field head? string
---@field branch? string  short name, nil when detached
---@field detached? boolean
---@field bare? boolean
---@field locked? boolean
---@field prunable? boolean
---@field current? boolean worktree containing the anchor

---@return worktree[]?, string? err
function M.list(dir)
  dir = dir or anchor()
  local out = git(dir, { "worktree", "list", "--porcelain" })
  if not out then return nil, "not inside a git repository" end
  local top = git(dir, { "rev-parse", "--show-toplevel" })
  local wts, cur = {}, nil
  for line in (out .. "\n"):gmatch("([^\n]*)\n") do
    local key, val = line:match("^(%S+)%s?(.*)$")
    if key == "worktree" then
      cur = { path = val }
      wts[#wts + 1] = cur
    elseif cur and key == "HEAD" then
      cur.head = val:sub(1, 7)
    elseif cur and key == "branch" then
      cur.branch = val:gsub("^refs/heads/", "")
    elseif cur and (key == "detached" or key == "bare" or key == "locked" or key == "prunable") then
      cur[key] = true
    end
  end
  for _, wt in ipairs(wts) do
    -- realpath both sides: /tmp vs /private/tmp style symlinks on macOS
    wt.current = top ~= nil and vim.uv.fs_realpath(wt.path) == vim.uv.fs_realpath(top)
  end
  return wts
end

local function label(wt)
  return wt.branch or (wt.bare and "(bare)") or ("(detached " .. (wt.head or "?") .. ")")
end

---@param wt worktree
function M.switch(wt)
  if wt.bare then return vim.notify("can't cd into a bare repository", vim.log.levels.WARN) end
  if wt.prunable or not vim.uv.fs_stat(wt.path) then
    return vim.notify("worktree is gone (git worktree prune): " .. wt.path, vim.log.levels.WARN)
  end

  -- Relative path of the current file inside its worktree, to reopen it there.
  local rel
  local name = vim.api.nvim_buf_get_name(0)
  if vim.bo.buftype == "" and name ~= "" then
    local top = git(vim.fs.dirname(name), { "rev-parse", "--show-toplevel" })
    local real = vim.uv.fs_realpath(name)
    top = top and vim.uv.fs_realpath(top)
    if top and real and real:sub(1, #top + 1) == top .. "/" then rel = real:sub(#top + 2) end
  end

  vim.cmd.cd(vim.fn.fnameescape(wt.path))

  local target = rel and (wt.path .. "/" .. rel)
  if target and vim.uv.fs_stat(target) and vim.uv.fs_realpath(target) ~= vim.uv.fs_realpath(name) then
    if vim.bo.modified then
      vim.notify("current buffer is modified; kept it open", vim.log.levels.WARN)
    else
      vim.cmd.edit(vim.fn.fnameescape(target))
    end
  end
  vim.notify(("worktree → %s  %s"):format(label(wt), vim.fn.fnamemodify(wt.path, ":~")))
end

function M.pick()
  local wts, err = M.list()
  if not wts then return vim.notify(err, vim.log.levels.WARN) end

  local items, width = {}, 0
  for i, wt in ipairs(wts) do
    width = math.max(width, vim.api.nvim_strwidth(label(wt)))
    items[#items + 1] = {
      idx = i,
      score = 0,
      text = label(wt) .. " " .. wt.path,
      wt = wt,
      cwd = wt.path, -- preview command runs here
    }
  end

  -- The worktree you're in goes last, so <CR> on the first row always moves.
  table.sort(items, function(a, b)
    if a.wt.current ~= b.wt.current then return b.wt.current end
    return a.idx < b.idx
  end)

  Snacks.picker.pick({
    title = "Worktrees",
    items = items,
    format = function(item)
      local wt = item.wt
      local ret = {}
      ret[#ret + 1] = { wt.current and "● " or "  ", "SnacksPickerSpecial" }
      local l = label(wt)
      ret[#ret + 1] = { l, wt.branch and "SnacksPickerGitBranch" or "SnacksPickerGitDetached" }
      ret[#ret + 1] = { string.rep(" ", width - vim.api.nvim_strwidth(l) + 2) }
      ret[#ret + 1] = { vim.fn.fnamemodify(wt.path, ":~"), "SnacksPickerDir" }
      local flags = {}
      if wt.locked then flags[#flags + 1] = "locked" end
      if wt.prunable then flags[#flags + 1] = "prunable" end
      if #flags > 0 then ret[#ret + 1] = { "  [" .. table.concat(flags, ",") .. "]", "DiagnosticWarn" } end
      return ret
    end,
    preview = function(ctx)
      if ctx.item.wt.bare or not vim.uv.fs_stat(ctx.item.wt.path) then
        ctx.preview:reset()
        ctx.preview:set_lines({ "(no working tree)" })
        return
      end
      Snacks.picker.preview.cmd({
        "sh", "-c",
        "git -c color.status=always status -sb; echo;"
          .. " git --no-pager log --color=always --oneline --decorate -20",
      }, ctx)
    end,
    confirm = function(picker, item)
      picker:close()
      if item then M.switch(item.wt) end
    end,
  })
end

function M.setup()
  vim.api.nvim_create_user_command("Worktree", function(o)
    if o.args == "" then return M.pick() end
    local wts, err = M.list()
    if not wts then return vim.notify(err, vim.log.levels.WARN) end
    for _, wt in ipairs(wts) do
      if wt.branch == o.args or vim.fs.basename(wt.path) == o.args then return M.switch(wt) end
    end
    vim.notify("no worktree named " .. o.args, vim.log.levels.WARN)
  end, {
    nargs = "?",
    desc = "cd into a git worktree of this repository",
    complete = function(lead)
      local out = {}
      for _, wt in ipairs(M.list() or {}) do
        for _, n in ipairs({ wt.branch, vim.fs.basename(wt.path) }) do
          if n and n:find(lead, 1, true) == 1 and not vim.tbl_contains(out, n) then out[#out + 1] = n end
        end
      end
      return out
    end,
  })
  vim.keymap.set("n", "<leader>gw", M.pick, { desc = "Git: switch worktree (cd)" })
end

return M
