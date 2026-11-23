-- "Where was I": the last few project sessions (persistence.nvim) with the most
-- recently used file in each. <CR> cd's there and reopens that file.
local U = require("header_art.static_util")
local uv = vim.uv or vim.loop

local function last_file(dir)
  for _, f in ipairs(vim.v.oldfiles) do
    if f:sub(1, #dir + 1) == dir .. "/" and not f:find("/%.git/") and uv.fs_stat(f) then return f end
  end
end

local function sessions()
  local okc, cfg = pcall(require, "persistence.config")
  local okp, p = pcall(require, "persistence")
  if not (okc and okp) then return {} end
  local out, seen, n = {}, {}, #cfg.options.dir
  for _, f in ipairs(p.list()) do
    local dir = (vim.split(f:sub(n + 1, -5), "%%", { plain = true })[1]):gsub("%%", "/")
    -- Claude's scratch checkouts and temp dirs are not projects you would resume
    if not seen[dir] and dir ~= vim.env.HOME and not dir:find("^/private/tmp") and not dir:find("^/tmp") and uv.fs_stat(dir) then
      seen[dir] = true
      local st = uv.fs_stat(f)
      out[#out + 1] = { dir = dir, branch = (vim.split(f:sub(n + 1, -5), "%%", { plain = true })[2] or ""):gsub("%%", "/"), mtime = st and st.mtime.sec or 0 }
      if #out >= 4 then break end
    end
  end
  return out
end

local function resume(dir)
  return function()
    vim.cmd.cd(vim.fn.fnameescape(dir))
    local f = last_file(dir)
    if f then U.open_file(f) else pcall(function() require("persistence").load() end) end
  end
end

return {
  id = "continue",
  title = "CONTINUE",
  every = 60,
  on = { "DirChanged", "User PersistenceSavePost" },
  available = function() return #sessions() > 0 end,
  render = function(w)
    local out, cwd = {}, vim.fn.getcwd()
    for i, s in ipairs(sessions()) do
      local act = resume(s.dir)
      local f = last_file(s.dir)
      out[#out + 1] = U.row({
        { i .. " ", "acc" }, { vim.fn.fnamemodify(s.dir, ":t"), s.dir == cwd and "b" or "" },
        { s.branch and ("  " .. s.branch) or "", "mid" },
      }, { { U.age(s.mtime), "dim" } }, w, act)
      out[#out + 1] = U.row({ { "  " .. (f and U.short_path(f, 3) or U.short_path(s.dir, 2)), "dim" } }, {}, w, act)
    end
    return out
  end,
}
