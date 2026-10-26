-- Typst snippets: the TeX set's triggers where they still make sense, made
-- lighter because Typst math already is. Native shorthands need no snippet
-- (`->`, `=>`, `<=`, `>=`, `!=`, `...`, `oo`, `RR`, and `x/y` is already a
-- fraction), and math is written in plain words (`delta`, `sqrt`, `liminf`,
-- `complement`, `parallel`, `odot`), so no autosnippet may be a prefix of one:
-- that rules out the TeX set's del/sq/lim/compl/par/dot (and `inn`, which
-- would also end in `nn`; `in` is native anyway). Limits and sums are
-- Tab snippets instead. Names are typst 0.15's (`partial`, not `diff`;
-- `product`, not `prod`; `chevron.l`, not `angle.l`).
local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local fmta = require("luasnip.extras.fmt").fmta

-- ── Math-zone detection (treesitter) ─────────────────────────────
-- Inside a `math` node, strictly between its `$`s (so not right after the
-- closing one), and not inside a "string" in it.
local function in_math()
    local ok, parser = pcall(vim.treesitter.get_parser, 0, "typst")
    if not ok or not parser then return false end
    parser:parse()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    row = row - 1
    local node = vim.treesitter.get_node({ bufnr = 0, pos = { row, math.max(col - 1, 0) } })
    -- at column 0 get_node returns the root even when a `$` starts the line
    if node and not node:parent() then node = vim.treesitter.get_node({ bufnr = 0, pos = { row, col } }) end
    while node do
        local kind = node:type()
        if kind == "string" then return false end
        if kind == "math" then
            local r1, c1, r2, c2 = node:range()
            return (row > r1 or col > c1) and (row < r2 or col < c2)
        end
        node = node:parent()
    end
    return false
end

local function in_text()
    return not in_math()
end

-- ── Snippet constructors ─────────────────────────────────────────
local function auto(trig, nodes, opts)
    opts = opts or {}
    return s(vim.tbl_extend("force", {
        trig = trig,
        snippetType = "autosnippet",
        wordTrig = false,
    }, opts), nodes)
end

local function math_auto(trig, nodes, opts)
    return auto(trig, nodes, vim.tbl_extend("force", { condition = in_math }, opts or {}))
end

local function math_auto_re(trig, nodes, opts)
    return math_auto(trig, nodes, vim.tbl_extend("force", { regTrig = true, trigEngine = "pattern" }, opts or {}))
end

local function math_snip(trig, nodes)
    return s({ trig = trig, condition = in_math, show_condition = in_math }, nodes)
end

