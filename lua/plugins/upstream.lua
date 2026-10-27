-- upstream.nvim: full-screen GitHub UI (issues, PRs, review requests, CI runs,
-- PR review, Claude drafts) on top of the `gh` CLI. Developed in its own repo;
-- see its README / :help upstream.
-- <leader>G is GitHub (<leader>g stays git/diffview).
--
-- Glue that lives here, not in the plugin: theme-derived colours (through
-- defaults/colors.lua, re-applied on ColorScheme), "work on this issue" chats
-- through claude_chats (with its `prompt` option), and a dashboard stats
-- refresh after every write. The list's filetype `upstream` is in
-- cursorline.lua's `unmanaged_ft` (its cursorline is the selection).
local function open(tab)
    return function() require("upstream").open({ tab = tab }) end
end

-- Accent from the active scheme, like the music player and the dashboard.
local function set_hl()
    local colors = require("defaults.colors")
    local acc = colors.accent()
    local bg = vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false }).bg
        or vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
        or tonumber(colors.terminal_bg:sub(2), 16)
    vim.api.nvim_set_hl(0, "UpstreamAccent", { fg = acc })
    vim.api.nvim_set_hl(0, "UpstreamTitle", { fg = acc, bold = true })
    vim.api.nvim_set_hl(0, "UpstreamTabActive", { fg = acc, bold = true })
    vim.api.nvim_set_hl(0, "UpstreamMuted", { fg = colors.fg("Comment") })
    vim.api.nvim_set_hl(0, "UpstreamSel", { bg = colors.blend(acc, bg, 0.22) })
end

return {
    dir = "~/Downloads/GitHub/upstream.nvim",
    name = "upstream.nvim",
    cmd = "Upstream",
    keys = {
        { "<leader>Go", open(),          desc = "GitHub: open (last tab)" },
        { "<leader>Gi", open("issues"),  desc = "GitHub: issues" },
        { "<leader>Gp", open("prs"),     desc = "GitHub: pull requests" },
        { "<leader>Gr", open("reviews"), desc = "GitHub: review requests" },
        { "<leader>Gn", function() require("upstream").new_issue() end, desc = "GitHub: new issue" },
        { "<leader>Gc", function() require("upstream").new_pr({ ai = true }) end, desc = "GitHub: create PR (AI draft)" },
    },
    opts = {
        ai = {
            open_chat = function(prompt, ctx)
                require("claude_chats").open({
                    prompt = prompt,
                    title = ("#%d %s"):format(ctx.number, ctx.title or ""),
                })
            end,
        },
    },
    config = function(_, opts)
        require("upstream").setup(opts)
        local group = vim.api.nvim_create_augroup("upstream_glue", { clear = true })
        set_hl()
        vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_hl })
        -- a write (comment, close, merge, new issue/PR…) can change the
        -- dashboard's PR/issue counts; plain reads don't
        vim.api.nvim_create_autocmd("User", {
            group = group,
            pattern = "UpstreamChanged",
            callback = function(ev)
                if ev.data and ev.data.item then require("defaults.dashboard_data").refresh(true) end
            end,
        })
    end,
}
