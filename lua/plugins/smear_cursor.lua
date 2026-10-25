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
  },
}
