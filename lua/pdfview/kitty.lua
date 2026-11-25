-- A flicker-free image surface for a viewer buffer, on kitty's Unicode
-- placeholders (the same mechanism snacks.image uses, minus its lifecycle).
--
-- snacks.image.buf.attach() tears the old placement down (`placement.clean`)
-- before it has even identified the new PNG, and shows a "loading" spinner
-- meanwhile: every re-render went image -> blank -> image. Here the buffer
-- holds one placeholder grid for good; its colour (fg = image id, underline =
-- placement id) says which image the terminal draws in it. A new frame is
-- transmitted under a fresh id with its own virtual placement, and flipping the
-- highlight moves every cell to it in a single redraw. The previous image is
-- freed (`d=I`) a moment later, so kitty never accumulates them either.

local K = {}
K.delay = 30 -- ms between transmitting a frame and flipping to it (kitty decodes the PNG meanwhile)
K.free_after = 120 -- ms the replaced image lives on, so the flip's redraw lands first

local ns = vim.api.nvim_create_namespace("pdfview.kitty")
local PLACEHOLDER = vim.fn.nr2char(0x10EEEE)
local PID = 1 -- the placement id; one per surface is enough, every frame is its own image
-- kitty's rowcolumn-diacritics: the Nth one encodes row/column N
-- stylua: ignore
local diacritics = vim.split("0305,030D,030E,0310,0312,033D,033E,033F,0346,034A,034B,034C,0350,0351,0352,0357,035B,0363,0364,0365,0366,0367,0368,0369,036A,036B,036C,036D,036E,036F,0483,0484,0485,0486,0487,0592,0593,0594,0595,0597,0598,0599,059C,059D,059E,059F,05A0,05A1,05A8,05A9,05AB,05AC,05AF,05C4,0610,0611,0612,0613,0614,0615,0616,0617,0657,0658,0659,065A,065B,065D,065E,06D6,06D7,06D8,06D9,06DA,06DB,06DC,06DF,06E0,06E1,06E2,06E4,06E7,06E8,06EB,06EC,0730,0732,0733,0735,0736,073A,073D,073F,0740,0741,0743,0745,0747,0749,074A,07EB,07EC,07ED,07EE,07EF,07F0,07F1,07F3,0816,0817,0818,0819,081B,081C,081D,081E,081F,0820,0821,0822,0823,0825,0826,0827,0829,082A,082B,082C,082D,0951,0953,0954,0F82,0F83,0F86,0F87,135D,135E,135F,17DD,193A,1A17,1A75,1A76,1A77,1A78,1A79,1A7A,1A7B,1A7C,1B6B,1B6D,1B6E,1B6F,1B70,1B71,1B72,1B73,1CD0,1CD1,1CD2,1CDA,1CDB,1CE0,1DC0,1DC1,1DC3,1DC4,1DC5,1DC6,1DC7,1DC8,1DC9,1DCB,1DCC,1DD1,1DD2,1DD3,1DD4,1DD5,1DD6,1DD7,1DD8,1DD9,1DDA,1DDB,1DDC,1DDD,1DDE,1DDF,1DE0,1DE1,1DE2,1DE3,1DE4,1DE5,1DE6,1DFE,20D0,20D1,20D4,20D5,20D6,20D7,20DB,20DC,20E1,20E7,20E9,20F0,2CEF,2CF0,2CF1,2DE0,2DE1,2DE2,2DE3,2DE4,2DE5,2DE6,2DE7,2DE8,2DE9,2DEA,2DEB,2DEC,2DED,2DEE,2DEF,2DF0,2DF1,2DF2,2DF3,2DF4,2DF5,2DF6,2DF7,2DF8,2DF9,2DFA,2DFB,2DFC,2DFD,2DFE,2DFF,A66F,A67C,A67D,A6F0,A6F1,A8E0,A8E1,A8E2,A8E3,A8E4,A8E5,A8E6,A8E7,A8E8,A8E9,A8EA,A8EB,A8EC,A8ED,A8EE,A8EF,A8F0,A8F1,AAB0,AAB2,AAB3,AAB7,AAB8,AABE,AABF,AAC1,FE20,FE21,FE22,FE23,FE24,FE25,FE26,10A0F,10A38,1D185,1D186,1D187,1D188,1D189,1D1AA,1D1AB,1D1AC,1D1AD,1D242,1D243,1D244", ",")
local marks = {}
for i, cp in ipairs(diacritics) do marks[i] = vim.fn.nr2char(tonumber(cp, 16)) end
K.max = #marks

