-- Pure fun: dissolve the current buffer into falling rain or Conway's Game of
-- Life. Useless, delightful. <leader>fml = "make it rain".
return {
  "Eandrju/cellular-automaton.nvim",
  cmd = "CellularAutomaton",
  keys = {
    { "<leader>fml", "<cmd>CellularAutomaton make_it_rain<cr>", desc = "Make it rain (cellular automaton)" },
    { "<leader>flife", "<cmd>CellularAutomaton game_of_life<cr>", desc = "Game of Life (cellular automaton)" },
  },
}
