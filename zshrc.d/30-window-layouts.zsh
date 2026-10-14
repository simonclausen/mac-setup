# Managed by mac-setup (30-window-layouts.zsh)
# Hammerspoon window layouts (see ~/.hammerspoon/init.lua)
wl() {
  case "$1" in
    save|restore) [[ -n "$2" ]] || { echo "usage: wl $1 <name>" >&2; return 1; }
                  hs -c "${1}Layout(\"$2\")" ;;
    list)         hs -c 'listLayouts()' ;;
    windows)      hs -c 'listWindows()' ;;
    *)            echo "usage: wl save|restore <name> | list | windows" >&2; return 1 ;;
  esac
}
