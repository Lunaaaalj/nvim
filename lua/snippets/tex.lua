local ls = require("luasnip")
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local d = ls.dynamic_node
local c = ls.choice_node
local fmta = require("luasnip.extras.fmt").fmta
local rep = require("luasnip.extras").rep

-- ── Math-zone detection (VimTeX) ─────────────────────────────────
local function in_mathzone()
    return vim.fn["vimtex#syntax#in_mathzone"]() == 1
end

local function in_text()
    return not in_mathzone()
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
    opts = opts or {}
    return s(vim.tbl_extend("force", {
        trig = trig,
        snippetType = "autosnippet",
        condition = in_mathzone,
        wordTrig = false,
    }, opts), nodes)
end

local function math_auto_re(trig, nodes, opts)
    opts = opts or {}
    return s(vim.tbl_extend("force", {
        trig = trig,
        snippetType = "autosnippet",
        condition = in_mathzone,
        wordTrig = false,
        trigEngine = "ecma",
    }, opts), nodes)
end

-- ═════════════════════════════════════════════════════════════════
-- REGULAR SNIPPETS (Tab / cmp triggered)
-- ═════════════════════════════════════════════════════════════════
local snippets = {

    -- ── A. Boilerplate ───────────────────────────────────────────

    s("template", fmta(
        [[
\documentclass{<>}
\usepackage[utf8]{inputenc}
\usepackage{amsmath,amssymb,amsthm}
\usepackage{graphicx}
\usepackage{hyperref}

\title{<>}
\author{<>}
\date{<>}

\begin{document}
\maketitle

<>

\end{document}
        ]],
        { c(1, { t("article"), t("report"), t("beamer") }), i(2, "Title"), i(3, "Author"), i(4, "\\today"), i(0) }
    )),

    s("beg", fmta(
        [[
\begin{<>}
    <>
\end{<>}
        ]],
        { i(1), i(0), rep(1) }
    )),

    s("fig", fmta(
        [[
\begin{figure}[<>]
    \centering
    \includegraphics[width=<>\textwidth]{<>}
    \caption{<>}
    \label{fig:<>}
\end{figure}
        ]],
        { i(1, "htbp"), i(2, "0.8"), i(3), i(4), i(5) }
    )),

    s("tab", fmta(
        [[
\begin{table}[<>]
    \centering
    \begin{tabular}{<>}
        \hline
        <>
        \hline
    \end{tabular}
    \caption{<>}
    \label{tab:<>}
\end{table}
        ]],
        { i(1, "htbp"), i(2, "c c c"), i(3), i(4), i(5) }
    )),

    s("enum", fmta(
        [[
\begin{enumerate}
    \item <>
\end{enumerate}
        ]],
        { i(0) }
    )),

    s("item", fmta(
        [[
\begin{itemize}
    \item <>
\end{itemize}
        ]],
        { i(0) }
    )),

    s("ali", fmta(
        [[
\begin{align*}
    <>
\end{align*}
        ]],
        { i(0) }
    )),

    s("eqn", fmta(
        [[
\begin{equation}
    <>
\end{equation}
        ]],
        { i(0) }
    )),

    s("sec", fmta([[\section{<>}]], { i(0) })),
    s("ssec", fmta([[\subsection{<>}]], { i(0) })),
    s("sssec", fmta([[\subsubsection{<>}]], { i(0) })),
    s("chap", fmta([[\chapter{<>}]], { i(0) })),
    s("pkg", fmta([[\usepackage{<>}]], { i(0) })),

    -- ── H. Matrix environments ───────────────────────────────────
    s("pmat", fmta(
        [[
\begin{pmatrix}
    <>
\end{pmatrix}
        ]],
        { i(0) }
    )),

    s("bmat", fmta(
        [[
\begin{bmatrix}
    <>
\end{bmatrix}
        ]],
        { i(0) }
    )),

    s("vmat", fmta(
        [[
\begin{vmatrix}
    <>
\end{vmatrix}
        ]],
        { i(0) }
    )),
}