-- ═════════════════════════════════════════════════════════════════
-- REGULAR SNIPPETS (Tab / cmp triggered)
-- ═════════════════════════════════════════════════════════════════
local snippets = {

    -- ── A. Boilerplate ───────────────────────────────────────────
    -- (for a journal or report layout, start from a template: <leader>ln)
    s("template", fmta(
        [[
#set document(title: [<>], author: "<>")
#set page(paper: "<>", numbering: "1")
#set text(size: 11pt, lang: "<>")
#set heading(numbering: "1.")
#set math.equation(numbering: "(1)")

#align(center, text(17pt, weight: "bold")[<>])

<>
        ]],
        { i(1, "Title"), i(2, "Author"), c(3, { t("a4"), t("us-letter") }), c(4, { t("en"), t("es") }), f(function(args)
            return args[1][1]
        end, { 1 }), i(0) }
    )),

    s("fig", fmta(
        [[
#figure(
  image("<>", width: <>%),
  caption: [<>],
) <<fig:<>>>
        ]],
        { i(1), i(2, "80"), i(3), i(4) }
    )),

    s("tab", fmta(
        [[
#figure(
  table(
    columns: <>,
    table.header(<>),
    <>
  ),
  caption: [<>],
) <<tab:<>>>
        ]],
        { i(1, "3"), i(2, "[*A*], [*B*], [*C*]"), i(3), i(4), i(5) }
    )),

    s("grid", fmta(
        [[
#grid(
  columns: (1fr, 1fr),
  gutter: 1em,
  [<>],
  [<>],
)
        ]],
        { i(1), i(2) }
    )),

    s("eqn", fmta(
        [[
$
  <>
$ <<eq:<>>>
        ]],
        { i(1), i(2) }
    )),

    s("code", fmta(
        [[
```<>
<>
```
        ]],
        { i(1, "python"), i(0) }
    )),

    s("link", fmta([=[#link("<>")[<>]]=], { i(1, "https://"), i(2) })),
    s("fn", fmta([=[#footnote[<>]]=], { i(1) })),
    s("bib", fmta([[#bibliography("<>")]], { i(1, "refs.bib") })),
    s("note", fmta(
        [[
#block(fill: luma(240), inset: 8pt, radius: 4pt, width: 100%)[
  <>
]
        ]],
        { i(0) }
    )),

    -- ── F. Big operators with limits (math; Tab, not auto) ───────
    math_snip("sum", fmta([[sum_(<>)^(<>) ]], { i(1, "i=1"), i(2, "n") })),
    math_snip("prod", fmta([[product_(<>)^(<>) ]], { i(1, "i=1"), i(2, "n") })),
    math_snip("lim", fmta([[lim_(<> ->> <>) ]], { i(1, "n"), i(2, "oo") })),
    math_snip("dint", fmta([[integral_(<>)^(<>) <> dif <>]], { i(1, "-oo"), i(2, "oo"), i(3), i(4, "x") })),

    -- ── H. Matrices and cases (math) ─────────────────────────────
    math_snip("pmat", fmta([[mat(<>)]], { i(1, "a, b; c, d") })),
    math_snip("bmat", fmta([[mat(delim: "[", <>)]], { i(1, "a, b; c, d") })),
    math_snip("vmat", fmta([[mat(delim: "|", <>)]], { i(1, "a, b; c, d") })),
    math_snip("cases", fmta([[cases(<> &"if" <>, <> &"otherwise")]], { i(1), i(2), i(3) })),
}

-- ═════════════════════════════════════════════════════════════════
-- AUTOSNIPPETS
-- ═════════════════════════════════════════════════════════════════
local autosnippets = {

    -- ── B. Math mode entry (text only) ───────────────────────────
    auto("mk", fmta("$<>$", { i(1) }), { condition = in_text, wordTrig = true }),
    auto("dm", fmta(
        [[
$
  <>
$
        ]],
        { i(1) }
    ), { condition = in_text, wordTrig = true }),

    -- ── C. Fractions (`x/y` is native; this is for longer ones) ──
    math_auto("//", fmta([[frac(<>, <>)]], { i(1), i(2) })),

    -- ── D. Subscript / superscript ───────────────────────────────
    -- x2 -> x_2
    math_auto_re("(%a)(%d)", {
        f(function(_, snip) return snip.captures[1] .. "_" .. snip.captures[2] end),
    }),
    math_auto("__", fmta("_(<>)", { i(1) })),
    math_auto("td", fmta("^(<>)", { i(1) })),
    math_auto("sr", { t("^2") }),
    math_auto("cb", { t("^3") }),
    math_auto("invs", { t("^(-1)") }),

    -- ── G. Delimiters (parentheses scale on their own) ───────────
    math_auto("lr|", fmta([[abs(<>)]], { i(1) })),
    math_auto("nrm", fmta([[norm(<>)]], { i(1) })),
    math_auto("lra", fmta([[chevron.l <> chevron.r]], { i(1) })),

    -- ── H. Relations without a native shorthand ──────────────────
    math_auto("~~", { t("approx ") }),
    math_auto("sub=", { t("subset.eq ") }),
    math_auto("sup=", { t("supset.eq ") }),
    math_auto("notin", { t("in.not ") }, { wordTrig = true }),

    -- ── I. Symbols ───────────────────────────────────────────────
    math_auto("c..", { t("dots.c") }),
    math_auto("v..", { t("dots.v") }),
    math_auto("d..", { t("dots.down") }),
    math_auto("xx", { t("times ") }),
    math_auto("**", { t("dot.op ") }),
    math_auto("nn", { t("inter ") }),
    math_auto("uu", { t("union ") }),

    -- ── J. Decorations (postfix: xhat -> hat(x)) ─────────────────
    math_auto_re("(%a)hat", { f(function(_, snip) return "hat(" .. snip.captures[1] .. ")" end) }),
    math_auto_re("(%a)bar", { f(function(_, snip) return "overline(" .. snip.captures[1] .. ")" end) }),
    math_auto_re("(%a)tld", { f(function(_, snip) return "tilde(" .. snip.captures[1] .. ")" end) }),
    math_auto_re("(%a)vec", { f(function(_, snip) return "arrow(" .. snip.captures[1] .. ")" end) }),

    -- ── K. Misc math ─────────────────────────────────────────────
    math_auto("bf", fmta([[bold(<>)]], { i(1) })),
    math_auto("pdv", fmta([[(partial <>)/(partial <>)]], { i(1), i(2) }), { wordTrig = true }),
    math_auto("ddt", { t("(dif)/(dif t)") }, { wordTrig = true }),
    math_auto("ddx", { t("(dif)/(dif x)") }, { wordTrig = true }),
}

-- ── E. Greek letters (@a -> alpha; Typst names, math only) ───────
local greek = {
    -- lowercase
    { "a", "alpha" },
    { "b", "beta" },
    { "g", "gamma" },
    { "d", "delta" },
    { "e", "epsilon" },
    { "ve", "epsilon.alt" },
    { "z", "zeta" },
    { "h", "eta" },
    { "q", "theta" },
    { "vq", "theta.alt" },
    { "i", "iota" },
    { "k", "kappa" },
    { "l", "lambda" },
    { "m", "mu" },
    { "n", "nu" },
    { "x", "xi" },
    { "p", "pi" },
    { "vp", "pi.alt" },
    { "r", "rho" },
    { "s", "sigma" },
    { "t", "tau" },
    { "u", "upsilon" },
    { "f", "phi" },
    { "vf", "phi.alt" },
    { "c", "chi" },
    { "y", "psi" },
    { "w", "omega" },
    -- uppercase
    { "G", "Gamma" },
    { "D", "Delta" },
    { "Q", "Theta" },
    { "L", "Lambda" },
    { "X", "Xi" },
    { "P", "Pi" },
    { "S", "Sigma" },
    { "U", "Upsilon" },
    { "F", "Phi" },
    { "Y", "Psi" },
    { "W", "Omega" },
}

for _, pair in ipairs(greek) do
    table.insert(autosnippets, math_auto("@" .. pair[1], { t(pair[2] .. " ") }))
end

return snippets, autosnippets
