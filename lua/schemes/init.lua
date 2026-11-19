-- In-repo colorschemes (concrete, graphite, paper, phosphor, phosphor-amber).
--
-- One builder, one palette file per scheme: `colors/<name>.lua` just calls
-- `require("schemes").load(name)`, which reads `lua/schemes/<name>.lua` and
-- paints every group from its palette. A palette returns
--   { dark = P, light = P }            (omit `light` for a dark-only scheme)
-- or a function(variant) returning that table. See `concrete.lua` for the
-- full list of roles.
--
-- Two things differ from a plugin theme:
--  * Normal's bg is left alone even in transparent mode. The strip autocmd in
--    defaults/init.lua records it as `g:scheme_bg` (Molten output, plot paper
--    and the cursorline blend are drawn on it) and then clears it, so setting
--    it NONE here would leave those with the fallback grey.
--  * 'background' is never written. A dark-only palette just keeps drawing
--    dark under "light" (like vesper), and ui_toggle.lua detects that from
--    Normal's luminance and undoes the switch with a warning.

local colors = require("defaults.colors")

local M = {}

local function int(hex) return tonumber(hex:sub(2), 16) end

-- Mix `a` into `b` by `t` (0..1); hex strings in, hex string out.
function M.mix(a, b, t) return colors.hex(colors.blend(int(a), int(b), t)) end

-- Contrast ratio (WCAG) of two hex colours; used by the test in scheme docs.
function M.contrast(a, b)
  local function lum(h)
    local c = int(h)
    local function lin(v)
      v = v / 255
      return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * lin(math.floor(c / 65536)) + 0.7152 * lin(math.floor(c / 256) % 256) + 0.0722 * lin(c % 256)
  end
  local la, lb = lum(a), lum(b)
  if la < lb then la, lb = lb, la end
  return (la + 0.05) / (lb + 0.05)
end

-- A syntax role: `{ fg = "#…", bold = true }`, or a bare colour string.
local function role(p, key)
  local r = p.syn[key] or p.fg
  if type(r) == "string" then r = { fg = r } end
  return vim.deepcopy(r)
end