-- ═════════════════════════════════════════════════════════════════
-- AUTOSNIPPETS
-- ═════════════════════════════════════════════════════════════════
local autosnippets = {

    -- ── B. Math mode entry (text-mode only) ──────────────────────
    auto("mk", fmta("$<>$", { i(1) }), { condition = in_text, wordTrig = true }),
    auto("dm", fmta(
        [[
\[
    <>
\]
        ]],
        { i(1) }
    ), { condition = in_text, wordTrig = true }),

    auto("aln", fmta(
        [[
\begin{<>}
    <>
\end{<>}
        ]],
        { c(1, { t("align*"), t("align") }), i(2), c(3, { t("align*"), t("align") }) }
    ), { condition = in_text, wordTrig = true }),

    -- ── C. Fractions ─────────────────────────────────────────────
    math_auto("//", fmta([[\frac{<>}{<>}]], { i(1), i(2) })),

    -- Smart fraction: word before / becomes numerator (e.g. "x/" → "\frac{x}{}")
    math_auto_re("([A-Za-z0-9]+)/", {
        f(function(_, snip) return "\\frac{" .. snip.captures[1] .. "}{" end),
        i(1),
        t("}"),
    }),

    -- ── D. Subscript / Superscript ───────────────────────────────
    -- Auto-subscript: x2 → x_{2}
    math_auto_re("([A-Za-z])(%d)", {
        f(function(_, snip) return snip.captures[1] .. "_{" .. snip.captures[2] .. "}" end),
    }),

    math_auto("__", fmta("_{<>}", { i(1) })),
    math_auto("td", fmta("^{<>}", { i(1) })),
    math_auto("sr", { t("^{2}") }),
    math_auto("cb", { t("^{3}") }),
    math_auto("invs", { t("^{-1}") }),
    math_auto("compl", { t("^{c}") }),

    -- ── F. Operators ─────────────────────────────────────────────
    math_auto("sum", fmta([[\sum_{<>}^{<>}]], { i(1, "i=1"), i(2, "n") }), { wordTrig = true }),
    math_auto("prod", fmta([[\prod_{<>}^{<>}]], { i(1, "i=1"), i(2, "n") }), { wordTrig = true }),
    math_auto("lim", fmta([[\lim_{<> \to <>}]], { i(1, "n"), i(2, "\\infty") }), { wordTrig = true }),
    math_auto("dint", fmta([[\int_{<>}^{<>} <>]], { i(1, "-\\infty"), i(2, "\\infty"), i(3) }), { wordTrig = true }),

    -- ── G. Delimiters ────────────────────────────────────────────
    math_auto("lr(", fmta([[\left( <> \right)]], { i(1) })),
    math_auto("lr[", fmta([=[\left[ <> \right]]=], { i(1) })),
    math_auto("lr|", fmta([[\left| <> \right|]], { i(1) })),
    math_auto("lra", fmta([[\left\langle <> \right\rangle]], { i(1) })),
    math_auto("lr{", fmta([[\left\{ <> \right\}]], { i(1) })),

    -- ── H. Arrows & Relations ────────────────────────────────────
    math_auto("->", { t("\\to ") }),
    math_auto("!>", { t("\\mapsto ") }),
    math_auto("=>", { t("\\implies ") }),
    math_auto("=<", { t("\\impliedby ") }),
    math_auto("iff", { t("\\iff ") }, { wordTrig = true }),
    math_auto("<=", { t("\\leq ") }),
    math_auto(">=", { t("\\geq ") }),
    math_auto("!=", { t("\\neq ") }),
    math_auto("~~", { t("\\approx ") }),
    math_auto("~=", { t("\\cong ") }),
    math_auto(">>", { t("\\gg ") }),
    math_auto("<<", { t("\\ll ") }),
    math_auto("inn", { t("\\in ") }, { wordTrig = true }),
    math_auto("notin", { t("\\notin ") }, { wordTrig = true }),
    math_auto("sub=", { t("\\subseteq ") }),
    math_auto("sup=", { t("\\supseteq ") }),

    -- ── I. Common Symbols ────────────────────────────────────────
    math_auto("ooo", { t("\\infty") }),
    math_auto("...", { t("\\ldots") }),
    math_auto("c..", { t("\\cdots") }),
    math_auto("v..", { t("\\vdots") }),
    math_auto("d..", { t("\\ddots") }),
    math_auto("xx", { t("\\times ") }),
    math_auto("**", { t("\\cdot ") }),
    math_auto("||", { t("\\mid ") }),
    math_auto("AA", { t("\\forall ") }),
    math_auto("EE", { t("\\exists ") }),
    math_auto("nn", { t("\\cap ") }),
    math_auto("uu", { t("\\cup ") }),
    math_auto("OO", { t("\\emptyset") }),
    math_auto("RR", { t("\\mathbb{R}") }),
    math_auto("QQ", { t("\\mathbb{Q}") }),
    math_auto("ZZ", { t("\\mathbb{Z}") }),
    math_auto("NN", { t("\\mathbb{N}") }),
    math_auto("CC", { t("\\mathbb{C}") }),
    math_auto("FF", { t("\\mathbb{F}") }),
    math_auto("nabl", { t("\\nabla") }),
    math_auto("del", { t("\\partial") }, { wordTrig = true }),

    -- ── J. Decorations (postfix: xhat → \hat{x}) ────────────────
    math_auto_re("([A-Za-z])hat", {
        f(function(_, snip) return "\\hat{" .. snip.captures[1] .. "}" end),
    }),
    math_auto_re("([A-Za-z])bar", {
        f(function(_, snip) return "\\bar{" .. snip.captures[1] .. "}" end),
    }),
    math_auto_re("([A-Za-z])tld", {
        f(function(_, snip) return "\\tilde{" .. snip.captures[1] .. "}" end),
    }),
    math_auto_re("([A-Za-z])vec", {
        f(function(_, snip) return "\\vec{" .. snip.captures[1] .. "}" end),
    }),
    math_auto_re("([A-Za-z])dot", {
        f(function(_, snip) return "\\dot{" .. snip.captures[1] .. "}" end),
    }),

    -- ── K. Misc Math ─────────────────────────────────────────────
    math_auto("sq", fmta([[\sqrt{<>}]], { i(1) })),
    math_auto("tt", fmta([[\text{<>}]], { i(1) })),
    math_auto("bf", fmta([[\mathbf{<>}]], { i(1) })),
    math_auto("cal", fmta([[\mathcal{<>}]], { i(1) })),
    math_auto("scr", fmta([[\mathscr{<>}]], { i(1) })),
    math_auto("frak", fmta([[\mathfrak{<>}]], { i(1) })),
    math_auto("ol", fmta([[\overline{<>}]], { i(1) })),
    math_auto("ul", fmta([[\underline{<>}]], { i(1) })),

    -- Partial derivative
    math_auto("par", fmta([[\frac{\partial <>}{\partial <>}]], { i(1), i(2) }), { wordTrig = true }),
    math_auto("ddt", { t("\\frac{d}{dt}") }, { wordTrig = true }),
    math_auto("ddx", { t("\\frac{d}{dx}") }, { wordTrig = true }),
}

