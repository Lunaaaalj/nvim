-- Hand Neovim's final cwd back to the shell that launched it.
--
-- A child process can't change its parent shell's directory, so this works
-- like yazi/lf's "cd on quit": the shell's `nvim` wrapper (see ~/.zshrc) sets
-- $NVIM_CWD_FILE to a temp file, we write getcwd() there on exit, and the
-- wrapper `cd`s into it. Without the variable (plain `command nvim`, GUIs)
-- this does nothing.

local file = vim.env.NVIM_CWD_FILE
if not file or file == "" then return end

-- Don't leak it into :terminal shells, where a nested nvim would write to
-- the same file and steal the outer session's result.
vim.env.NVIM_CWD_FILE = nil

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("ShellCwd", { clear = true }),
  callback = function()
    pcall(vim.fn.writefile, { vim.fn.getcwd() }, file)
  end,
})
