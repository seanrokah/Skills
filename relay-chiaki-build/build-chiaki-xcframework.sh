#!/usr/bin/env bash
# shellcheck shell=bash
#
# build-chiaki-xcframework.sh
#
# Builds libchiaki (the core library of chiaki-ng, the open-source PlayStation
# Remote Play client) and every library it depends on as static libraries for
# tvOS. Everything is merged into one static library per platform and packaged
# as deps/out/ChiakiKit.xcframework, which a SwiftUI tvOS app can link and use
# with `import ChiakiKit`.
#
# Usage:  ./build-chiaki-xcframework.sh [--device] [--clean | --clean-all]
#                                       [--jobs N] [--verbose] [--help]
#
# Every download is pinned. Tarballs are checked against the SHA-256 that the
# project publishes. Git sources are checked against a pinned commit hash.
# Python packages are hash-locked (requirements-nanopb.txt). The script never
# runs sudo, never pipes anything into a shell, and keeps all of its files under
# this directory (src/, build/, out/).
#
# Compatible with the bash 3.2 that ships with macOS: no associative arrays, and
# arrays that may be empty are never expanded without a guard.

set -euo pipefail

# ----------------------------------------------------------------------------
# Paths
# ----------------------------------------------------------------------------
DEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${CHIAKI_XCF_SRC_DIR:-$DEPS_DIR/src}"
BUILD_DIR="${CHIAKI_XCF_BUILD_DIR:-$DEPS_DIR/build}"
OUT_DIR="${CHIAKI_XCF_OUT_DIR:-$DEPS_DIR/out}"
DL_DIR="$SRC_DIR/_downloads"
LOG_DIR="$BUILD_DIR/logs"
VENV_DIR="$BUILD_DIR/venv"

PATCH_DIR="$DEPS_DIR/patches"
OPENSSL_TVOS_CONF="$DEPS_DIR/openssl-tvos.conf"
PY_REQUIREMENTS="$DEPS_DIR/requirements-nanopb.txt"

# ----------------------------------------------------------------------------
# Pins. Change versions only together with their hash or commit.
# ----------------------------------------------------------------------------
TVOS_MIN="18.0"

CHIAKI_REPO="https://github.com/chiaki-ng/chiaki-ng.git"
CHIAKI_TAG="v1.10.1"
CHIAKI_COMMIT="f30da0aaeb96fc0026cc03683153f682352e7d7c"
# Key that signed tag v1.10.1 ("Street Pea", EdDSA). Published at
# https://github.com/streetpea.gpg
CHIAKI_TAG_SIGNER_FPR="609B7D18288DF6E62624B0694569A5F4961E8ED9"
CHIAKI_PATCHES="chiaki-ng-v1.10.1-keep-tvos-deployment-target.patch"
# The only submodules libchiaki needs, with the gitlink commits recorded in
# chiaki-ng v1.10.1. The curl submodule (curl 8.11.1) is not used: curl is
# built separately from a newer pinned release (see CURL_* below).
CHIAKI_SUBMODULES="third-party/nanopb:160d4f09e5fabb2b66aa2dea32d4f38ace2c4b3f
third-party/jerasure:505ccb4bc69eee8d7ea40a6089a056b99671134f
third-party/gf-complete:fa54a4670a5705c84abf6c24b92b0cd479625478"

# OpenSSL 3.5 LTS. The SHA-256 is the one published next to the release
# (openssl-3.5.9.tar.gz.sha256 on the GitHub release, linked from
# https://openssl-library.org/source/).
OPENSSL_VERSION="3.5.9"
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
OPENSSL_SHA256="603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a"

# Opus. The SHA-256 comes from https://downloads.xiph.org/releases/opus/SHA256SUMS.txt
OPUS_VERSION="1.6.1"
OPUS_URL="https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz"
OPUS_SHA256="6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1"

# curl's site publishes only PGP signatures, no checksums, so curl is pinned to
# a git tag and its commit.
CURL_VERSION="8.23.0"
CURL_REPO="https://github.com/curl/curl.git"
CURL_TAG="curl-8_23_0"
CURL_COMMIT="3163ec065643ba20709f190111f42c3e1fe95273"

# libevent, json-c and miniupnpc publish no official checksums, so they are
# also pinned to a git tag and its commit.
LIBEVENT_VERSION="2.1.12-stable"
LIBEVENT_REPO="https://github.com/libevent/libevent.git"
LIBEVENT_TAG="release-2.1.12-stable"
LIBEVENT_COMMIT="5df3037d10556bfcb675bc73e516978b75fc7bc7"

JSONC_VERSION="0.18-20240915"
JSONC_REPO="https://github.com/json-c/json-c.git"
JSONC_TAG="json-c-0.18-20240915"
JSONC_COMMIT="41a55cfcedb54d9c1874f2f0eb07b504091d7e37"

MINIUPNPC_VERSION="2.3.5"
MINIUPNPC_REPO="https://github.com/miniupnp/miniupnp.git"
MINIUPNPC_TAG="miniupnpc_2_3_5"
MINIUPNPC_COMMIT="e1db7c47295d38b2b416c892779dae9afa434016"

MIN_CMAKE_VERSION="3.24"   # CMAKE_IGNORE_PREFIX_PATH needs 3.23
MIN_PYTHON_MINOR="10"   # grpcio-tools 1.85 requires Python >= 3.10

# Name of the XCFramework, the Clang/Swift module and the merged library.
MODULE_NAME="ChiakiKit"

# ----------------------------------------------------------------------------
# Options
# ----------------------------------------------------------------------------
BUILD_DEVICE=0
CLEAN=0
CLEAN_ALL=0
VERBOSE=0
JOBS=""

usage() {
	cat <<EOF
Usage: $(basename "$0") [options]

Builds libchiaki (chiaki-ng ${CHIAKI_TAG}) and its dependencies as static
libraries for tvOS (arm64, minimum tvOS ${TVOS_MIN}) and packages them as
  ${OUT_DIR}/${MODULE_NAME}.xcframework

Options:
  --device      Also build the appletvos (real Apple TV) slice. By default
                only the appletvsimulator arm64 slice is built.
  --clean       Delete build/ and out/ first. Verified sources in src/ are
                kept and checked again.
  --clean-all   Delete src/, build/ and out/ first, and download everything
                again.
  --jobs N      Number of parallel compile jobs (default: number of CPUs).
  --verbose     Show full build output on screen. It always goes to
                build/logs/ as well.
  -h, --help    Show this help.

Remote Play over the Internet (RUDP/holepunch) is always compiled in: in
chiaki-ng ${CHIAKI_TAG} the CHIAKI_ENABLE_RUDP option exists but nothing uses
it, and session.c/ctrl.c call the RUDP code directly. So curl, json-c,
miniupnpc and libevent are always required, and there is no --no-rudp switch.

Steps that already finished are skipped when run again. A step's key covers
the pinned version, its options and the steps it depends on, so changing a pin
rebuilds that step and every step that depends on it.
EOF
}

parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
			--device) BUILD_DEVICE=1 ;;
			--clean) CLEAN=1 ;;
			--clean-all) CLEAN=1; CLEAN_ALL=1 ;;
			--jobs)
				[ $# -ge 2 ] || die "--jobs needs a number"
				JOBS="$2"; shift ;;
			--jobs=*) JOBS="${1#--jobs=}" ;;
			--verbose|-v) VERBOSE=1 ;;
			-h|--help) usage; exit 0 ;;
			*) usage >&2; die "unknown option: $1" ;;
		esac
		shift
	done
	if [ -n "$JOBS" ]; then
		case "$JOBS" in
			''|*[!0-9]*) die "--jobs expects a positive integer, got '$JOBS'" ;;
		esac
	fi
}

