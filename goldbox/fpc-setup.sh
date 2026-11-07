#!/usr/bin/env bash
#
# Download and build the pinned Free Pascal toolchain used by native builds.
#
#   scripts/fpc-setup.sh            build the compiler for this host and the cross compilers build/toolchain lists
#   scripts/fpc-setup.sh --print    print the folder the toolchain is (or would be) installed in, and stop
#   scripts/fpc-setup.sh --pack DIR set up as usual, then pack the installation into DIR as the talonius/fpc fork's
#                                   goldbox release publishes it (scripts/toolchain-release.sh)
#
# build/toolchain specifies the source branch and commit, plus the released compiler used to bootstrap it, and the
# recipe (recipe=N), the revision of how this script builds them. The result is installed under
# $FPC_PREFIX/<branch>-<short commit>, with ~/fpc as the default prefix. Re-running the script with the same pins
# reuses the completed installation. With FPC_RELEASES (or TOOLCHAIN_RELEASES) set, a published build of these pins
# is downloaded instead of compiled: fpc-<branch>-<short commit>-r<recipe>-<host>.tar.zst, which the talonius/fpc
# fork's goldbox release publishes (see scripts/toolchain-release.sh). TOOLCHAIN_FILE
# names another pin file, for a repository that keeps it elsewhere.
#
# Downloads go to $FPC_PREFIX/cache, each into its own folder. Nothing outside FPC_PREFIX is changed. FPC_GIT_URL
# replaces GitLab's Free Pascal repository, and FPC_BOOTSTRAP_URL the bootstrap compiler's download, with mirrors.
#
# An x86-64 Linux host also builds the i386-linux, i386-win32, and x86_64-win64 cross-compilers. The i386 Linux
# target was the first native port because its four-byte pointers preserve Turbo Pascal's record layouts. Apple
# Silicon hosts build aarch64-darwin only; Intel Macs are deprecated as of macOS 26 and have no target here.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
toolchain="${TOOLCHAIN_FILE:-$root/build/toolchain}"

setting() {
    sed -n "s/^$1=\([A-Za-z0-9._@-]*\).*/\1/p" "$toolchain" 2> /dev/null | head -n 1
}

pin="$(setting fpc)"
bootstrap="$(setting fpc_bootstrap)"
[ -n "$pin" ] || { echo "fpc-setup.sh: $toolchain has no fpc=<branch>@<commit> line." >&2; exit 1; }
[ -n "$bootstrap" ] || { echo "fpc-setup.sh: $toolchain has no fpc_bootstrap=<version> line." >&2; exit 1; }
recipe="$(setting recipe)"
recipe="${recipe:-1}"
branch="${pin%@*}"
commit="${pin#*@}"
prefix_root="${FPC_PREFIX:-$HOME/fpc}"
prefix="$prefix_root/$branch-${commit:0:7}"
tag="fpc-$branch-${commit:0:7}-r$recipe"

pack=""
case "${1:-}" in
    --print) echo "$prefix"; exit 0 ;;
    --pack) [ $# -eq 2 ] || { echo "fpc-setup.sh: --pack needs the folder to pack into." >&2; exit 2; }
            pack="$2" ;;
    "") ;;
    *) echo "fpc-setup.sh: unknown option $1 (the options are --print and --pack DIR)" >&2; exit 2 ;;
esac
. "$(dirname "${BASH_SOURCE[0]}")/toolchain-release.sh"

host_os="$(uname -s)"
host_cpu="$(uname -m)"
case "$host_os-$host_cpu" in
    Linux-x86_64)
        boot_dist="x86_64-linux" boot_pp="ppcx64"
        crosses=("i386 linux" "i386 win32" "x86_64 win64") ;;
    Darwin-arm64)
        boot_dist="aarch64-darwin" boot_pp="ppca64"
        crosses=() ;;
    *) echo "fpc-setup.sh: no recipe for a $host_os $host_cpu host." >&2; exit 1 ;;
esac
file="$tag-$boot_dist.tar.zst"

# Point the compiler links and etc/fpc.cfg at the installation's lib folder, after a build or once a published build
# is unpacked (the archive's links and configuration name the folder it was built in).
configure() {
    local lib pp plain
    lib="$(ls -d "$prefix"/lib/fpc/[0-9]* | head -n 1)"
    # Put compiler links where the fpc driver expects them; etc/fpc.cfg locates their units.
    for pp in "$lib"/ppc*; do
        ln -sf "$pp" "$prefix/bin/$(basename "$pp")"
    done
    # Add the native-style name when a CPU has only a cross-compiler; the fpc driver may request either name.
    for pp in "$lib"/ppcross*; do
        [ -e "$pp" ] || continue
        plain="ppc${pp##*/ppcross}"
        [ -e "$lib/$plain" ] || ln -sf "$pp" "$prefix/bin/$plain"
    done
    mkdir -p "$prefix/etc"
    "$prefix/bin/fpcmkcfg" -d "basepath=$lib" -o "$prefix/etc/fpc.cfg"
    if [ "$host_os" = Darwin ]; then
        # fpcmkcfg may select an older Command Line Tools linker and SDK that current Xcode cannot use. Disable those
        # entries and use Xcode's own linker and SDK instead.
        sed -i '' 's|^\(-F[DlL].*/Library/Developer/CommandLineTools/.*\)|#\1|; s|^\(-XR/Library/Developer/CommandLineTools/.*\)|#\1|' \
            "$prefix/etc/fpc.cfg"
        echo "-FD$(dirname "$(xcrun --find ld)")" >> "$prefix/etc/fpc.cfg"
    fi
    [ -z "$opt" ] || echo "$opt" >> "$prefix/etc/fpc.cfg"
}

