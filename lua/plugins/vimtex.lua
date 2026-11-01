return {
    {
  "lervag/vimtex",
  lazy = false, -- we don't want to lazy load VimTeX
  -- Pinned: VimTeX HEAD requires nvim >= 0.12.4 (bumped 2026-07-22). We run
  -- 0.11.x, and the version gate `finish`es ftplugin/tex.vim before
  -- vimtex#init(), which kills every mapping, the latexmk compiler, and
  -- vimtex#syntax#in_mathzone() -- the last one silently disables all the
  -- math autosnippets in lua/snippets/tex.lua. v2.18 is the last tag that
  -- still accepts nvim 0.10+. Drop this pin after upgrading to nvim 0.12.4.
  tag = "v2.18",
  init = function()
    -- PDF viewer: the in-terminal kitty preview (lua/pdfview/tex.lua) is the
    -- viewer. VimTeX's own viewer only backs `<leader>lV` and the fallback
    -- outside a graphics terminal, and is the system viewer (`open`), not
    -- Skim: the skim viewer's compiler_callback talks to Skim after *every*
    -- compile, even with view_automatic off.
    vim.g.vimtex_view_method = "general"
    vim.g.vimtex_view_general_viewer = "open"
    vim.g.vimtex_view_general_options = "@pdf"
    -- Never auto-open VimTeX's viewer on the first successful compile;
    -- pdfview.tex opens the kitty preview instead (same once-per-session rule).
    vim.g.vimtex_view_automatic = 0
    vim.g.vimtex_view_forward_search_on_start = 0
    -- Register the preview's compile hooks before the first `<leader>ll`.
    vim.api.nvim_create_autocmd("User", {
      pattern = "VimtexEventInitPost",
      callback = function() require("pdfview.tex").setup() end,
    })
  end
}
}
