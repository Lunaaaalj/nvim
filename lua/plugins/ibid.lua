-- ibid.nvim: cite from Zotero and keep each document's .bib equal to the
-- entries it cites (via Better BibTeX). Developed in its own repo; see its
-- README / :help ibid. <leader>Z is Zotero (<leader>z stays Zen mode).
--
-- Glue that lives here, not in the plugin: theme-derived colours (through
-- defaults/colors.lua, re-applied on ColorScheme) and PDFs opened with
-- :edit, which pdfview claims (BufReadCmd *.pdf). The cmp source is
-- registered in cmp.lua and the hover provider listed in hover.lua.
local function set_hl()
    local colors = require("defaults.colors")
    vim.api.nvim_set_hl(0, "IbidAuthor", { fg = colors.accent() })
    vim.api.nvim_set_hl(0, "IbidYear", { fg = colors.fg("Comment") })
    vim.api.nvim_set_hl(0, "IbidMuted", { fg = colors.fg("Comment") })
end

local function call(name, ...)
    local args = { ... }
    return function() require("ibid")[name](unpack(args)) end
end

return {
    dir = "~/Downloads/GitHub/ibid.nvim",
    name = "ibid.nvim",
    ft = { "tex", "plaintex", "markdown", "quarto", "rmd", "typst" },
    cmd = "Ibid",
    keys = {
        { "<leader>Zc", call("cite"),           desc = "Zotero: cite" },
        { "<leader>ZC", call("cayw"),           desc = "Zotero: cite with Zotero's picker (CAYW)" },
        { "<leader>Zs", call("sync"),           desc = "Zotero: sync the .bib" },
        { "<leader>ZS", call("sync", { force = true, adopt = true }), desc = "Zotero: re-export the whole .bib" },
        { "<leader>Zi", call("info"),           desc = "Zotero: item card" },
        { "<leader>Zp", call("open_pdf"),       desc = "Zotero: open PDF" },
        { "<leader>Zz", call("show_in_zotero"), desc = "Zotero: show in Zotero" },
        { "<leader>Zu", call("open_url"),       desc = "Zotero: open DOI/URL" },
        { "<leader>Zb", call("yank_bibtex"),    desc = "Zotero: yank BibTeX entry" },
        { "<leader>Zr", call("yank_reference"), desc = "Zotero: yank formatted reference" },
    },
    opts = {
        open_pdf = function(path) vim.cmd.edit(vim.fn.fnameescape(path)) end,
    },
    config = function(_, opts)
        require("ibid").setup(opts)
        set_hl()
        vim.api.nvim_create_autocmd("ColorScheme", {
            group = vim.api.nvim_create_augroup("ibid_glue", { clear = true }),
            callback = set_hl,
        })
    end,
}