# ----------------------------------------------------------------------------
# Logging and helpers
# ----------------------------------------------------------------------------
if [ -t 1 ]; then
	C_BOLD=$'\033[1m'; C_RED=$'\033[31m'; C_YEL=$'\033[33m'; C_GRN=$'\033[32m'; C_OFF=$'\033[0m'
else
	C_BOLD=""; C_RED=""; C_YEL=""; C_GRN=""; C_OFF=""
fi

step()  { printf '\n%s==> [%s] %s%s\n' "$C_BOLD" "$(date +%H:%M:%S)" "$*" "$C_OFF"; }
info()  { printf '    %s\n' "$*"; }
ok()    { printf '    %s%s%s\n' "$C_GRN" "$*" "$C_OFF"; }
warn()  { printf '%sWARNING:%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
die()   { printf '%sERROR:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

# run_logged LOGFILE CMD [ARGS...]
# Runs CMD and appends its output to LOGFILE. With --verbose the output is also
# shown on screen. If CMD fails, the end of the log is printed and the script
# stops.
run_logged() {
	local logf="$1"; shift
	mkdir -p "$(dirname "$logf")"
	printf '+ %s\n' "$*" >>"$logf"
	local rc=0
	if [ "$VERBOSE" = 1 ]; then
		"$@" 2>&1 | tee -a "$logf" || rc=$?
	else
		"$@" >>"$logf" 2>&1 || rc=$?
	fi
	if [ "$rc" != 0 ]; then
		printf '%sERROR:%s command failed (exit %s): %s\n' "$C_RED" "$C_OFF" "$rc" "$*" >&2
		printf '       Full log: %s\n       Last 60 lines:\n' "$logf" >&2
		tail -n 60 "$logf" >&2 || true
		exit "$rc"
	fi
}

sha256_file() {
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{print $1}'
	else
		sha256sum "$1" | awk '{print $1}'
	fi
}

sha256_str() {
	if command -v shasum >/dev/null 2>&1; then
		printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
	else
		printf '%s' "$1" | sha256sum | awk '{print $1}'
	fi
}

ncpu() {
	if command -v sysctl >/dev/null 2>&1 && sysctl -n hw.ncpu >/dev/null 2>&1; then
		sysctl -n hw.ncpu
	elif command -v nproc >/dev/null 2>&1; then
		nproc
	else
		echo 4
	fi
}

# version_ge A B: true if version A >= version B (numeric, dot-separated)
version_ge() {
	[ "$(printf '%s\n%s\n' "$2" "$1" | sort -t. -k1,1n -k2,2n -k3,3n | head -n1)" = "$2" ]
}

# Step stamps. A step is skipped when its stamp file holds the same key.
stamp_path() { printf '%s/%s.stamp' "$SLICE_STAMPS" "$1"; }
stamp_ok() {
	local f; f="$(stamp_path "$1")"
	[ -f "$f" ] && [ "$(cat "$f")" = "$2" ]
}
stamp_set() { mkdir -p "$SLICE_STAMPS"; printf '%s' "$2" >"$(stamp_path "$1")"; }

# Joins all arguments into one string and returns its SHA-256. Used to build
# step keys.
key_of() {
	local IFS='|'
	sha256_str "$*"
}

# ----------------------------------------------------------------------------
# Prerequisites
# ----------------------------------------------------------------------------
sanitize_env() {
	# Compiler and SDK variables from the user's shell would leak into
	# OpenSSL's Configure and the CMake builds, so they are cleared.
	unset CC CXX CPP LD AR RANLIB CFLAGS CXXFLAGS CPPFLAGS LDFLAGS OBJCFLAGS \
		SDKROOT MACOSX_DEPLOYMENT_TARGET TVOS_DEPLOYMENT_TARGET \
		IPHONEOS_DEPLOYMENT_TARGET CMAKE_TOOLCHAIN_FILE CMAKE_PREFIX_PATH \
		CMAKE_GENERATOR PKG_CONFIG_SYSROOT_DIR OPENSSL_ROOT_DIR \
		PYTHONHOME PYTHONPATH 2>/dev/null || true
	export LC_ALL=C
}

check_prereqs() {
	step "Checking prerequisites"
	[ "$(uname -s)" = "Darwin" ] || die "this script must run on macOS (found $(uname -s))."

	local devdir
	devdir="$(xcode-select -p 2>/dev/null || true)"
	if [ -z "$devdir" ]; then
		die "no developer directory is selected. Install Xcode from the App Store, then run:
       sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
	fi
	case "$devdir" in
		*CommandLineTools*)
			die "xcode-select points to the Command Line Tools ($devdir). The tvOS SDKs ship only with full Xcode. Run:
       sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" ;;
	esac
	info "Xcode: $devdir ($(xcodebuild -version 2>/dev/null | tr '\n' ' '))"

	local sdk
	for sdk in $SDKS_TO_BUILD; do
		if ! xcrun --sdk "$sdk" --show-sdk-path >/dev/null 2>&1; then
			die "the $sdk SDK was not found. In Xcode, open Settings > Components and install the tvOS platform (or run: xcodebuild -downloadPlatform tvOS)."
		fi
		info "SDK $sdk: $(xcrun --sdk "$sdk" --show-sdk-version) at $(xcrun --sdk "$sdk" --show-sdk-path)"
	done

	local missing="" tool
	for tool in cmake ninja pkg-config python3 git perl make curl tar; do
		command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
	done
	if [ -n "$missing" ]; then
		local brew_pkgs="" t
		for t in $missing; do
			case "$t" in
				pkg-config) brew_pkgs="$brew_pkgs pkgconf" ;;
				python3) brew_pkgs="$brew_pkgs python" ;;
				cmake|ninja|git) brew_pkgs="$brew_pkgs $t" ;;
			esac
		done
		if [ -n "$brew_pkgs" ]; then
			die "missing tools:$missing
       Install them with Homebrew:  brew install$brew_pkgs
       (perl, make, curl and tar come with macOS and Xcode.)"
		fi
		die "missing tools:$missing (these ship with macOS/Xcode; check your PATH)."
	fi

	local cmv
	cmv="$(cmake --version | head -n1 | awk '{print $3}')"
	version_ge "$cmv" "$MIN_CMAKE_VERSION" || die "CMake $cmv is too old; $MIN_CMAKE_VERSION or newer is needed (brew upgrade cmake)."
	info "cmake $cmv, ninja $(ninja --version), pkg-config $(pkg-config --version)"

	local pyminor
	pyminor="$(python3 -c 'import sys; print(sys.version_info[1] if sys.version_info[0]==3 else 0)')"
	if [ "$pyminor" -lt "$MIN_PYTHON_MINOR" ]; then
		die "python3 is $(python3 -V 2>&1); 3.${MIN_PYTHON_MINOR}+ is needed for the nanopb generator (brew install python, then make sure $(brew --prefix 2>/dev/null || echo /opt/homebrew)/bin comes first in PATH)."
	fi
	info "$(python3 -V 2>&1) at $(command -v python3)"

	if ! command -v gpg >/dev/null 2>&1; then
		warn "gpg was not found, so the signature on chiaki-ng tag $CHIAKI_TAG cannot be checked (brew install gnupg). The pinned commit hash is still checked."
	fi
	[ -f "$OPENSSL_TVOS_CONF" ] || die "missing $OPENSSL_TVOS_CONF"
	[ -f "$PY_REQUIREMENTS" ] || die "missing $PY_REQUIREMENTS"
	local p
	for p in $CHIAKI_PATCHES; do
		[ -f "$PATCH_DIR/$p" ] || die "missing patch $PATCH_DIR/$p"
	done
	ok "prerequisites OK"
}

# ----------------------------------------------------------------------------
# Fetching and verification
# ----------------------------------------------------------------------------

