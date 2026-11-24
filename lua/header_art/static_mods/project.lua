-- Project card: cwd, branch and the last commit, from .git files (no process).
local U = require("header_art.static_util")

return {
  id = "project",
  title = "PROJECT",
  on = { "DirChanged", "BufWritePost" },
  render = function(w)
    local D = require("header_art.hud_data").sample()
    return {
      U.row({ { vim.fn.fnamemodify(D.cwd or "", ":t"), "b acc" }, { "  " .. (D.cwd or ""), "dim" } }, {}, w),
      U.row({ { D.branch or "no branch", "mid" } }, { { D.head and D.head:sub(1, 7) or "", "dim" } }, w),
    }
  end,
}
