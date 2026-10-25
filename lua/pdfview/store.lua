-- Per-PDF view state (page, zoom, fit, spread, colours) remembered across
-- sessions in stdpath("state")/pdfview.json. Writes are debounced.

local M = {}

local file = vim.fn.stdpath("state") .. "/pdfview.json"
local FIELDS = { "page", "fit", "zoom", "vx", "vy", "spread", "colors" }
local MAX_ENTRIES = 300

local data ---@type table<string, table>?
local timer = assert(vim.uv.new_timer())

local function load()
  if data then return data end
  local ok, decoded = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
  end)
  data = ok and type(decoded) == "table" and decoded or {}
  return data
end

function M.flush()
  timer:stop()
  if not data then return end
  local list = {}
  for pdf, e in pairs(data) do list[#list + 1] = { pdf, e.t or 0 } end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  for i = MAX_ENTRIES + 1, #list do data[list[i][1]] = nil end
  pcall(vim.fn.writefile, { vim.json.encode(data) }, file)
end

function M.restore(v)
  local e = load()[v.pdf]
  if not e then return end
  for _, f in ipairs(FIELDS) do
    if e[f] ~= nil and e[f] ~= vim.NIL then v[f] = e[f] end
  end
end

function M.save(v)
  local e = { t = os.time() }
  for _, f in ipairs(FIELDS) do e[f] = v[f] end
  load()[v.pdf] = e
  timer:start(1000, 0, vim.schedule_wrap(M.flush))
end

return M