# fetch_tarball URL SHA256 DEST_DIR
# Downloads URL over HTTPS (redirects must stay on HTTPS), checks its SHA-256,
# and only then unpacks it into DEST_DIR without the top-level folder.
fetch_tarball() {
	local url="$1" sha="$2" dest="$3"
	local file="$DL_DIR/${url##*/}"
	local marker="$dest/.chiaki-xcf-sha256"
	mkdir -p "$DL_DIR"

	if [ -f "$marker" ] && [ "$(cat "$marker")" = "$sha" ] && [ -f "$file" ] \
		&& [ "$(sha256_file "$file")" = "$sha" ]; then
		info "already verified: ${url##*/}"
		return 0
	fi

	if [ ! -f "$file" ] || [ "$(sha256_file "$file")" != "$sha" ]; then
		info "downloading $url"
		rm -f "$file.part"
		curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
			--retry 3 --retry-delay 2 --silent --show-error \
			--output "$file.part" "$url"
		local got; got="$(sha256_file "$file.part")"
		if [ "$got" != "$sha" ]; then
			rm -f "$file.part"
			die "SHA-256 mismatch for ${url##*/}
       expected $sha
       got      $got"
		fi
		mv "$file.part" "$file"
	fi
	ok "SHA-256 verified: ${url##*/} ($sha)"

	rm -rf "$dest" "$dest.tmp"
	mkdir -p "$dest.tmp"
	tar -xf "$file" -C "$dest.tmp" --strip-components=1
	printf '%s' "$sha" >"$dest.tmp/.chiaki-xcf-sha256"
	mv "$dest.tmp" "$dest"
}

# git_head_commit DIR: commit hash of HEAD
git_head_commit() { git -C "$1" rev-parse --verify 'HEAD^{commit}'; }

# fetch_git_pinned URL TAG COMMIT DEST_DIR
# Shallow-clones TAG and checks that it resolves to COMMIT and that the work
# tree has no local changes.
fetch_git_pinned() {
	local url="$1" tag="$2" commit="$3" dest="$4"
	if [ ! -d "$dest/.git" ]; then
		info "cloning $url @ $tag"
		rm -rf "$dest.tmp"
		git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" \
			--no-recurse-submodules "$url" "$dest.tmp"
		mv "$dest.tmp" "$dest"
	fi
	local head; head="$(git_head_commit "$dest")"
	if [ "$head" != "$commit" ]; then
		die "$dest: HEAD is $head but $tag is pinned to $commit. Delete $dest (or run --clean-all) and try again; if it happens again, the upstream tag has moved."
	fi
	if [ -n "$(git -C "$dest" status --porcelain --untracked-files=no)" ]; then
		die "$dest has local changes; remove it or run --clean-all."
	fi
	ok "commit verified: ${url##*/} $tag = $commit"
}

verify_chiaki_tag() {
	local dir="$1"
	local import_hint="       To check the tag signature, import the maintainer's key and run again:
         curl -s https://github.com/streetpea.gpg | gpg --import
       Expected fingerprint: $CHIAKI_TAG_SIGNER_FPR"
	if ! command -v gpg >/dev/null 2>&1; then
		warn "gpg is not installed; skipping 'git verify-tag $CHIAKI_TAG' (the commit hash was checked).
$import_hint"
		return 0
	fi
	local out rc=0
	out="$(git -C "$dir" verify-tag --raw "$CHIAKI_TAG" 2>&1)" || rc=$?
	if [ "$rc" = 0 ]; then
		if printf '%s\n' "$out" | grep -q "VALIDSIG.*$CHIAKI_TAG_SIGNER_FPR"; then
			ok "tag $CHIAKI_TAG has a good signature from $CHIAKI_TAG_SIGNER_FPR"
		else
			die "tag $CHIAKI_TAG has a valid signature, but not from the expected key $CHIAKI_TAG_SIGNER_FPR:
$out"
		fi
	elif printf '%s\n' "$out" | grep -q 'NO_PUBKEY\|No public key'; then
		warn "could not check the signature on tag $CHIAKI_TAG because the signing key is not in your keyring (the commit hash was checked).
$import_hint"
	else
		die "signature check failed for tag $CHIAKI_TAG:
$out"
	fi
}

fetch_chiaki() {
	step "Fetching chiaki-ng $CHIAKI_TAG"
	local dir="$SRC_DIR/chiaki-ng"
	if [ ! -d "$dir/.git" ]; then
		info "cloning $CHIAKI_REPO @ $CHIAKI_TAG"
		rm -rf "$dir.tmp"
		git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$CHIAKI_TAG" \
			--no-recurse-submodules "$CHIAKI_REPO" "$dir.tmp"
		mv "$dir.tmp" "$dir"
	fi
	local head tagc
	head="$(git_head_commit "$dir")"
	[ "$head" = "$CHIAKI_COMMIT" ] || die "chiaki-ng HEAD is $head, expected $CHIAKI_COMMIT. Run --clean-all."
	tagc="$(git -C "$dir" rev-parse --verify "refs/tags/$CHIAKI_TAG^{commit}" 2>/dev/null || true)"
	[ "$tagc" = "$CHIAKI_COMMIT" ] || die "tag $CHIAKI_TAG resolves to '$tagc', expected $CHIAKI_COMMIT."
	ok "commit verified: chiaki-ng $CHIAKI_TAG = $CHIAKI_COMMIT"
	verify_chiaki_tag "$dir"

	# Initialise only the submodules libchiaki needs, and check each one.
	local entry path want recorded have
	for entry in $CHIAKI_SUBMODULES; do
		path="${entry%%:*}"; want="${entry#*:}"
		recorded="$(git -C "$dir" ls-tree HEAD "$path" | awk '{print $3}')"
		[ "$recorded" = "$want" ] || die "submodule $path is recorded as '$recorded' in chiaki-ng, but $want is pinned here."
		have="$(git -C "$dir/$path" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || true)"
		if [ "$have" != "$want" ]; then
			info "initialising submodule $path"
			git -C "$dir" -c advice.detachedHead=false submodule --quiet update --init --depth 1 -- "$path" \
				|| git -C "$dir" -c advice.detachedHead=false submodule --quiet update --init -- "$path"
			have="$(git -C "$dir/$path" rev-parse --verify 'HEAD^{commit}')"
		fi
		[ "$have" = "$want" ] || die "submodule $path is at $have, expected $want."
		if [ -n "$(git -C "$dir/$path" status --porcelain --untracked-files=no)" ]; then
			die "submodule $path has local changes; run --clean-all."
		fi
		ok "submodule verified: $path = $want"
	done

	# Apply the local patches, each only once.
	local p pf
	for p in $CHIAKI_PATCHES; do
		pf="$PATCH_DIR/$p"
		if git -C "$dir" apply --reverse --check "$pf" >/dev/null 2>&1; then
			info "patch already applied: $p"
		else
			git -C "$dir" apply --check "$pf" || die "patch $p does not apply to chiaki-ng $CHIAKI_TAG; run --clean-all."
			git -C "$dir" apply "$pf"
			ok "applied patch: $p"
		fi
	done
	# Only the patched files may differ from the pinned commit.
	local changed
	changed="$(git -C "$dir" status --porcelain --untracked-files=no --ignore-submodules=all | awk '{print $2}' | tr '\n' ' ')"
	[ "$changed" = "CMakeLists.txt " ] || [ -z "$changed" ] || die "unexpected changes in chiaki-ng: $changed (run --clean-all)."
	CHIAKI_SRC="$dir"
}

