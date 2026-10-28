-- projectrc.nvim: per-project settings, VS Code style (.nvim/settings.json +
-- the tools' own .clang-format / .clangd), edited in a float. Developed in its
-- own repo; see its README / :help projectrc. It also makes C-family indent
-- follow clang-format (so >> and format-on-save agree).
--
-- Glue that lives here, not in the plugin: theme-derived colours (through
-- defaults/colors.lua, re-applied on ColorScheme), transparency from
-- g:ui_transparent, and build/run/test sent to a project shell from
-- lua/terminals (so <leader>tq turns its errors into a quickfix list). The
-- hooks into conform, clangd and nvim-dap are in their own specs. The float's
-- filetype `projectrc` is in cursorline.lua's `unmanaged_ft`.

-- Accent from the active scheme, like the music player and upstream.nvim.
local function set_hl()
    local colors = require("defaults.colors")
    local acc = colors.accent()
    local bg = vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false }).bg
        or vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
        or tonumber(colors.terminal_bg:sub(2), 16)
    vim.api.nvim_set_hl(0, "ProjectRCAccent", { fg = acc })
    vim.api.nvim_set_hl(0, "ProjectRCTitle", { fg = acc, bold = true })
    vim.api.nvim_set_hl(0, "ProjectRCMuted", { fg = colors.fg("Comment") })
    vim.api.nvim_set_hl(0, "ProjectRCWarn", { fg = colors.fg("DiagnosticWarn", "WarningMsg") })
    vim.api.nvim_set_hl(0, "ProjectRCSel", { bg = colors.blend(acc, bg, 0.22) })
end

-- One shell per project, reused across runs.
local build_terms = {}
local function runner(cmd, ctx)
    local names = vim.tbl_keys(ctx.env)
    table.sort(names)
    local prefix = ""
    for _, k in ipairs(names) do prefix = prefix .. k .. "=" .. vim.fn.shellescape(ctx.env[k]) .. " " end
    local line = "cd " .. vim.fn.shellescape(ctx.cwd) .. " && " .. prefix .. cmd

    local T = require("terminals")
    local id = build_terms[ctx.root]
    if not (id and T.get(id)) then
        id = T.new({ dir = ctx.cwd, name = "build: " .. vim.fs.basename(ctx.root) })
        if not id then return end
        build_terms[ctx.root] = id
    elseif not T.get(id):is_open() then
        T.open(id)
    end
    T.send({ line }, id)
    vim.cmd("stopinsert | wincmd p")
end

local function build(kind) return function() require("projectrc").build(kind) end end

return {
    dir = "~/Downloads/GitHub/projectrc.nvim",
    name = "projectrc.nvim",
    -- not lazy: the appliers (options, clang-format indent) must see the
    -- first FileType, and conform/mason/dap call into it
    lazy = false,
    keys = {
        { "<leader>,", function() require("projectrc").open() end, desc = "Project settings" },
        { "<leader>bb", build("cmd"), desc = "Build: project build command" },
        { "<leader>br", build("run"), desc = "Build: project run command" },
        { "<leader>bt", build("test"), desc = "Build: project test command" },
    },
    opts = {
        transparent = function() return vim.g.ui_transparent end,
        runner = runner,
    },
    config = function(_, opts)
        require("projectrc").setup(opts)
        set_hl()
        vim.api.nvim_create_autocmd("ColorScheme", {
            group = vim.api.nvim_create_augroup("projectrc_glue", { clear = true }),
            callback = set_hl,
        })
    end,
}
