local function is_macos_dark()
  local handle = io.popen("defaults read -g AppleInterfaceStyle 2>/dev/null")
  local result = handle:read("*a")
  handle:close()
  return result:match("Dark") ~= nil
end

local current = nil
local function apply()
  local dark = is_macos_dark()
  if current == dark then return end
  current = dark
  if dark then
    vim.cmd.colorscheme("kanso-zen")
  else
    vim.cmd.colorscheme("kanso-pearl")
  end
end

apply()

-- re-check every 2 seconds
vim.fn.timer_start(2000, function() vim.schedule(apply) end, { ["repeat"] = -1 })
