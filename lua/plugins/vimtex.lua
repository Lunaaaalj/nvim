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
    -- PDF viewer. Skim over sioyek: sioyek ships unsigned, so Gatekeeper
    -- kills it on launch -- and since VimTeX starts viewers detached, that
    -- failure is completely silent (`\lv` just does nothing). Homebrew
    -- deprecated the sioyek cask for that same reason, disabling 2026-09-01.
    -- Skim is notarized and is the de-facto LaTeX viewer on macOS.
    vim.g.vimtex_view_method = "skim"
    vim.g.vimtex_view_skim_sync = 1 -- forward search: jump PDF to cursor line
    vim.g.vimtex_view_skim_activate = 1 -- focus the Skim window on view
    vim.g.vimtex_view_skim_reading_bar = 1 -- highlight the synced line
    -- Don't jump to the PDF as soon as compilation starts; `\lv` is explicit.
    vim.g.vimtex_view_forward_search_on_start = 0
  end
}
}
