# shellcheck shell=sh
# Keep this block in sync with the copy in scripts/get.sh, which is piped to sh.
# BEGIN app-install
check_app_target() {
    if [ -L "$1" ] || { [ -e "$1" ] && ! {
        [ -d "$1" ] &&
            [ "$(/usr/bin/defaults read "$1/Contents/Info" CFBundleIdentifier 2>/dev/null)" = com.thatjuan.slack-remote.helper ]
    }; }; then
        printf 'Refusing to modify %s\n' "$1" >&2
        return 1
    fi
}

quit_helper() (
    uid=$(/usr/bin/id -u) || exit 1
    # Match the installed executable at the start of the command line.
    executable=$(printf '%s\n' "$1/Contents/MacOS/SlackRemote" | /usr/bin/sed 's/[][\\.^$*+?(){}|]/\\&/g') || exit 1
    pattern="^$executable([[:space:]]|$)"
    /usr/bin/pkill -TERM -u "$uid" -f "$pattern" || :
    attempts=0
    while [ "$attempts" -lt 5 ]; do
        /usr/bin/pgrep -q -u "$uid" -f "$pattern" || exit 0
        /bin/sleep 1
        attempts=$((attempts + 1))
    done

    /usr/bin/pkill -KILL -u "$uid" -f "$pattern" || :
    /bin/sleep 0.1
    if /usr/bin/pgrep -q -u "$uid" -f "$pattern"; then
        printf 'SlackRemote.app is still running. Quit it from the menu bar and try again.\n' >&2
        exit 1
    fi
)

install_app() (
    app_dir="$HOME/Applications"
    app_target="$app_dir/SlackRemote.app"
    check_app_target "$app_target" || exit 1
    /bin/mkdir -p "$app_dir" || exit 1
    app_stage=$(/usr/bin/mktemp -d "$app_dir/.SlackRemote.XXXXXXXX") || exit 1
    trap '/bin/rm -rf "$app_stage"' EXIT
    trap 'exit 1' HUP INT TERM
    /usr/bin/ditto --rsrc "$1" "$app_stage/SlackRemote.app" || exit 1
    quit_helper "$app_target" || exit 1
    check_app_target "$app_target" || exit 1
    if [ -e "$app_target" ]; then
        # mv cannot replace a nonempty directory, so move the old bundle aside first.
        # osascript can hang on exit on macOS 27, so the installer avoids it.
        /bin/mv -h "$app_target" "$app_stage/previous.app" || exit 1
        if ! /bin/mv -hn "$app_stage/SlackRemote.app" "$app_dir/" || [ -e "$app_stage/SlackRemote.app" ]; then
            /bin/mv -hn "$app_stage/previous.app" "$app_target"
            printf 'Could not replace %s\n' "$app_target" >&2
            exit 1
        fi
    else
        /bin/mv -hn "$app_stage/SlackRemote.app" "$app_dir/" || exit 1
        if [ -e "$app_stage/SlackRemote.app" ]; then
            printf 'Refusing to overwrite a newly created %s\n' "$app_target" >&2
            exit 1
        fi
    fi
    printf 'Installed %s\n' "$app_target"
    /usr/bin/open -g -j "$app_target"
)
# END app-install
