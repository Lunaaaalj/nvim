-- A scratch notes file (static.notes_file): its first lines, checkboxes dimmed
-- once ticked. <CR> opens it. Hidden when the file is missing or empty.
local U = require("header_art.static_util")

local function lines()
  local path = require("header_art.static").opts.notes_file
  if vim.fn.filereadable(path) == 0 then return {}, path end
  local out = {}
  for _, l in ipairs(vim.fn.readfile(path, "", 40)) do
    if l:match("%S") then out[#out + 1] = l end
    if #out >= 4 then break end
  end
  return out, path
end

return {
  id = "notes",
  title = "NOTES",
  on = { "BufWritePost" },
  available = function() return #lines() > 0 end,
  render = function(w)
    local ls, path = lines()
    local out = {}
    for _, l in ipairs(ls) do
      local done = l:match("^%s*[-*]%s*%[[xX]%]") ~= nil
      local open = l:match("^%s*[-*]%s*%[ %]") ~= nil
      local text = l:gsub("^%s*[-*]%s*%[.%]%s*", ""):gsub("^%s*[-*]%s*", ""):gsub("^#+%s*", "")
      local mark = (done and "[x] ") or (open and "[ ] ") or "    "
      out[#out + 1] = U.row({ { mark, done and "dim" or "acc" }, { text, done and "dim" or "" } }, {}, w, function() U.open_file(path) end)
    end
    return out
  end,
}