# Pack the finished installation when asked to, and stop.
finish() {
    if [ -n "$pack" ]; then
        release_pack "$prefix_root" "$(basename "$prefix")" "$file" "$pack"
        echo "fpc-setup.sh: packed $pack/$file"
    fi
    exit 0
}

# On macOS, point every link at the Xcode SDK because the C library and frameworks are not in /usr/lib.
opt=""
if [ "$host_os" = Darwin ]; then
    sdk="$(xcrun --show-sdk-path)" || { echo "fpc-setup.sh: no macOS SDK: install Xcode or its tools." >&2; exit 1; }
    opt="-XR$sdk"
fi

# Write this marker last so an interrupted installation is rebuilt.
stamp="$prefix/.complete"
if [ -f "$stamp" ]; then
    echo "fpc-setup.sh: Free Pascal $pin is already in $prefix"
    finish
fi

# --- a published build --------------------------------------------------------------------------

base="$(release_base FPC_RELEASES "$tag")"
if release_fetch "$base" "$file" "$prefix_root"; then
    configure > /dev/null
    touch "$stamp"
    echo "fpc-setup.sh: Free Pascal $pin installed in $prefix from $base"
    finish
fi
release_missing "Free Pascal $pin" "$base" "$file"

problems=()
for tool in curl tar git make; do
    command -v "$tool" > /dev/null 2>&1 || problems+=("$tool is not on PATH.")
done
if [ ${#problems[@]} -gt 0 ]; then
    echo "fpc-setup.sh: cannot set up Free Pascal. Fix these first:" >&2
    printf '  - %s\n' "${problems[@]}" >&2
    exit 1
fi

cache="$prefix_root/cache"
mkdir -p "$cache"
jobs="$(getconf _NPROCESSORS_ONLN 2> /dev/null || echo 4)"

# --- the bootstrap compiler ---------------------------------------------------------------------

# Only the bootstrap compiler binary is needed. It compiles the pinned source, which then rebuilds itself.
boot="$cache/bootstrap-$bootstrap-$boot_dist"
if [ ! -x "$boot/$boot_pp" ]; then
    echo "fpc-setup.sh: downloading the Free Pascal $bootstrap compiler to bootstrap with..."
    rm -rf "$boot" "$boot.download"
    mkdir -p "$boot.download"
    # Free Pascal's release archive contains nested component archives; the compiler is in the base component.
    url="https://downloads.freepascal.org/fpc/dist/$bootstrap/$boot_dist/fpc-$bootstrap.$boot_dist.tar"
    url="${FPC_BOOTSTRAP_URL:-$url}"
    curl -fsSL "$url" -o "$boot.download/fpc.tar"
    tar -xf "$boot.download/fpc.tar" -C "$boot.download"
    tar -xf "$boot.download"/fpc-*/binary.*.tar -C "$boot.download"
    tar -xzf "$boot.download"/base.*.tar.gz -C "$boot.download" "lib/fpc/$bootstrap/$boot_pp"
    mkdir -p "$boot"
    cp "$boot.download/lib/fpc/$bootstrap/$boot_pp" "$boot/"
    rm -rf "$boot.download"
fi

# --- the pinned source --------------------------------------------------------------------------

source="$cache/source-$branch-$commit"
if [ ! -d "$source/compiler" ]; then
    echo "fpc-setup.sh: fetching the Free Pascal source, $branch at $commit..."
    rm -rf "$source"
    git init -q "$source"
    git -C "$source" fetch -q --depth 1 "${FPC_GIT_URL:-https://gitlab.com/freepascal.org/fpc/source.git}" "$commit"
    git -C "$source" checkout -q FETCH_HEAD
fi

# --- build and install --------------------------------------------------------------------------

log="$cache/build-$branch-$commit.log"
: > "$log"
echo "fpc-setup.sh: building the compiler for this host (log: $log)..."
make -C "$source" -j "$jobs" FPMAKEOPT="-T $jobs" PP="$boot/$boot_pp" OPT="$opt" all >> "$log" 2>&1 \
    || { echo "fpc-setup.sh: the host build failed; see $log" >&2; tail -n 20 "$log" >&2; exit 1; }
make -C "$source" PP="$boot/$boot_pp" OPT="$opt" INSTALL_PREFIX="$prefix" install >> "$log" 2>&1 \
    || { echo "fpc-setup.sh: installing the host build failed; see $log" >&2; exit 1; }

version="$(sed -n 's/^version=\([0-9.]*\).*/\1/p' "$source/compiler/Makefile.fpc" | head -n 1)"
lib="$prefix/lib/fpc/$version"
# Use the newly installed compiler to build every cross-compiler from the same pinned source.
newpp="$lib/$boot_pp"

for cross in ${crosses[@]+"${crosses[@]}"}; do
    set -- $cross
    echo "fpc-setup.sh: building the $1-$2 cross compiler..."
    make -C "$source" -j "$jobs" FPMAKEOPT="-T $jobs" PP="$newpp" OPT="$opt" CPU_TARGET="$1" OS_TARGET="$2" crossall \
        >> "$log" 2>&1 \
        || { echo "fpc-setup.sh: the $1-$2 build failed; see $log" >&2; tail -n 20 "$log" >&2; exit 1; }
    make -C "$source" PP="$newpp" OPT="$opt" CPU_TARGET="$1" OS_TARGET="$2" INSTALL_PREFIX="$prefix" crossinstall \
        >> "$log" 2>&1 \
        || { echo "fpc-setup.sh: installing the $1-$2 build failed; see $log" >&2; exit 1; }
done

configure >> "$log" 2>&1

touch "$stamp"
echo "fpc-setup.sh: Free Pascal $version ($pin) installed in $prefix"
echo "fpc-setup.sh: compilers: $(cd "$prefix/bin" && ls ppc* | tr '\n' ' ')"
finish
