-- Recently used files in the current project (oldfiles, MRU order).
local U = require("header_art.static_util")
local uv = vim.uv or vim.loop

local function files()
  local cwd, out = vim.fn.getcwd(), {}
  for _, f in ipairs(vim.v.oldfiles) do
    if f:sub(1, #cwd + 1) == cwd .. "/" and not f:find("/%.git/") and not f:find("^/private/tmp") then
      local st = uv.fs_stat(f)
      if st and st.type == "file" then
        out[#out + 1] = { path = f, mtime = st.mtime.sec }
        if #out >= 5 then break end
      end
    end
  end
  return out
end

return {
  id = "recent",
  title = "RECENT",
  badge = "p",
  every = 60,
  on = { "BufWritePost", "DirChanged" },
  available = function() return #files() > 0 end,
  render = function(w)
    local out, cwd = {}, vim.fn.getcwd()
    for _, f in ipairs(files()) do
      local rel = f.path:sub(#cwd + 2)
      local dir = vim.fn.fnamemodify(rel, ":h")
      out[#out + 1] = U.row({
        { vim.fn.fnamemodify(rel, ":t") }, { dir ~= "." and ("  " .. dir .. "/") or "", "dim" },
      }, { { U.age(f.mtime), "dim" } }, w, function() U.open_file(f.path) end)
    end
    return out
  end,
}