fetch_deps() {
	step "Fetching dependencies"
	fetch_openssl_src
	fetch_opus_src
	fetch_git_pinned "$CURL_REPO" "$CURL_TAG" "$CURL_COMMIT" "$SRC_DIR/curl-$CURL_VERSION"
	CURL_SRC="$SRC_DIR/curl-$CURL_VERSION"
	fetch_git_pinned "$LIBEVENT_REPO" "$LIBEVENT_TAG" "$LIBEVENT_COMMIT" "$SRC_DIR/libevent-$LIBEVENT_VERSION"
	LIBEVENT_SRC="$SRC_DIR/libevent-$LIBEVENT_VERSION"
	fetch_git_pinned "$JSONC_REPO" "$JSONC_TAG" "$JSONC_COMMIT" "$SRC_DIR/json-c-$JSONC_VERSION"
	JSONC_SRC="$SRC_DIR/json-c-$JSONC_VERSION"
	fetch_git_pinned "$MINIUPNPC_REPO" "$MINIUPNPC_TAG" "$MINIUPNPC_COMMIT" "$SRC_DIR/miniupnp-$MINIUPNPC_VERSION"
	MINIUPNPC_SRC="$SRC_DIR/miniupnp-$MINIUPNPC_VERSION/miniupnpc"
}

fetch_openssl_src() {
	OPENSSL_SRC="$SRC_DIR/openssl-$OPENSSL_VERSION"
	fetch_tarball "$OPENSSL_URL" "$OPENSSL_SHA256" "$OPENSSL_SRC"
}

fetch_opus_src() {
	OPUS_SRC="$SRC_DIR/opus-$OPUS_VERSION"
	fetch_tarball "$OPUS_URL" "$OPUS_SHA256" "$OPUS_SRC"
}

# ----------------------------------------------------------------------------
# Python venv for nanopb (protoc + protobuf runtime, hash-locked)
# ----------------------------------------------------------------------------
setup_venv() {
	step "Python venv for the nanopb generator"
	local key; key="$(key_of "venv" "$(sha256_file "$PY_REQUIREMENTS")" "$(python3 -c 'import sys; print(sys.version)')")"
	if [ -f "$VENV_DIR/.chiaki-xcf-key" ] && [ "$(cat "$VENV_DIR/.chiaki-xcf-key")" = "$key" ] \
		&& "$VENV_DIR/bin/python3" -I -c 'import grpc_tools.protoc, google.protobuf' >/dev/null 2>&1; then
		info "venv up to date: $VENV_DIR"
	else
		rm -rf "$VENV_DIR"
		run_logged "$LOG_DIR/venv.log" python3 -m venv "$VENV_DIR"
		run_logged "$LOG_DIR/venv.log" "$VENV_DIR/bin/python3" -m pip install \
			--disable-pip-version-check --no-input --require-hashes --only-binary=:all: \
			-r "$PY_REQUIREMENTS"
		"$VENV_DIR/bin/python3" -I -c 'import grpc_tools.protoc, google.protobuf' \
			|| die "the venv is missing grpc_tools/protobuf; see $LOG_DIR/venv.log"
		printf '%s' "$key" >"$VENV_DIR/.chiaki-xcf-key"
	fi
	# nanopb's generator/protoc wrapper starts with "#!/usr/bin/env python3",
	# so the venv must come first in PATH while chiaki is configured and built.
	PATH="$VENV_DIR/bin:$PATH"
	export PATH
	ok "$("$VENV_DIR/bin/python3" -I -c 'import google.protobuf as p; import grpc_tools; from importlib.metadata import version; print("protobuf", p.__version__, "/ grpcio-tools", version("grpcio-tools"))')"
}

# ----------------------------------------------------------------------------
# Per-slice configuration
# ----------------------------------------------------------------------------

# slice_setup NAME: sets the variables used by the build steps for one slice.
slice_setup() {
	SLICE="$1"
	case "$SLICE" in
		appletvsimulator)
			SLICE_MIN_FLAG="-mtvos-simulator-version-min=$TVOS_MIN"
			SLICE_OPENSSL_TARGET="tvossimulator-arm64-xcrun"
			SLICE_CLANG_TARGET="arm64-apple-tvos${TVOS_MIN}-simulator"
			SLICE_EXPECT_PLATFORM="TVOSSIMULATOR"
			;;
		appletvos)
			SLICE_MIN_FLAG="-mtvos-version-min=$TVOS_MIN"
			SLICE_OPENSSL_TARGET="tvos64-xcrun"
			SLICE_CLANG_TARGET="arm64-apple-tvos${TVOS_MIN}"
			SLICE_EXPECT_PLATFORM="TVOS"
			;;
		*) die "unknown slice $SLICE" ;;
	esac
	SLICE_SDK_PATH="$(xcrun --sdk "$SLICE" --show-sdk-path)"
	SLICE_CC="$(xcrun --sdk "$SLICE" --find clang)"
	SLICE_CXX="$(xcrun --sdk "$SLICE" --find clang++)"
	SLICE_DIR="$BUILD_DIR/$SLICE"
	SLICE_PREFIX="$SLICE_DIR/prefix"
	SLICE_STAMPS="$SLICE_DIR/stamps"
	SLICE_PKG="$SLICE_DIR/package"
	mkdir -p "$SLICE_PREFIX/lib/pkgconfig" "$SLICE_STAMPS" "$LOG_DIR"

	# pkg-config may only see .pc files of this slice, never Homebrew's macOS ones.
	PKG_CONFIG_LIBDIR="$SLICE_PREFIX/lib/pkgconfig:$SLICE_PREFIX/share/pkgconfig"
	PKG_CONFIG_PATH=""
	export PKG_CONFIG_LIBDIR PKG_CONFIG_PATH
}

# CMake arguments that make a project cross-compile for the current slice.
# CMake's tvOS support sets CMAKE_FIND_ROOT_PATH to the SDK with
# CMAKE_FIND_ROOT_PATH_MODE_{LIBRARY,INCLUDE,PACKAGE}=ONLY, so the slice prefix
# is added to the root path too. That way the dependencies we built are found,
# and nothing from Homebrew or the host system is.
cmake_platform_args() {
	printf '%s\n' \
		"-DCMAKE_SYSTEM_NAME=tvOS" \
		"-DCMAKE_SYSTEM_PROCESSOR=aarch64" \
		"-DCMAKE_OSX_SYSROOT=$SLICE_SDK_PATH" \
		"-DCMAKE_OSX_ARCHITECTURES=arm64" \
		"-DCMAKE_OSX_DEPLOYMENT_TARGET=$TVOS_MIN" \
		"-DCMAKE_C_COMPILER=$SLICE_CC" \
		"-DCMAKE_CXX_COMPILER=$SLICE_CXX" \
		"-DCMAKE_FIND_ROOT_PATH=$SLICE_PREFIX" \
		"-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local;/opt/local"
}

cmake_common_args() {
	printf '%s\n' \
		"-GNinja" \
		"-DCMAKE_BUILD_TYPE=Release" \
		"-DCMAKE_INSTALL_PREFIX=$SLICE_PREFIX" \
		"-DCMAKE_INSTALL_LIBDIR=lib" \
		"-DCMAKE_PREFIX_PATH=$SLICE_PREFIX" \
		"-DBUILD_SHARED_LIBS=OFF" \
		"-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
	cmake_platform_args
}

# cmake_project NAME SRC_DIR [EXTRA_ARGS...]
# Configures, builds and installs a CMake project out of tree in the slice's
# build directory.
cmake_project() {
	local name="$1" src="$2"; shift 2
	local bdir="$SLICE_DIR/$name" logf="$LOG_DIR/$SLICE-$name.log"
	local -a args=()
	local line
	while IFS= read -r line; do args+=("$line"); done < <(cmake_common_args)
	rm -rf "$bdir"; : >"$logf"
	info "configure (log: $logf)"
	run_logged "$logf" cmake -S "$src" -B "$bdir" "${args[@]}" "$@"
	warn_unused_cmake_vars "$logf" "$name"
	info "build"
	run_logged "$logf" cmake --build "$bdir" --parallel "$JOBS"
	info "install -> $SLICE_PREFIX"
	run_logged "$logf" cmake --install "$bdir"
}

