#!/bin/sh
# Downloads the latest slack-remote release, checks its SHA-256 and signature,
# and installs the binary into ~/.local/bin (or DIR/bin with --prefix DIR)
# and SlackRemote.app into ~/Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/thatjuan/slack-remote/main/scripts/get.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/thatjuan/slack-remote/main/scripts/get.sh | sh -s -- --prefix DIR
set -eu

repo=thatjuan/slack-remote

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

# Everything runs inside main so a truncated download never executes half a script.
main() {
    prefix="$HOME/.local"
    if [ "$#" -ne 0 ]; then
        if [ "$#" -ne 2 ] || [ "$1" != "--prefix" ] || [ -z "$2" ]; then
            fail 'Usage: get.sh [--prefix DIR]'
        fi
        prefix="$2"
    fi
    case "$prefix" in
        /*) ;;
        *) prefix="$PWD/$prefix" ;;
    esac
    [ "$(uname -s)" = Darwin ] || fail 'slack-remote runs only on macOS.'

    target="$prefix/bin/slack-remote"
    check_target

    # /releases/latest redirects to /releases/tag/<tag>.
    latest=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")
    tag=${latest##*/}
    case "$tag" in
        v[0-9]*) ;;
        *) fail "No release found at https://github.com/$repo/releases" ;;
    esac
    archive="slack-remote-${tag#v}-macos.zip"
    base="https://github.com/$repo/releases/download/$tag"

    work=$(mktemp -d)
    staged=
    trap 'rm -rf "$work"; [ -z "$staged" ] || rm -rf "$staged"' EXIT
    trap 'exit 1' HUP INT TERM
    printf 'Downloading %s\n' "$archive"
    curl -fsSL -o "$work/$archive" "$base/$archive"
    curl -fsSL -o "$work/$archive.sha256" "$base/$archive.sha256"
    (cd "$work" && /usr/bin/shasum -a 256 -c "$archive.sha256" >/dev/null) ||
        fail "SHA-256 check failed for $archive"
    /usr/bin/unzip -q "$work/$archive" slack-remote -d "$work"
    /usr/bin/codesign --verify --strict "$work/slack-remote" ||
        fail 'The downloaded binary failed signature verification.'

    mkdir -p "$prefix/bin"
    staged=$(mktemp -d "$prefix/bin/.slack-remote.XXXXXXXX")
    install -m 755 "$work/slack-remote" "$staged/slack-remote"
    if [ -e "$target" ]; then
        check_target
        mv -fh "$staged/slack-remote" "$target"
    else
        # Linking into an empty slot also catches a concurrent first install.
        ln -h "$staged/slack-remote" "$target"
    fi
    printf 'Installed %s (%s)\n' "$target" "$("$target" --version)"

    downloaded_app="$work/payload/SlackRemote.app"
    if ! /usr/bin/ditto -x -k --rsrc "$work/$archive" "$work/payload" ||
        [ ! -d "$downloaded_app" ] || [ -L "$downloaded_app" ]; then
        printf 'Skipping SlackRemote.app: the release could not be extracted or contains no app.\n' >&2
    elif ! /usr/bin/codesign --verify --strict --deep "$downloaded_app"; then
        printf 'Skipping SlackRemote.app: signature verification failed.\n' >&2
    elif /usr/bin/codesign -dv "$work/slack-remote" 2>&1 | /usr/bin/grep -q '^Authority=Developer ID Application:' &&
        ! /usr/sbin/spctl --assess --type execute "$downloaded_app"; then
        printf 'Skipping SlackRemote.app: Gatekeeper assessment failed.\n' >&2
    elif ! install_app "$downloaded_app"; then
        printf 'Could not install or launch SlackRemote.app. The CLI is installed.\n' >&2
    fi

    case ":$PATH:" in
        *":$prefix/bin:"*) ;;
        *) printf 'Add %s to PATH, for example:\n  echo '\''export PATH="%s:$PATH"'\'' >> ~/.zshrc\n' \
            "$prefix/bin" "$prefix/bin" ;;
    esac
    printf 'Next, run: slack-remote doctor --grant (it grants access to SlackRemote, not your terminal)\n'
}

# Only replace a regular, executable, valid slack-remote binary.
check_target() {
    if [ -L "$target" ] || { [ -e "$target" ] && ! {
        [ -f "$target" ] && [ -x "$target" ] &&
            /usr/bin/codesign --verify --strict "$target" 2>/dev/null &&
            /usr/bin/codesign -dv "$target" 2>&1 | /usr/bin/grep -qx 'Identifier=slack-remote'
    }; }; then
        fail "Refusing to overwrite $target"
    fi
}

# Keep this block in sync with scripts/lib/app-install.sh. get.sh is piped to sh.
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

main "$@"