-- ── E. Greek letters (loop-generated, auto, math mode) ───────────
local greek = {
    -- lowercase
    { "a", "\\alpha" },
    { "b", "\\beta" },
    { "g", "\\gamma" },
    { "d", "\\delta" },
    { "e", "\\epsilon" },
    { "ve", "\\varepsilon" },
    { "z", "\\zeta" },
    { "h", "\\eta" },
    { "q", "\\theta" },
    { "vq", "\\vartheta" },
    { "i", "\\iota" },
    { "k", "\\kappa" },
    { "l", "\\lambda" },
    { "m", "\\mu" },
    { "n", "\\nu" },
    { "x", "\\xi" },
    { "p", "\\pi" },
    { "vp", "\\varpi" },
    { "r", "\\rho" },
    { "s", "\\sigma" },
    { "t", "\\tau" },
    { "u", "\\upsilon" },
    { "f", "\\phi" },
    { "vf", "\\varphi" },
    { "c", "\\chi" },
    { "y", "\\psi" },
    { "w", "\\omega" },
    -- uppercase
    { "G", "\\Gamma" },
    { "D", "\\Delta" },
    { "Q", "\\Theta" },
    { "L", "\\Lambda" },
    { "X", "\\Xi" },
    { "P", "\\Pi" },
    { "S", "\\Sigma" },
    { "U", "\\Upsilon" },
    { "F", "\\Phi" },
    { "Y", "\\Psi" },
    { "W", "\\Omega" },
}

for _, pair in ipairs(greek) do
    table.insert(autosnippets, math_auto("@" .. pair[1], { t(pair[2]) }))
end

return snippets, autosnippets