-- snacks numbers its images `(nvim hash << 14) | n` with n counting up from 30.
-- Ours use the top of that range (n >= 0x3000), so the two never meet.
local counter = 0
local function next_id()
  counter = counter + 1
  local lo = 0x3000 + counter % 0x1000
  local hi = math.floor(counter / 0x1000) % 0x400
  return hi * 0x4000 + lo
end

local function request(opts)
  Snacks.image.terminal.request(opts)
end

local function free(id)
  request({ a = "d", d = "I", i = id })
end

---@type table<integer, table>
local surfaces = {}

local S = {}
S.__index = S

-- Placeholders only work in kitty-like terminals and not over ssh (the image
-- file has to be readable by the terminal).
function K.supported()
  if not (_G.Snacks and Snacks.image and Snacks.image.terminal) then return false end
  local ok, env = pcall(Snacks.image.terminal.env)
  return ok and env.placeholders == true and not env.remote
end

---@param buf integer
function K.new(buf)
  if surfaces[buf] then return surfaces[buf] end
  local self = setmetatable({ buf = buf, hl = "PdfViewImg" .. buf }, S)
  surfaces[buf] = self
  vim.bo[buf].undolevels = -1
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "image" -- keeps cursorline & friends off (cursorline.lua's skip_ft)
  return self
end

-- The buffer text: `rows` lines of `cols` placeholder cells, each tagged with
-- its row and column. Rebuilt only when the window's size in cells changes.
function S:grid(cols, rows)
  local lines = {}
  for r = 1, rows do
    local cells = {}
    for c = 1, cols do cells[c] = PLACEHOLDER .. marks[r] .. marks[c] end
    lines[r] = table.concat(cells)
  end
  local b = vim.bo[self.buf]
  b.modifiable = true
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  b.modifiable, b.modified = false, false
  vim.api.nvim_buf_clear_namespace(self.buf, ns, 0, -1)
  for r = 1, rows do
    vim.api.nvim_buf_set_extmark(self.buf, ns, r - 1, 0, { end_col = #lines[r], hl_group = self.hl })
  end
  self.cols, self.rows = cols, rows
end

function S:color()
  if not self.id then return end
  vim.api.nvim_set_hl(0, self.hl, { fg = self.id, sp = PID, bg = "NONE", nocombine = true })
end

local function drop_later(id)
  vim.defer_fn(function() free(id) end, K.free_after)
end

-- Show a frame in the buffer: `file` holds raw 8-bit RGBA, `w` x `h` pixels
-- (exactly cols x rows cells, so the terminal maps it 1:1; no PNG to encode
-- here or decode there).
function S:show(file, cols, rows, w, h)
  if self.closed then return end
  cols, rows = math.min(cols, K.max), math.min(rows, K.max)
  if cols ~= self.cols or rows ~= self.rows then self:grid(cols, rows) end
  -- a frame still waiting to be flipped to was never seen: drop it
  if self.pending then
    self.pending.timer:stop()
    self.pending.timer:close()
    free(self.pending.id)
    self.pending = nil
  end
  local id = next_id()
  request({ a = "t", t = "f", f = 32, s = w, v = h, i = id, data = Snacks.util.base64(file) })
  request({ a = "p", U = 1, i = id, p = PID, c = cols, r = rows, C = 1 })
  local timer = assert(vim.uv.new_timer())
  self.pending = { id = id, timer = timer }
  timer:start(K.delay, 0, vim.schedule_wrap(function()
    if self.pending and self.pending.id == id then
      self.pending = nil
      timer:close()
    else
      return
    end
    if self.closed then return free(id) end
    local old = self.id
    self.id = id
    self:color()
    if old then drop_later(old) end
  end))
end

function S:close()
  if self.closed then return end
  self.closed = true
  surfaces[self.buf] = nil
  if self.pending then
    self.pending.timer:stop()
    self.pending.timer:close()
    free(self.pending.id)
    self.pending = nil
  end
  if self.id then free(self.id) end
end

-- `:colorscheme` clears highlight groups it doesn't know: put ours back.
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("pdfview.kitty", { clear = true }),
  callback = function()
    for _, s in pairs(surfaces) do s:color() end
  end,
})

return K
