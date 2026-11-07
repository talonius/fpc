# Sourced by fpc-setup.sh, sdl3-setup.sh and dosbox-x-setup.sh: fetch a Free Pascal, SDL3 or DOSBox-X build
# published as a release, or pack one for publishing. A release holds one <tag>-<target>.tar.zst per target, where
# <tag> names the pins it was built from (fpc-<branch>-<commit>-r<recipe>, sdl3-<version>-r<recipe>,
# dosbox-x-<version>-r<recipe>), and a SHA256SUMS listing them; each archive unpacks into FPC_PREFIX as the folder the
# setup script would have built. An archive over 90 MiB is published in parts, <file>.part00, .part01, ..., which
# SHA256SUMS lists in its place (some forges sit behind proxies that refuse an upload over 100 MB).
#
# Where each tool's release is:
#   FPC_RELEASES           the download base of the release holding Free Pascal builds, for example
#   SDL3_RELEASES            https://github.com/talonius/fpc/releases/download/goldbox: each fork's CI publishes the
#   DOSBOX_X_RELEASES        builds of its goldbox/toolchain pins as its "goldbox" release.
#   TOOLCHAIN_RELEASES     the older layout, one release per pin: <base>/<tag>. Used for a tool whose own variable
#                          above is unset.
#   TOOLCHAIN_FETCH_ONLY   1 makes a build with no release an error instead of compiling it from source, as CI wants.
# Because a file's name carries its pins, a release built from other pins has no file of the name asked for, and the
# setup script says so rather than install the wrong build.

# release_base VAR TAG: print the download base for a tool whose own variable is VAR and whose pins name TAG, or
# nothing when neither VAR nor TOOLCHAIN_RELEASES is set.
release_base() {
    local own="${!1:-}"
    if [ -n "$own" ]; then
        echo "${own%/}"
    elif [ -n "${TOOLCHAIN_RELEASES:-}" ]; then
        echo "${TOOLCHAIN_RELEASES%/}/$2"
    fi
}

# release_fetch BASE FILE DIR: download FILE, whole or in parts, from the release at download base BASE, check it
# against the release's SHA256SUMS and unpack it into DIR. Returns 1, having changed nothing, when BASE is empty,
# SHA256SUMS lists no FILE, or a download fails; a file that does not match its checksum stops the script.
release_fetch() {
    local base="$1" file="$2" dir="$3" dl tool part parts=() re
    re="  ${file//./\\.}(\\.part[0-9]+)?\$"
    [ -n "$base" ] || return 1
    for tool in curl zstd sha256sum; do
        command -v "$tool" > /dev/null 2>&1 \
            || { echo "$tool is not on PATH: cannot fetch $file from $base." >&2; return 1; }
    done
    dl="$(mktemp -d)"
    if ! curl -fsSL -o "$dl/SHA256SUMS" "$base/SHA256SUMS"; then
        rm -rf "$dl"
        return 1
    fi
    while read -r _ part; do
        parts+=("$part")
    done < <(grep -E "$re" "$dl/SHA256SUMS" | sort -k 2)
    if [ "${#parts[@]}" = 0 ]; then
        echo "$base has no $file: it was built from other pins." >&2
        rm -rf "$dl"
        return 1
    fi
    for part in "${parts[@]}"; do
        if ! curl -fsSL -o "$dl/$part" "$base/$part"; then
            rm -rf "$dl"
            return 1
        fi
    done
    if ! (cd "$dl" && grep -E "$re" SHA256SUMS | sha256sum --check --strict --quiet); then
        echo "$file does not match its SHA-256 at $base." >&2
        rm -rf "$dl"
        exit 1
    fi
    mkdir -p "$dir"
    (cd "$dl" && cat "${parts[@]}") | tar --zstd -xf - -C "$dir"
    rm -rf "$dl"
}

# release_missing WHAT BASE FILE: with TOOLCHAIN_FETCH_ONLY=1, stop because the release at BASE has no FILE of WHAT.
release_missing() {
    [ "${TOOLCHAIN_FETCH_ONLY:-}" = 1 ] || return 0
    echo "$1 has no published build (${3} at ${2:-an unset release location}), and TOOLCHAIN_FETCH_ONLY=1 forbids" \
        "building it here: move the fork's goldbox tag to a commit whose goldbox/toolchain has these pins." >&2
    exit 1
}

# release_pack DIR ITEM FILE OUT: pack DIR/ITEM as OUT/FILE, in parts if it is over 90 MiB, and add the SHA-256 of
# each file written to OUT/SHA256SUMS.
release_pack() {
    local dir="$1" item="$2" file="$3" out="$4"
    mkdir -p "$out"
    rm -f "$out/$file"
    tar -C "$dir" --sort=name --owner=0 --group=0 --numeric-owner --exclude="$item/.complete" \
        -I 'zstd -19 -T0 -q' -cf "$out/$file" "$item"
    if [ "$(wc -c < "$out/$file")" -gt $((90 * 1024 * 1024)) ]; then
        rm -f "$out/$file".part*
        split -b 90M -d -a 2 "$out/$file" "$out/$file.part"
        rm "$out/$file"
        (cd "$out" && sha256sum "$file".part*) >> "$out/SHA256SUMS"
    else
        (cd "$out" && sha256sum "$file") >> "$out/SHA256SUMS"
    fi
}
