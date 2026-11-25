#!/bin/sh
# Downloads the latest slack-remote release, checks its SHA-256 and signature,
# and installs the binary into ~/.local/bin (or DIR/bin with --prefix DIR).
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

    case ":$PATH:" in
        *":$prefix/bin:"*) ;;
        *) printf 'Add %s to PATH, for example:\n  echo '\''export PATH="%s:$PATH"'\'' >> ~/.zshrc\n' \
            "$prefix/bin" "$prefix/bin" ;;
    esac
    printf 'Next, run: slack-remote doctor --grant\n'
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

main "$@"