# CMake says "Manually-specified variables were not used by the project" when
# an option name does not exist (for example after a rename upstream). The
# message is shown so that such a change is not missed.
warn_unused_cmake_vars() {
	local logf="$1" name="$2"
	if grep -q 'Manually-specified variables were not used' "$logf"; then
		local vars
		vars="$(awk '/Manually-specified variables were not used/{f=1;next} f&&/^ *$/{if(seen)exit;next} f{seen=1;gsub(/^ +/,"");print}' "$logf" | tr '\n' ' ')"
		info "note: $name did not use these -D options: $vars"
	fi
}

# Key of the toolchain/SDK for the current slice. Part of every step key.
slice_toolchain_key() {
	key_of "$SLICE" "$TVOS_MIN" "$SLICE_SDK_PATH" "$(xcrun --sdk "$SLICE" --show-sdk-version 2>/dev/null || true)" \
		"$("$SLICE_CC" --version 2>/dev/null | head -n1)" "$(cmake --version | head -n1)"
}

# ----------------------------------------------------------------------------
# Dependency builds (one slice at a time)
# ----------------------------------------------------------------------------
OPENSSL_OPTIONS="no-shared no-tests no-apps no-docs no-engine no-legacy no-module no-async no-ui-console"

openssl_configure_target() { printf '%s' "$SLICE_OPENSSL_TARGET"; }
openssl_platform_flags() { printf '%s\n' "$SLICE_MIN_FLAG"; }

build_openssl() {
	step "[$SLICE] OpenSSL $OPENSSL_VERSION"
	local key; key="$(key_of openssl "$OPENSSL_VERSION" "$OPENSSL_SHA256" "$OPENSSL_OPTIONS" \
		"$(sha256_file "$OPENSSL_TVOS_CONF")" "$(openssl_configure_target)" "$TOOLCHAIN_KEY")"
	KEY_OPENSSL="$key"
	if stamp_ok openssl "$key" && [ -f "$SLICE_PREFIX/lib/libcrypto.a" ] && [ -f "$SLICE_PREFIX/lib/libssl.a" ]; then
		info "up to date, skipping"; return 0
	fi
	local bdir="$SLICE_DIR/openssl" logf="$LOG_DIR/$SLICE-openssl.log"
	rm -rf "$bdir"; mkdir -p "$bdir"; : >"$logf"
	local -a pflags=()
	local line
	while IFS= read -r line; do [ -n "$line" ] && pflags+=("$line"); done < <(openssl_platform_flags)
	info "configure target $(openssl_configure_target) (log: $logf)"
	# shellcheck disable=SC2086 # OPENSSL_OPTIONS is a word list and is split on purpose
	(cd "$bdir" && run_logged "$logf" perl "$OPENSSL_SRC/Configure" \
		"--config=$OPENSSL_TVOS_CONF" "$(openssl_configure_target)" $OPENSSL_OPTIONS \
		"--prefix=$SLICE_PREFIX" "--openssldir=/etc/ssl" "--libdir=lib" \
		${pflags[@]+"${pflags[@]}"})
	info "build"
	(cd "$bdir" && run_logged "$logf" make -j "$JOBS" build_libs)
	info "install headers and static libraries -> $SLICE_PREFIX"
	(cd "$bdir" && run_logged "$logf" make install_dev)
	stamp_set openssl "$key"
	ok "OpenSSL done"
}

build_opus() {
	step "[$SLICE] Opus $OPUS_VERSION"
	local -a opts=(
		-DOPUS_BUILD_SHARED_LIBRARY=OFF
		-DOPUS_BUILD_TESTING=OFF
		-DOPUS_BUILD_PROGRAMS=OFF
		-DOPUS_BUILD_FRAMEWORK=OFF
		-DOPUS_INSTALL_PKG_CONFIG_MODULE=ON
		-DOPUS_INSTALL_CMAKE_CONFIG_MODULE=ON
		-DOPUS_DRED=OFF
		-DOPUS_OSCE=OFF
		-DBUILD_TESTING=OFF
	)
	local key; key="$(key_of opus "$OPUS_VERSION" "$OPUS_SRC_ID" "${opts[*]}" "$TOOLCHAIN_KEY")"
	KEY_OPUS="$key"
	if stamp_ok opus "$key" && [ -f "$SLICE_PREFIX/lib/libopus.a" ]; then
		info "up to date, skipping"; return 0
	fi
	cmake_project opus "$OPUS_SRC" "${opts[@]}"
	stamp_set opus "$key"
	ok "Opus done"
}

# Platform-specific curl options. tvOS has no system CA bundle file, so curl is
# built with Apple SecTrust: when the app does not set its own CA file, curl
# checks server certificates against the OS trust store. Needs curl >= 8.17.
curl_platform_args() {
	printf '%s\n' "-DUSE_APPLE_SECTRUST=ON" "-DUSE_APPLE_IDN=OFF"
	# With SecTrust on, curl's CMake also looks up CoreServices.framework,
	# although libcurl calls nothing from it. If an SDK does not have it,
	# CoreFoundation is put in its place so that configure can go on.
	if [ ! -d "$SLICE_SDK_PATH/System/Library/Frameworks/CoreServices.framework" ]; then
		warn "CoreServices.framework is not in $SLICE_SDK_PATH; telling curl's CMake to use CoreFoundation instead (libcurl does not call CoreServices)."
		printf '%s\n' "-DCORESERVICES_FRAMEWORK=$SLICE_SDK_PATH/System/Library/Frameworks/CoreFoundation.framework"
	fi
}

build_curl() {
	step "[$SLICE] curl $CURL_VERSION (HTTP/HTTPS/WebSocket only, OpenSSL)"
	local -a opts=(
		-DBUILD_STATIC_LIBS=ON
		-DBUILD_CURL_EXE=OFF
		-DBUILD_TESTING=OFF
		-DBUILD_EXAMPLES=OFF
		-DBUILD_LIBCURL_DOCS=OFF
		-DBUILD_MISC_DOCS=OFF
		-DENABLE_CURL_MANUAL=OFF
		-DCURL_DISABLE_INSTALL=OFF
		-DPICKY_COMPILER=OFF
		-DCURL_ENABLE_SSL=ON
		-DCURL_USE_OPENSSL=ON
		"-DOPENSSL_ROOT_DIR=$SLICE_PREFIX"
		-DOPENSSL_USE_STATIC_LIBS=ON
		-DCURL_CA_BUNDLE=none
		-DCURL_CA_PATH=none
		-DCURL_CA_FALLBACK=OFF
		-DCURL_USE_LIBPSL=OFF
		-DUSE_LIBIDN2=OFF
		-DCURL_USE_LIBSSH2=OFF
		-DCURL_USE_LIBSSH=OFF
		-DCURL_USE_GSSAPI=OFF
		-DCURL_USE_GSASL=OFF
		-DCURL_ZLIB=OFF
		-DCURL_BROTLI=OFF
		-DCURL_ZSTD=OFF
		-DUSE_NGHTTP2=OFF
		-DUSE_NGTCP2=OFF
		-DUSE_QUICHE=OFF
		-DENABLE_ARES=OFF
		-DENABLE_THREADED_RESOLVER=ON
		-DENABLE_UNIX_SOCKETS=OFF
		-DCURL_DISABLE_WEBSOCKETS=OFF
		-DCURL_DISABLE_ALTSVC=ON
		-DCURL_DISABLE_AWS=ON
		-DCURL_DISABLE_DICT=ON
		-DCURL_DISABLE_DOH=ON
		-DCURL_DISABLE_FILE=ON
		-DCURL_DISABLE_FTP=ON
		-DCURL_DISABLE_GOPHER=ON
		-DCURL_DISABLE_IMAP=ON
		-DCURL_DISABLE_IPFS=ON
		-DCURL_DISABLE_LDAP=ON
		-DCURL_DISABLE_LDAPS=ON
		-DCURL_DISABLE_MQTT=ON
		-DCURL_DISABLE_NETRC=ON
		-DCURL_DISABLE_POP3=ON
		-DCURL_DISABLE_RTSP=ON
		-DCURL_DISABLE_SMTP=ON
		-DCURL_DISABLE_TELNET=ON
		-DCURL_DISABLE_TFTP=ON
		-DCURL_DISABLE_KERBEROS_AUTH=ON
		-DCURL_DISABLE_NEGOTIATE_AUTH=ON
		-DCURL_ENABLE_NTLM=OFF
	)
	local line
	while IFS= read -r line; do [ -n "$line" ] && opts+=("$line"); done < <(curl_platform_args)
	local key; key="$(key_of curl "$CURL_COMMIT" "${opts[*]}" "$KEY_OPENSSL" "$TOOLCHAIN_KEY")"
	KEY_CURL="$key"
	if stamp_ok curl "$key" && [ -f "$SLICE_PREFIX/lib/libcurl.a" ]; then
		info "up to date, skipping"; return 0
	fi
	cmake_project curl "$CURL_SRC" "${opts[@]}"
	stamp_set curl "$key"
	ok "curl done"
}

