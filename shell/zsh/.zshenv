# Shell integration for terminals spawned by lua/terminals/ (Neovim).
#
# Neovim starts zsh with ZDOTDIR pointing here and the user's original value in
# NVIM_TERM_ZDOTDIR. This file restores it, sources the real .zshenv, and — in
# the interactive shell — adds prompt hooks that report to Neovim via OSC:
#
#   OSC 633;E;<cmdline>   command about to run (for "repeat last command")
#   OSC 133;C             output starts
#   OSC 133;D;<status>    command finished with <status>
#   OSC 7                 current directory (session restore, tab names)
#
# Neovim reads them through the TermRequest autocmd; nothing reaches the outer
# terminal. ~/.zshrc and the rest of the startup files load unchanged.

_nvt_self=$ZDOTDIR
if [[ -n $NVIM_TERM_ZDOTDIR ]]; then
  ZDOTDIR=$NVIM_TERM_ZDOTDIR
else
  unset ZDOTDIR
fi
[[ -f ${ZDOTDIR:-$HOME}/.zshenv ]] && source ${ZDOTDIR:-$HOME}/.zshenv

if [[ ! -o interactive ]]; then
  # toggleterm runs `zsh -c "zsh;#toggleterm#N"`: keep pointing the inner,
  # interactive zsh back at this file.
  export ZDOTDIR=$_nvt_self
  unset _nvt_self
  return 0
fi
unset _nvt_self NVIM_TERM_ZDOTDIR

_nvt_running=0
_nvt_precmd() {
  local st=$?
  (( _nvt_running )) && print -n "\e]133;D;$st\a"
  _nvt_running=0
  print -rn -- $'\e]7;file://'"${HOST}${PWD}"$'\a'
}
_nvt_preexec() {
  _nvt_running=1
  print -rn -- $'\e]633;E;'"${1//[[:cntrl:]]/ }"$'\a\e]133;C\a'
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _nvt_precmd
add-zsh-hook preexec _nvt_preexec
