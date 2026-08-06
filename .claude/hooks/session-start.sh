#!/bin/bash
# Installs the Zig compiler this project needs, so that `zig build test` works
# in Claude Code on the web. Only runs in the remote environment; on a local
# machine the developer's own zig is used.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Must match minimum_zig_version in build.zig.zon. This is a nightly build: the
# framework uses the 0.17 reflection API (std.lang.Type with parallel arrays,
# @Struct/@Tuple), which does not exist in released 0.16.0.
ZIG_VERSION="0.17.0-dev.1282+c0f9b51d8"
ZIG_DIR="$HOME/.local/zig/$ZIG_VERSION"

if [ -x "$ZIG_DIR/zig" ]; then
  echo "zig $ZIG_VERSION already installed"
else
  case "$(uname -m)" in
    x86_64) arch="x86_64" ;;
    aarch64 | arm64) arch="aarch64" ;;
    *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
  esac

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # The tarball naming changed during the 0.14/0.15 cycle (zig-linux-x86_64-*
  # became zig-x86_64-linux-*), so try the current form first and fall back.
  downloaded=""
  for name in "zig-${arch}-linux-${ZIG_VERSION}" "zig-linux-${arch}-${ZIG_VERSION}"; do
    if curl -fsSL --retry 3 --connect-timeout 30 \
        "https://ziglang.org/builds/${name}.tar.xz" -o "$tmp/zig.tar.xz"; then
      downloaded="$name"
      break
    fi
  done

  if [ -z "$downloaded" ]; then
    echo "could not download zig $ZIG_VERSION from ziglang.org." >&2
    echo "Two things make this fail:" >&2
    echo "  1. ziglang.org must be allowed by the environment's network policy." >&2
    echo "  2. Nightly builds are garbage-collected; if this one is gone from" >&2
    echo "     ziglang.org/builds, pick a current nightly and update both this" >&2
    echo "     script and minimum_zig_version in build.zig.zon." >&2
    exit 1
  fi

  mkdir -p "$ZIG_DIR"
  tar -xJf "$tmp/zig.tar.xz" -C "$ZIG_DIR" --strip-components=1
  echo "installed zig $ZIG_VERSION"
fi

"$ZIG_DIR/zig" version
echo "export PATH=\"$ZIG_DIR:\$PATH\"" >> "${CLAUDE_ENV_FILE:-/dev/null}"