build_libevent() {
	step "[$SLICE] libevent $LIBEVENT_VERSION (core only, no OpenSSL)"
	local -a opts=(
		-DEVENT__LIBRARY_TYPE=STATIC
		-DEVENT__DISABLE_OPENSSL=ON
		-DEVENT__DISABLE_BENCHMARK=ON
		-DEVENT__DISABLE_TESTS=ON
		-DEVENT__DISABLE_REGRESS=ON
		-DEVENT__DISABLE_SAMPLES=ON
	)
	local key; key="$(key_of libevent "$LIBEVENT_COMMIT" "${opts[*]}" "$TOOLCHAIN_KEY")"
	KEY_LIBEVENT="$key"
	if stamp_ok libevent "$key" && [ -f "$SLICE_PREFIX/lib/libevent_core.a" ]; then
		info "up to date, skipping"; return 0
	fi
	cmake_project libevent "$LIBEVENT_SRC" "${opts[@]}"
	stamp_set libevent "$key"
	ok "libevent done"
}

build_jsonc() {
	step "[$SLICE] json-c $JSONC_VERSION"
	local -a opts=(
		-DBUILD_STATIC_LIBS=ON
		-DBUILD_TESTING=OFF
		-DBUILD_APPS=OFF
		-DDISABLE_WERROR=ON
		-DDISABLE_EXTRA_LIBS=ON
	)
	local key; key="$(key_of jsonc "$JSONC_COMMIT" "${opts[*]}" "$TOOLCHAIN_KEY")"
	KEY_JSONC="$key"
	if stamp_ok jsonc "$key" && [ -f "$SLICE_PREFIX/lib/libjson-c.a" ]; then
		info "up to date, skipping"; return 0
	fi
	cmake_project json-c "$JSONC_SRC" "${opts[@]}"
	stamp_set jsonc "$key"
	ok "json-c done"
}

build_miniupnpc() {
	step "[$SLICE] miniupnpc $MINIUPNPC_VERSION"
	local -a opts=(
		-DUPNPC_BUILD_STATIC=ON
		-DUPNPC_BUILD_SHARED=OFF
		-DUPNPC_BUILD_TESTS=OFF
		-DUPNPC_BUILD_SAMPLE=OFF
	)
	local key; key="$(key_of miniupnpc "$MINIUPNPC_COMMIT" "${opts[*]}" "$TOOLCHAIN_KEY")"
	KEY_MINIUPNPC="$key"
	if stamp_ok miniupnpc "$key" && [ -f "$SLICE_PREFIX/lib/libminiupnpc.a" ]; then
		info "up to date, skipping"; return 0
	fi
	cmake_project miniupnpc "$MINIUPNPC_SRC" "${opts[@]}"
	stamp_set miniupnpc "$key"
	ok "miniupnpc done"
}

# ----------------------------------------------------------------------------
# libchiaki
# ----------------------------------------------------------------------------
chiaki_cmake_options() {
	printf '%s\n' \
		-DCHIAKI_ENABLE_GUI=OFF \
		-DCHIAKI_ENABLE_CLI=OFF \
		-DCHIAKI_ENABLE_TESTS=OFF \
		-DCHIAKI_ENABLE_ANDROID=OFF \
		-DCHIAKI_ENABLE_BOREALIS=OFF \
		-DCHIAKI_ENABLE_SETSU=OFF \
		-DCHIAKI_ENABLE_STEAMDECK_NATIVE=OFF \
		-DCHIAKI_ENABLE_STEAM_SHORTCUT=OFF \
		-DCHIAKI_ENABLE_SPEEX=OFF \
		-DCHIAKI_ENABLE_FFMPEG_DECODER=OFF \
		-DCHIAKI_ENABLE_PI_DECODER=OFF \
		-DCHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER=OFF \
		-DCHIAKI_ENABLE_RUDP=ON \
		-DCHIAKI_LIB_ENABLE_OPUS=ON \
		-DCHIAKI_LIB_ENABLE_MBEDTLS=OFF \
		-DCHIAKI_LIB_MBEDTLS_EXTERNAL_PROJECT=OFF \
		-DCHIAKI_LIB_OPENSSL_EXTERNAL_PROJECT=OFF \
		-DCHIAKI_LIB_JSONC_EXTERNAL_PROJECT=OFF \
		-DCHIAKI_LIB_MINIUPNPC_EXTERNAL_PROJECT=OFF \
		-DCHIAKI_USE_SYSTEM_JERASURE=OFF \
		-DCHIAKI_USE_SYSTEM_NANOPB=OFF \
		-DCHIAKI_USE_SYSTEM_CURL=ON \
		"-DOPENSSL_ROOT_DIR=$SLICE_PREFIX" \
		-DOPENSSL_USE_STATIC_LIBS=ON \
		"-DPYTHON_EXECUTABLE=$VENV_DIR/bin/python3" \
		"-DPython_EXECUTABLE=$VENV_DIR/bin/python3" \
		"-DPROTOC=$CHIAKI_SRC/third-party/nanopb/generator/protoc" \
		"-Dnanopb_PROTOC_PATH=$CHIAKI_SRC/third-party/nanopb/generator/protoc" \
		-Dnanopb_BUILD_GENERATOR=OFF
}

build_chiaki() {
	step "[$SLICE] libchiaki (chiaki-ng $CHIAKI_TAG)"
	local -a opts=()
	local line
	while IFS= read -r line; do opts+=("$line"); done < <(chiaki_cmake_options)
	local pk="" p
	for p in $CHIAKI_PATCHES; do pk="$pk$(sha256_file "$PATCH_DIR/$p")"; done
	local key; key="$(key_of chiaki "$CHIAKI_COMMIT" "$pk" "${opts[*]}" "$KEY_OPENSSL" "$KEY_OPUS" \
		"$KEY_CURL" "$KEY_LIBEVENT" "$KEY_JSONC" "$KEY_MINIUPNPC" "$TOOLCHAIN_KEY")"
	CHIAKI_BUILD="$SLICE_DIR/chiaki"
	if stamp_ok chiaki "$key" && [ -f "$CHIAKI_BUILD/lib/libchiaki.a" ]; then
		info "up to date, skipping"; return 0
	fi
	local bdir="$CHIAKI_BUILD" logf="$LOG_DIR/$SLICE-chiaki.log"
	local -a args=()
	while IFS= read -r line; do args+=("$line"); done < <(cmake_common_args)
	rm -rf "$bdir"; : >"$logf"
	info "configure (log: $logf)"
	run_logged "$logf" cmake -S "$CHIAKI_SRC" -B "$bdir" "${args[@]}" "${opts[@]}"
	warn_unused_cmake_vars "$logf" chiaki
	# Make sure the dependencies we built were picked up, not other copies.
	if grep -q 'Found OpenSSL' "$logf" && ! grep 'Found OpenSSL' "$logf" | grep -qF "$SLICE_PREFIX"; then
		die "chiaki's CMake found an OpenSSL outside $SLICE_PREFIX; see $logf"
	fi
	info "build (generates takion.pb.c/.h with nanopb, then compiles libchiaki)"
	run_logged "$logf" cmake --build "$bdir" --parallel "$JOBS" --target chiaki-lib
	[ -f "$bdir/lib/libchiaki.a" ] || die "libchiaki.a was not produced; see $logf"
	stamp_set chiaki "$key"
	ok "libchiaki done"
}

