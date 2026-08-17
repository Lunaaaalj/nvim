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
    -- VimTeX configuration goes here, e.g.
    vim.g.vimtex_view_method = "sioyek"
    vim.g.vimtex_view_forward_search_on_start = 0
  end
}
}
