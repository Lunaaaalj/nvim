-- Animated cursor trail. Owns ALL cursor animation.
return {
  "sphamba/smear-cursor.nvim",
  opts = {
    -- With a transparent Normal bg, smear has no colour to fade its trail into
    -- and falls back to #303030, which is lighter than the terminal and leaves a
    -- grey ghost. Fade into what is actually behind the editor instead.
    transparent_bg_fallback_color = require("defaults.colors").terminal_bg,
    -- Snappier than the defaults (0.6 / 0.45): the trail settles faster.
    stiffness = 0.8,
    trailing_stiffness = 0.6,
    stiffness_insert_mode = 0.7,
    trailing_stiffness_insert_mode = 0.7,
    distance_stop_animating = 0.5,
    -- Typing glide (VS Code's smooth caret). The insert cursor is a vertical bar,
    -- and bars stop animating within 0.875 cells by default, so a one-character
    -- step (exactly 1 cell) barely moved. Legacy-computing glyphs (kitty draws
    -- them natively) render sub-cell bars, which makes 0.1 safe.
    legacy_computing_symbols_support_vertical_bars = true,
    distance_stop_animating_vertical_bar = 0.1,
    -- Short head-to-tail length in insert mode: a glide, not a long streak.
    max_length_insert_mode = 2.0,
  },
}
