-- Molten setup that adapts to the terminal.
--
-- Inline images (plots) only work in terminals that speak the Kitty graphics
-- protocol: Kitty, WezTerm, Ghostty. Alacritty has no image support, so there
-- we disable the inline provider and view plots in an external viewer/browser
-- (`:MoltenImagePopup` / `:MoltenOpenInBrowser`).
local function image_capable()
    local term = vim.env.TERM or ""
    return vim.env.KITTY_WINDOW_ID ~= nil
        or vim.env.WEZTERM_PANE ~= nil
        or vim.env.GHOSTTY_RESOURCES_DIR ~= nil
        or vim.env.GHOSTTY_BIN_DIR ~= nil
        or term:find("kitty") ~= nil
        or term:find("ghostty") ~= nil
end

return {
    {
        "benlubas/molten-nvim",
        version = "^1.0.0", -- use version <2.0.0 to avoid breaking changes
        dependencies = { "3rd/image.nvim" },
        build = ":UpdateRemotePlugins",
        init = function()
            -- Kernels from interpreters/venvs (lua/molten_kernels.lua). Puts its
            -- kernelspec dir on $JUPYTER_PATH, so it must run before the Python
            -- host starts.
            require("molten_kernels").setup()
            if image_capable() then
                vim.g.molten_image_provider = "image.nvim"
            else
                -- Alacritty (and other non-graphics terminals): no inline images.
                vim.g.molten_image_provider = "none"
            end
            vim.g.molten_output_win_max_height = 20
            vim.g.molten_auto_open_output = false -- needed when image_provider = none
            vim.g.molten_wrap_output = true
            vim.g.molten_virt_text_output = true -- show text output as virtual text
            vim.g.molten_virt_lines_off_by_1 = true
        end,
    },
    {
        -- only load when the terminal can actually draw images
        "3rd/image.nvim",
        cond = image_capable,
        opts = {
            backend = "kitty", -- kitty graphics protocol (Kitty/WezTerm/Ghostty)
            max_width = 100,
            max_height = 12,
            max_height_window_percentage = math.huge,
            max_width_window_percentage = math.huge,
            window_overlap_clear_enabled = true, -- toggles images when windows are overlapped
            window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
            -- Molten drives image.nvim through its API; the document
            -- integrations (on by default) would render every image link in
            -- Markdown/Neorg/typst buffers inline. They download remote images
            -- and block the editor in `vim.wait` on a `magick identify` per
            -- image, so a README full of shields.io badges froze Neovim and
            -- threw on SVGs ImageMagick can't parse. The Markdown preview
            -- (<leader>pv, lua/pdfview/markdown.lua) shows images properly.
            integrations = {
                markdown = { enabled = false },
                neorg = { enabled = false },
                typst = { enabled = false },
                html = { enabled = false },
                css = { enabled = false },
                asciidoc = { enabled = false },
                syslang = { enabled = false },
                org = { enabled = false },
            },
        },
    },
}