local function groups(p)
  local mix = M.mix
  local bg = p.bg
  local s = function(k) return role(p, k) end
  local fgonly = function(c) return { fg = c } end
  local search_bg = p.search_bg or mix(p.accent, bg, 0.35)

  local g = {
    -- editor chrome -------------------------------------------------------
    Normal = { fg = p.fg, bg = bg },
    NormalNC = { fg = p.fg, bg = bg },
    NormalFloat = { fg = p.fg, bg = p.float },
    FloatBorder = { fg = p.line, bg = p.float },
    FloatTitle = { fg = p.accent, bg = p.float, bold = true },
    Cursor = { fg = bg, bg = p.fg },
    lCursor = { link = "Cursor" },
    TermCursor = { link = "Cursor" },
    CursorLine = { bg = p.sel },
    CursorColumn = { bg = p.sel },
    ColorColumn = { bg = p.sel },
    CursorLineNr = { fg = p.accent, bold = true },
    LineNr = { fg = p.dim },
    LineNrAbove = { fg = p.dim },
    LineNrBelow = { fg = p.dim },
    SignColumn = { fg = p.dim },
    FoldColumn = { fg = p.dim },
    Folded = { fg = p.dim, bg = p.sel },
    EndOfBuffer = { fg = bg },
    NonText = { fg = mix(p.dim, bg, 0.5) },
    Whitespace = { fg = mix(p.dim, bg, 0.5) },
    SpecialKey = { fg = mix(p.dim, bg, 0.5) },
    Conceal = { fg = p.dim },
    Visual = { bg = p.visual },
    VisualNOS = { bg = p.visual },
    Search = { fg = p.fg, bg = search_bg },
    IncSearch = { fg = bg, bg = p.accent, bold = true },
    CurSearch = { fg = bg, bg = p.accent, bold = true },
    Substitute = { fg = bg, bg = p.error },
    MatchParen = { bg = p.visual, bold = true },
    WinSeparator = { fg = p.line },
    VertSplit = { fg = p.line },
    StatusLine = { fg = p.fg, bg = p.float },
    StatusLineNC = { fg = p.dim, bg = p.float },
    TabLine = { fg = p.dim, bg = p.float },
    TabLineSel = { fg = p.fg, bg = bg, bold = true },
    TabLineFill = { bg = p.float },
    WinBar = { fg = p.fg },
    WinBarNC = { fg = p.dim },
    Pmenu = { fg = p.fg, bg = p.float },
    PmenuSel = { fg = p.fg, bg = p.visual, bold = true },
    PmenuSbar = { bg = p.sel },
    PmenuThumb = { bg = p.line },
    PmenuKind = { fg = p.dim, bg = p.float },
    PmenuExtra = { fg = p.dim, bg = p.float },
    WildMenu = { fg = p.fg, bg = p.visual },
    Directory = { fg = p.accent },
    Title = { fg = p.accent, bold = true },
    ErrorMsg = { fg = p.error, bold = true },
    WarningMsg = { fg = p.warn },
    ModeMsg = { fg = p.fg, bold = true },
    MoreMsg = { fg = p.ok },
    Question = { fg = p.ok },
    MsgArea = { fg = p.fg },
    QuickFixLine = { bg = p.visual, bold = true },
    SpellBad = { undercurl = true, sp = p.error },
    SpellCap = { undercurl = true, sp = p.warn },
    SpellRare = { undercurl = true, sp = p.info },
    SpellLocal = { undercurl = true, sp = p.hint },

    -- diff / git ----------------------------------------------------------
    DiffAdd = { bg = mix(p.add, bg, 0.18) },
    DiffDelete = { fg = mix(p.delete, bg, 0.6), bg = mix(p.delete, bg, 0.14) },
    DiffChange = { bg = mix(p.change, bg, 0.14) },
    DiffText = { bg = mix(p.change, bg, 0.34), bold = true },
    Added = { fg = p.add },
    Changed = { fg = p.change },
    Removed = { fg = p.delete },
    GitSignsAdd = { fg = p.add },
    GitSignsChange = { fg = p.change },
    GitSignsDelete = { fg = p.delete },
    GitSignsTopdelete = { fg = p.delete },
    GitSignsChangedelete = { fg = p.change },
    GitSignsUntracked = { fg = p.add },

    -- classic syntax ------------------------------------------------------
    Comment = s("comment"),
    Constant = s("constant"),
    String = s("string"),
    Character = s("string"),
    Number = s("number"),
    Boolean = s("constant"),
    Float = s("number"),
    Identifier = s("variable"),
    Function = s("func"),
    Statement = s("keyword"),
    Conditional = s("keyword"),
    Repeat = s("keyword"),
    Label = s("keyword"),
    Operator = s("operator"),
    Keyword = s("keyword"),
    Exception = s("keyword"),
    PreProc = s("preproc"),
    Include = s("preproc"),
    Define = s("preproc"),
    Macro = s("preproc"),
    PreCondit = s("preproc"),
    Type = s("type"),
    StorageClass = s("keyword"),
    Structure = s("type"),
    Typedef = s("type"),
    Special = s("special"),
    SpecialChar = s("special"),
    Tag = s("keyword"),
    Delimiter = s("delimiter"),
    SpecialComment = s("comment"),
    Debug = s("special"),
    Underlined = { fg = p.accent, underline = true },
    Error = { fg = p.error },
    Todo = { fg = bg, bg = p.accent, bold = true },

    -- treesitter (everything else falls through to the groups above) -------
    ["@variable"] = s("variable"),
    ["@variable.builtin"] = s("special"),
    ["@variable.parameter"] = s("param"),
    ["@variable.member"] = s("property"),
    ["@property"] = s("property"),
    ["@constant.builtin"] = s("constant"),
    ["@module"] = s("type"),
    ["@constructor"] = s("type"),
    ["@function.builtin"] = s("func"),
    ["@string.escape"] = s("special"),
    ["@punctuation.delimiter"] = s("delimiter"),
    ["@punctuation.bracket"] = s("delimiter"),
    ["@tag"] = s("keyword"),
    ["@tag.attribute"] = s("property"),
    ["@tag.delimiter"] = s("delimiter"),
    ["@comment.todo"] = { fg = bg, bg = p.accent, bold = true },
    ["@comment.warning"] = { fg = bg, bg = p.warn, bold = true },
    ["@comment.error"] = { fg = bg, bg = p.error, bold = true },
    ["@comment.note"] = { fg = bg, bg = p.info, bold = true },
    ["@markup.heading"] = { fg = p.accent, bold = true },
    ["@markup.strong"] = { bold = true },
    ["@markup.italic"] = { italic = true },
    ["@markup.strikethrough"] = { strikethrough = true },
    ["@markup.link"] = { fg = p.accent },
    ["@markup.link.url"] = { fg = p.dim, underline = true },
    ["@markup.raw"] = s("string"),
    ["@markup.list"] = { fg = p.accent },

    -- diagnostics / LSP ---------------------------------------------------
    DiagnosticError = fgonly(p.error),
    DiagnosticWarn = fgonly(p.warn),
    DiagnosticInfo = fgonly(p.info),
    DiagnosticHint = fgonly(p.hint),
    DiagnosticOk = fgonly(p.ok),
    DiagnosticVirtualTextError = fgonly(mix(p.error, bg, 0.75)),
    DiagnosticVirtualTextWarn = fgonly(mix(p.warn, bg, 0.75)),
    DiagnosticVirtualTextInfo = fgonly(mix(p.info, bg, 0.75)),
    DiagnosticVirtualTextHint = fgonly(mix(p.hint, bg, 0.75)),
    DiagnosticUnderlineError = { undercurl = true, sp = p.error },
    DiagnosticUnderlineWarn = { undercurl = true, sp = p.warn },
    DiagnosticUnderlineInfo = { undercurl = true, sp = p.info },
    DiagnosticUnderlineHint = { undercurl = true, sp = p.hint },
    DiagnosticUnnecessary = { fg = p.dim },
    DiagnosticDeprecated = { strikethrough = true },
    LspReferenceText = { bg = p.sel },
    LspReferenceRead = { bg = p.sel },
    LspReferenceWrite = { bg = p.sel, underline = true },
    LspInlayHint = { fg = p.dim },
    LspSignatureActiveParameter = { fg = p.accent, bold = true },

    -- plugins that read plain groups --------------------------------------
    TelescopeNormal = { fg = p.fg, bg = p.float },
    TelescopeBorder = { fg = p.line, bg = p.float },
    TelescopeTitle = { fg = p.accent, bold = true },
    TelescopePromptPrefix = { fg = p.accent },
    TelescopeSelection = { bg = p.sel, bold = true },
    TelescopeSelectionCaret = { fg = p.accent, bg = p.sel },
    TelescopeMatching = { fg = p.accent, bold = true },
    CmpItemAbbr = { fg = p.fg },
    CmpItemAbbrMatch = { fg = p.accent, bold = true },
    CmpItemAbbrMatchFuzzy = { fg = p.accent },
    CmpItemAbbrDeprecated = { fg = p.dim, strikethrough = true },
    CmpItemMenu = { fg = p.dim },
    CmpItemKind = { fg = role(p, "type").fg },
    WhichKey = { fg = p.accent },
    WhichKeyDesc = { fg = p.fg },
    WhichKeyGroup = { fg = role(p, "type").fg },
    WhichKeySeparator = { fg = p.dim },
    IblIndent = { fg = mix(p.line, bg, 0.45) },
    IblScope = { fg = p.line },
    MiniIndentscopeSymbol = { fg = p.line },
    IlluminatedWordText = { bg = p.sel },
    IlluminatedWordRead = { bg = p.sel },
    IlluminatedWordWrite = { bg = p.sel, underline = true },
    FlashLabel = { fg = bg, bg = p.accent, bold = true },
    FlashMatch = { fg = p.fg, bg = search_bg },
    FlashCurrent = { fg = bg, bg = p.accent },
    TodoBgTODO = { fg = bg, bg = p.accent, bold = true },
    TreesitterContext = { bg = p.sel },
    TreesitterContextBottom = { underline = true, sp = p.line },
  }

  for name, extra in pairs(p.extra or {}) do
    g[name] = extra
  end
  return g
end

-- The 16 ANSI slots for `:terminal` buffers (palette `term`, 16 hex strings).
local function terminal(p)
  for i, c in ipairs(p.term or {}) do
    vim.g["terminal_color_" .. (i - 1)] = c
  end
end

---@param name string       scheme name, also the palette module under lua/schemes/
---@param variant? string   passed to a palette function (phosphor's hue)
function M.load(name, variant)
  local mod = "schemes." .. name
  package.loaded[mod] = nil -- re-read on every load so palette edits show up
  local pal = require(mod)
  if type(pal) == "function" then pal = pal(variant) end
  local p = (vim.o.background == "light" and pal.light) or pal.dark

  vim.cmd("highlight clear")
  if vim.fn.exists("syntax_on") == 1 then vim.cmd("syntax reset") end
  vim.o.termguicolors = true
  vim.g.colors_name = variant and (name .. "-" .. variant) or name

  for group, spec in pairs(groups(p)) do
    vim.api.nvim_set_hl(0, group, spec)
  end
  terminal(p)
end

return M
