-- Per-PDF view state (page, zoom, fit, spread, colours) remembered across
-- sessions in stdpath("state")/pdfview.json, keyed by the PDF path or the
-- viewer's `store_key` (a Markdown preview's source file). Writes are debounced.
-- Entries can carry fields of their own besides the view (a Markdown file's
-- `style`); keys starting with "_" hold settings and are never pruned.

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
  for pdf, e in pairs(data) do
    if pdf:sub(1, 1) ~= "_" then list[#list + 1] = { pdf, e.t or 0 } end
  end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  for i = MAX_ENTRIES + 1, #list do data[list[i][1]] = nil end
  pcall(vim.fn.writefile, { vim.json.encode(data) }, file)
end

function M.restore(v)
  local e = load()[v.store_key or v.pdf]
  if not e then return end
  for _, f in ipairs(FIELDS) do
    if e[f] ~= nil and e[f] ~= vim.NIL then v[f] = e[f] end
  end
end

local function schedule() timer:start(1000, 0, vim.schedule_wrap(M.flush)) end

function M.save(v)
  local key = v.store_key or v.pdf
  local e = load()[key] or {} -- keep fields that aren't the view's
  e.t = os.time()
  for _, f in ipairs(FIELDS) do e[f] = v[f] end
  load()[key] = e
  schedule()
end

-- One field of an entry (`key` = a PDF path, a store_key, or "_name").
function M.get(key, field)
  local e = load()[key]
  local val = e and e[field]
  if val == vim.NIL then return nil end
  return val
end

function M.set(key, field, value)
  local e = load()[key] or {}
  e[field] = value
  if key:sub(1, 1) ~= "_" then e.t = os.time() end
  load()[key] = e
  schedule()
end

return M