# ----------------------------------------------------------------------------
# Packaging
# ----------------------------------------------------------------------------

# Prints the static libraries that go into the merged library, in link order.
slice_static_libs() {
	local f
	for f in \
		"$CHIAKI_BUILD/lib/libchiaki.a" \
		"$CHIAKI_BUILD/third-party/libjerasure.a" \
		"$CHIAKI_BUILD/third-party/libgf_complete.a" \
		"$CHIAKI_BUILD/third-party/nanopb/libprotobuf-nanopb.a" \
		"$SLICE_PREFIX/lib/libcurl.a" \
		"$SLICE_PREFIX/lib/libssl.a" \
		"$SLICE_PREFIX/lib/libcrypto.a" \
		"$SLICE_PREFIX/lib/libopus.a" \
		"$SLICE_PREFIX/lib/libevent_core.a" \
		"$SLICE_PREFIX/lib/libjson-c.a" \
		"$SLICE_PREFIX/lib/libminiupnpc.a"
	do
		[ -f "$f" ] || die "expected static library not found: $f"
		printf '%s\n' "$f"
	done
}

# merge_static_libs OUTPUT INPUT...
merge_static_libs() {
	local out="$1"; shift
	rm -f "$out"
	run_logged "$LOG_DIR/$SLICE-package.log" xcrun --sdk "$SLICE" libtool -static -no_warning_for_no_symbols -o "$out" "$@"
}

# Public headers: lib/include/chiaki minus the decoders that are switched off
# (their headers include FFmpeg / Raspberry Pi headers that are not here), plus
# the generated config.h, which takes the place of the stale copy in git.
# The module map sits in Headers/ChiakiKit/ so that it cannot clash with
# module maps from other XCFrameworks in the same app.
stage_headers() {
	local hdr="$1"
	rm -rf "$hdr"; mkdir -p "$hdr"
	cp -R "$CHIAKI_SRC/lib/include/chiaki" "$hdr/chiaki"
	rm -f "$hdr/chiaki/ffmpegdecoder.h" "$hdr/chiaki/pidecoder.h"
	cp "$CHIAKI_BUILD/lib/include/chiaki/config.h" "$hdr/chiaki/config.h"

	local list
	list="$(cd "$hdr" && { echo chiaki/common.h; find chiaki -name '*.h' ! -name common.h | LC_ALL=C sort; })"

	mkdir -p "$hdr/$MODULE_NAME"
	{
		echo "// Generated by build-chiaki-xcframework.sh -- umbrella header for C/ObjC users."
		echo "// chiaki-ng $CHIAKI_TAG ($CHIAKI_COMMIT)"
		echo "#ifndef CHIAKIKIT_H"
		echo "#define CHIAKIKIT_H"
		local h
		for h in $list; do echo "#include <$h>"; done
		echo "#endif"
	} >"$hdr/$MODULE_NAME/$MODULE_NAME.h"
	{
		echo "// Generated by build-chiaki-xcframework.sh"
		echo "module $MODULE_NAME [system] {"
		local h
		for h in $list; do echo "    header \"../$h\""; done
		echo "    export *"
		echo "    link framework \"Security\""
		echo "    link framework \"CoreFoundation\""
		echo "}"
	} >"$hdr/$MODULE_NAME/module.modulemap"
}

# Checks the merged library: it must be arm64 only, every member must target
# the right platform, and none may need a newer tvOS than TVOS_MIN.
verify_slice_lib() {
	local lib="$1"
	local archs; archs="$(xcrun lipo -archs "$lib")"
	[ "$archs" = "arm64" ] || die "$lib has architectures '$archs', expected arm64 only"
	local report
	report="$(xcrun otool -l "$lib" | awk '
		/cmd LC_BUILD_VERSION/ {bv=1; next}
		bv && $1=="platform" {p=$2}
		bv && $1=="minos" {print p, $2; bv=0}
		/cmd LC_VERSION_MIN_/ {print "legacy", $0}' | sort | uniq -c)"
	info "platform/minos of the objects in $(basename "$lib"):"
	printf '%s\n' "$report" | sed 's/^/        /'
	local want_num
	case "$SLICE_EXPECT_PLATFORM" in
		TVOS) want_num=3 ;;
		TVOSSIMULATOR) want_num=8 ;;
	esac
	local bad
	bad="$(printf '%s\n' "$report" | awk -v want="$SLICE_EXPECT_PLATFORM" -v wnum="$want_num" -v min="$TVOS_MIN" '
		function vcmp(a,b,  x,y,i){split(a,x,".");split(b,y,".");for(i=1;i<=3;i++){if((x[i]+0)<(y[i]+0))return -1;if((x[i]+0)>(y[i]+0))return 1}return 0}
		NF>=3 && $2!="legacy" { if (($2!=want && $2!=wnum) || vcmp($3,min)>0) print }')"
	[ -z "$bad" ] || die "objects in $lib target the wrong platform or a newer tvOS than $TVOS_MIN:
$bad"
	ok "$(basename "$lib"): arm64, $SLICE_EXPECT_PLATFORM, minos <= $TVOS_MIN"
}

# Compiles a small C file that imports the module and calls the main entry
# points, then links it against the merged library. This finds missing
# symbols here instead of in Xcode.
smoke_test_slice() {
	local lib="$1" hdr="$2"
	local t="$SLICE_DIR/smoke"
	rm -rf "$t"; mkdir -p "$t"
	write_smoke_source "$t/smoke.c"
	info "smoke test: build the $MODULE_NAME module and link a test program"
	run_logged "$LOG_DIR/$SLICE-package.log" xcrun --sdk "$SLICE" clang -target "$SLICE_CLANG_TARGET" \
		-isysroot "$SLICE_SDK_PATH" -fmodules -fmodules-cache-path="$t/mcache" \
		-I "$hdr" -fmodule-map-file="$hdr/$MODULE_NAME/module.modulemap" \
		-Werror=implicit-function-declaration -c "$t/smoke.c" -o "$t/smoke.o"
	run_logged "$LOG_DIR/$SLICE-package.log" xcrun --sdk "$SLICE" clang -target "$SLICE_CLANG_TARGET" \
		-isysroot "$SLICE_SDK_PATH" "$t/smoke.o" "$lib" \
		-framework Security -framework CoreFoundation -o "$t/smoke"
	ok "smoke test linked: every referenced symbol resolves"
}

