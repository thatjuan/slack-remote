#!/bin/sh
set -eu

if [ "$#" -ne 0 ]; then
    printf 'Usage: %s\n' "$0" >&2
    exit 2
fi

cd "$(dirname "$0")/.."
swift build -c release --arch arm64 --arch x86_64 -Xlinker -adhoc_codesign
build_dir=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
binary="$build_dir/slack-remote"
case "$(/usr/bin/lipo -archs "$binary")" in
    'arm64 x86_64'|'x86_64 arm64') ;;
    *) printf 'Expected arm64 and x86_64 slices in %s\n' "$binary" >&2; exit 1 ;;
esac
/usr/bin/codesign --verify --strict --all-architectures "$binary"
version=$("$binary" --version)
archive="slack-remote-$version-macos.zip"

mkdir -p dist
staged=$(mktemp -d "$PWD/dist/.package.XXXXXXXX")
trap 'rm -rf "$staged"' EXIT
trap 'exit 1' HUP INT TERM
mkdir "$staged/payload"
install -m 755 "$binary" "$staged/payload/slack-remote"
cp README.md "$staged/payload/"
cp -R docs "$staged/payload/"
(
    cd "$staged/payload"
    /usr/bin/zip -qr "../$archive" slack-remote README.md docs
    cd ..
    /usr/bin/shasum -a 256 "$archive" > "$archive.sha256"
)
mv -f "$staged/$archive" "$staged/$archive.sha256" dist/
printf '%s\n' "$PWD/dist/$archive" "$PWD/dist/$archive.sha256"
