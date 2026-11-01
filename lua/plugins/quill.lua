-- quill.nvim: spell audit (<leader>sa) and the Claude writing companion
-- (<leader>W: grammar, STYLE.md check, rigor review, reverse outline,
-- rewrite/ask/chat, later list, model picker). In every walk, `l` leaves an
-- issue for later and `t` talks about a finding.
-- Developed in its own repo; see its README / :help quill. The Lua module is
-- `writing`, so `:checkhealth writing`.
--
-- Glue that lives here, not in the plugin: theme-derived colours (through
-- defaults/colors.lua; `highlights` is a function the plugin re-runs on every
-- ColorScheme), the chat through lua/claude_chats (so it gets the IDE env and
-- shows in the neo-tree Claude tab), and the Spanish rewrite preset. The
-- filetypes `spellaudit` and `writingoutline` are in cursorline.lua's
-- `unmanaged_ft`; the which-key group and the cheatsheet entries stay in
-- their own files.

local function highlights()
    local colors = require("defaults.colors")
    local acc = colors.accent()
    local bg = vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false }).bg
        or vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
        or tonumber(colors.terminal_bg:sub(2), 16)
    local muted = colors.fg("Comment")
    local warn = colors.fg("DiagnosticWarn", "WarningMsg")
    return {
        SpellAuditAccent = { fg = acc },
        SpellAuditTitle = { fg = acc, bold = true },
        SpellAuditMuted = { fg = muted },
        SpellAuditBad = { fg = colors.fg("DiagnosticError", "ErrorMsg"), bold = true, underline = true },
        SpellAuditWord = { bg = colors.blend(acc, bg, 0.35), bold = true },
        SpellAuditSel = { bg = colors.blend(acc, bg, 0.22) },
        WritingTitle = { fg = acc, bold = true },
        WritingMuted = { fg = muted },
        WritingRole = { fg = acc },
        WritingFlag = { fg = warn },
        WritingHeading = { fg = colors.fg("Title", "Normal"), bold = true },
        WritingMajor = { fg = warn, bold = true },
        WritingMinor = { fg = colors.fg("DiagnosticInfo", "Comment") },
    }
end

-- `remap`: lazy maps a string rhs with noremap, and a non-recursive map to a
-- <Plug> does nothing.
local function plug(lhs, name, desc, mode)
    return { lhs, "<Plug>(" .. name .. ")", mode = mode, remap = true, desc = desc }
end

return {
    dir = "~/Downloads/GitHub/quill.nvim",
    name = "quill.nvim",
    cmd = { "Writing", "SpellAudit" },
    keys = {
        plug("<leader>sa", "SpellAudit", "Spell audit (walk every issue)"),
        plug("<leader>Wg", "WritingGrammar", "Writing: grammar audit"),
        plug("<leader>WG", "WritingStyle", "Writing: grammar + style audit"),
        plug("<leader>Wp", "WritingParagraph", "Writing: grammar audit of this paragraph"),
        plug("<leader>Ws", "WritingConform", "Writing: check against STYLE.md"),
        plug("<leader>Wo", "WritingOutline", "Writing: reverse outline"),
        plug("<leader>Wa", "WritingRigor", "Writing: rigor review (arguments, claims, evidence)"),
        plug("<leader>Wr", "WritingRewrite", "Writing: rewrite paragraph / selection", { "n", "x" }),
        plug("<leader>Wq", "WritingAsk", "Writing: ask about paragraph / selection", { "n", "x" }),
        plug("<leader>Wc", "WritingChat", "Writing: companion chat"),
        plug("<leader>Wl", "WritingLater", "Writing: issues left for later (quickfix)"),
        plug("<leader>Wm", "WritingModel", "Writing: pick a task's model for this session"),
        plug("<leader>Wd", "WritingDiagnostics", "Writing: toggle AI diagnostics"),
        plug("<leader>Wx", "WritingClear", "Writing: clear AI issues"),
    },
    opts = {
        assist = {
            presets = {
                "More concise",
                "More formal / academic",
                "Simpler and plainer",
                "Active voice",
                "Smoother flow and transitions",
                "Fix grammar only",
                "Translate to English",
                "Translate to Spanish",
            },
        },
        chat = function(prompt, ctx)
            require("claude_chats").open({ win = ctx.win, prompt = prompt })
        end,
        highlights = highlights,
    },
}