write_smoke_source() {
	cat >"$1" <<'EOF'
// Not meant to run. It only proves that the module compiles and that the
// entry points the app needs link. With -fmodules these includes are turned
// into an import of the ChiakiKit module, so the module map is checked too.
#include <chiaki/session.h>
#include <chiaki/discovery.h>
#include <chiaki/regist.h>
#include <chiaki/opusdecoder.h>
#include <chiaki/controller.h>
#include <chiaki/base64.h>
#include <chiaki/remote/holepunch.h>
#include <stddef.h>
#include <sys/socket.h>
static void log_cb(ChiakiLogLevel level, const char *msg, void *user) { (void)level; (void)msg; (void)user; }
static void disc_cb(ChiakiDiscoveryHost *host, void *user) { (void)host; (void)user; }
static void regist_cb(ChiakiRegistEvent *ev, void *user) { (void)ev; (void)user; }
static bool video_cb(uint8_t *buf, size_t sz, int32_t lost, bool rec, void *user) { (void)buf; (void)sz; (void)lost; (void)rec; (void)user; return true; }
static void event_cb(ChiakiEvent *ev, void *user) { (void)ev; (void)user; }
int main(int argc, char **argv) {
	(void)argv;
	if (argc < 100) return 0;
	ChiakiLog log; chiaki_log_init(&log, CHIAKI_LOG_ALL, log_cb, NULL);
	chiaki_lib_init();
	ChiakiDiscovery d; chiaki_discovery_init(&d, &log, AF_INET);
	ChiakiDiscoveryThread dt; chiaki_discovery_thread_start(&dt, &d, disc_cb, NULL);
	chiaki_discovery_thread_stop(&dt); chiaki_discovery_fini(&d);
	ChiakiRegist r; ChiakiRegistInfo ri = {0}; chiaki_regist_start(&r, &log, &ri, regist_cb, NULL);
	chiaki_regist_stop(&r); chiaki_regist_fini(&r);
	ChiakiSession s; ChiakiConnectInfo ci = {0};
	chiaki_connect_video_profile_preset(&ci.video_profile, CHIAKI_VIDEO_RESOLUTION_PRESET_1080p, CHIAKI_VIDEO_FPS_PRESET_60);
	chiaki_session_init(&s, &ci, &log);
	chiaki_session_set_event_cb(&s, event_cb, NULL);
	chiaki_session_set_video_sample_cb(&s, video_cb, NULL);
	ChiakiOpusDecoder od; chiaki_opus_decoder_init(&od, &log);
	ChiakiAudioSink sink; chiaki_opus_decoder_get_sink(&od, &sink); chiaki_session_set_audio_sink(&s, &sink);
	chiaki_session_start(&s);
	ChiakiControllerState cs; chiaki_controller_state_set_idle(&cs); chiaki_session_set_controller_state(&s, &cs);
	chiaki_session_stop(&s); chiaki_session_join(&s); chiaki_session_fini(&s);
	chiaki_opus_decoder_fini(&od);
	uint8_t out[64]; size_t out_sz = sizeof(out); chiaki_base64_decode("AA==", 4, out, &out_sz);
	ChiakiHolepunchSession hs = chiaki_holepunch_session_init("token", &log); chiaki_holepunch_upnp_discover(hs); chiaki_holepunch_session_fini(hs);
	return 0;
}
EOF
}

package_slice() {
	step "[$SLICE] Packaging"
	rm -rf "$SLICE_PKG"; mkdir -p "$SLICE_PKG"
	: >"$LOG_DIR/$SLICE-package.log"
	local -a libs=()
	local line
	while IFS= read -r line; do libs+=("$line"); done < <(slice_static_libs)
	info "merging ${#libs[@]} static libraries into lib$MODULE_NAME.a"
	local l
	for l in "${libs[@]}"; do info "  + ${l#"$BUILD_DIR"/}"; done
	merge_static_libs "$SLICE_PKG/lib$MODULE_NAME.a" "${libs[@]}"
	stage_headers "$SLICE_PKG/Headers"
	verify_slice_lib "$SLICE_PKG/lib$MODULE_NAME.a"
	smoke_test_slice "$SLICE_PKG/lib$MODULE_NAME.a" "$SLICE_PKG/Headers"
	PACKAGED_SLICES="$PACKAGED_SLICES $SLICE"
	ok "slice ready: $SLICE_PKG"
}

create_xcframework() {
	step "Creating $MODULE_NAME.xcframework"
	local xcf="$OUT_DIR/$MODULE_NAME.xcframework"
	mkdir -p "$OUT_DIR"
	rm -rf "$xcf"
	local -a args=()
	local s
	for s in $PACKAGED_SLICES; do
		args+=(-library "$BUILD_DIR/$s/package/lib$MODULE_NAME.a" -headers "$BUILD_DIR/$s/package/Headers")
	done
	run_logged "$LOG_DIR/xcframework.log" xcodebuild -create-xcframework "${args[@]}" -output "$xcf"
	write_manifest "$OUT_DIR/$MODULE_NAME-versions.txt"
	ok "created $xcf"
}

write_manifest() {
	{
		echo "$MODULE_NAME.xcframework -- built $(date -u +%Y-%m-%dT%H:%M:%SZ) by build-chiaki-xcframework.sh"
		echo "slices:          $PACKAGED_SLICES (arm64, minimum tvOS $TVOS_MIN)"
		echo "chiaki-ng:       $CHIAKI_TAG  commit $CHIAKI_COMMIT  patches: $CHIAKI_PATCHES"
		local entry
		for entry in $CHIAKI_SUBMODULES; do
			echo "  submodule:     ${entry%%:*}  commit ${entry#*:}"
		done
		echo "OpenSSL:         $OPENSSL_VERSION  sha256 $OPENSSL_SHA256"
		echo "  options:       $OPENSSL_OPTIONS"
		echo "Opus:            $OPUS_VERSION  sha256 $OPUS_SHA256"
		echo "curl:            $CURL_VERSION  $CURL_TAG commit $CURL_COMMIT (OpenSSL + Apple SecTrust, HTTP/HTTPS/WS/WSS)"
		echo "libevent:        $LIBEVENT_VERSION  commit $LIBEVENT_COMMIT (libevent_core)"
		echo "json-c:          $JSONC_VERSION  commit $JSONC_COMMIT"
		echo "miniupnpc:       $MINIUPNPC_VERSION  commit $MINIUPNPC_COMMIT"
		echo "nanopb python:   $(grep -E '^[A-Za-z0-9_.-]+==' "$PY_REQUIREMENTS" | sed 's/ *\\$//' | tr '\n' ' ')(hash-locked)"
		echo "Xcode:           $(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
		echo "Link in the app: $MODULE_NAME.xcframework (Do Not Embed), Security.framework, CoreFoundation.framework"
	} >"$1"
}

build_slice() {
	slice_setup "$1"
	TOOLCHAIN_KEY="$(slice_toolchain_key)"
	build_openssl
	build_opus
	build_curl
	build_libevent
	build_jsonc
	build_miniupnpc
	build_chiaki
	package_slice
}

print_summary() {
	step "Done"
	local xcf="$OUT_DIR/$MODULE_NAME.xcframework"
	echo
	echo "  XCFramework: $xcf"
	echo "  Slices:     $PACKAGED_SLICES"
	echo "  Versions:   $OUT_DIR/$MODULE_NAME-versions.txt"
	echo
	sed 's/^/    /' "$OUT_DIR/$MODULE_NAME-versions.txt"
	echo
	echo "  Next: add $xcf to the TVRemotePlay target"
	echo "  (Frameworks, Libraries, and Embedded Content -> Do Not Embed), add"
	echo "  Security.framework, then use 'import $MODULE_NAME' in Swift. See README.md."
}

main() {
	parse_args "$@"
	sanitize_env
	[ -n "$JOBS" ] || JOBS="$(ncpu)"

	SDKS_TO_BUILD="appletvsimulator"
	[ "$BUILD_DEVICE" = 1 ] && SDKS_TO_BUILD="$SDKS_TO_BUILD appletvos"

	if [ "$CLEAN" = 1 ]; then
		step "Cleaning"
		info "removing $BUILD_DIR and $OUT_DIR"
		rm -rf "$BUILD_DIR" "$OUT_DIR"
		if [ "$CLEAN_ALL" = 1 ]; then
			info "removing $SRC_DIR"
			rm -rf "$SRC_DIR"
		fi
	fi
	mkdir -p "$SRC_DIR" "$BUILD_DIR" "$OUT_DIR" "$LOG_DIR"

	check_prereqs
	fetch_chiaki
	fetch_deps
	OPUS_SRC_ID="$OPUS_SHA256"
	setup_venv

	PACKAGED_SLICES=""
	local s
	for s in $SDKS_TO_BUILD; do
		build_slice "$s"
	done
	PACKAGED_SLICES="${PACKAGED_SLICES# }"
	create_xcframework
	print_summary
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main ${1+"$@"}
fi
