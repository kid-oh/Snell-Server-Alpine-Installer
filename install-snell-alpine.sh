#!/bin/sh
# Alpine Snell Server Installer
# Tested workflow: Alpine Linux 3.21 x86_64 + Snell Server v6.0.0 RC2
# Designed for very small Alpine VPS/NAT VPS where Docker is impractical.
#
# What it does:
#   1. Installs minimal tools
#   2. Downloads official Snell linux-amd64 binary
#   3. Extracts Debian Bookworm glibc/libstdc++/libgcc runtime into /opt/glibc
#   4. Creates /lib64/ld-linux-x86-64.so.2 symlink
#   5. Generates a Snell config on first run
#   6. Installs an OpenRC service and enables autostart
#
# IMPORTANT:
# - x86_64/amd64 only.
# - This does NOT replace Alpine's musl libc.
# - Do NOT install/use gcompat for Snell together with this setup.
# - Snell v6 is beta/RC software. Change SNELL_URL below when a newer official build is released.

set -eu

SNELL_URL="${SNELL_URL:-https://dl.nssurge.com/snell/snell-server-v6.0.0rc2-linux-amd64.zip}"
SNELL_BIN="/usr/local/bin/snell-server"
SNELL_DIR="/etc/snell"
SNELL_CONF="${SNELL_DIR}/snell-server.conf"
GLIBC_DIR="/opt/glibc"
WORKDIR="/tmp/snell-alpine-install"

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Please run as root."
[ "$(uname -m)" = "x86_64" ] || die "This script currently supports x86_64 only."
[ -f /etc/alpine-release ] || die "This installer is intended for Alpine Linux."

say "Alpine $(cat /etc/alpine-release), architecture $(uname -m)"

# gcompat caused the official Snell self-loader to fail in the tested setup.
if apk info -e gcompat >/dev/null 2>&1; then
    say "Removing gcompat to avoid loader conflicts"
    apk del gcompat
fi

say "Installing minimal dependencies"
apk add --no-cache curl unzip binutils xz ca-certificates

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR" "$GLIBC_DIR" "$SNELL_DIR"
cd "$WORKDIR"

get_debian_filename() {
    pkg="$1"
    curl -fsSL https://deb.debian.org/debian/dists/bookworm/main/binary-amd64/Packages.gz |
        gzip -dc |
        awk -v pkg="$pkg" '
            $0 == "Package: " pkg { found=1; next }
            found && /^Filename: / { print $2; exit }
        '
}

extract_deb_data() {
    deb="$1"
    dest="$2"
    mkdir -p "$dest"
    (
        cd "$dest"
        ar x "$deb"
        data_archive="$(ls data.tar.* 2>/dev/null | head -n 1)"
        [ -n "$data_archive" ] || exit 1
        tar -xf "$data_archive"
    )
}

say "Resolving current Debian Bookworm runtime packages"
LIBC_PATH="$(get_debian_filename libc6)"
LIBSTDCPP_PATH="$(get_debian_filename 'libstdc++6')"
LIBGCC_PATH="$(get_debian_filename libgcc-s1)"

[ -n "$LIBC_PATH" ] || die "Could not resolve Debian libc6 package."
[ -n "$LIBSTDCPP_PATH" ] || die "Could not resolve Debian libstdc++6 package."
[ -n "$LIBGCC_PATH" ] || die "Could not resolve Debian libgcc-s1 package."

printf 'libc6:      %s\nlibstdc++6: %s\nlibgcc-s1:   %s\n' \
    "$LIBC_PATH" "$LIBSTDCPP_PATH" "$LIBGCC_PATH"

say "Downloading Debian Bookworm runtime packages"
curl -fL "https://deb.debian.org/debian/$LIBC_PATH" -o libc6.deb
curl -fL "https://deb.debian.org/debian/$LIBSTDCPP_PATH" -o libstdcpp.deb
curl -fL "https://deb.debian.org/debian/$LIBGCC_PATH" -o libgcc.deb

say "Extracting isolated glibc runtime into $GLIBC_DIR"
extract_deb_data "$WORKDIR/libc6.deb" "$WORKDIR/libc6"
extract_deb_data "$WORKDIR/libstdcpp.deb" "$WORKDIR/libstdcpp"
extract_deb_data "$WORKDIR/libgcc.deb" "$WORKDIR/libgcc"

cp -a "$WORKDIR"/libc6/lib/x86_64-linux-gnu/* "$GLIBC_DIR"/
cp -a "$WORKDIR"/libstdcpp/usr/lib/x86_64-linux-gnu/libstdc++.so* "$GLIBC_DIR"/
cp -a "$WORKDIR"/libgcc/lib/x86_64-linux-gnu/libgcc_s.so.1 "$GLIBC_DIR"/

[ -x "$GLIBC_DIR/ld-linux-x86-64.so.2" ] || die "glibc loader was not extracted."
[ -f "$GLIBC_DIR/libc.so.6" ] || die "libc.so.6 was not extracted."
[ -e "$GLIBC_DIR/libstdc++.so.6" ] || die "libstdc++.so.6 was not extracted."
[ -f "$GLIBC_DIR/libgcc_s.so.1" ] || die "libgcc_s.so.1 was not extracted."

say "Creating loader path expected by Snell"
mkdir -p /lib64
ln -sf "$GLIBC_DIR/ld-linux-x86-64.so.2" /lib64/ld-linux-x86-64.so.2

say "Downloading official Snell Server"
curl -fL "$SNELL_URL" -o snell.zip
unzip -o snell.zip
[ -f snell-server ] || die "snell-server was not found in the downloaded archive."
chmod +x snell-server

if [ -f "$SNELL_BIN" ]; then
    backup="${SNELL_BIN}.backup.$(date +%Y%m%d%H%M%S)"
    say "Backing up existing Snell binary to $backup"
    cp -a "$SNELL_BIN" "$backup"
fi

cp snell-server "$SNELL_BIN"
chmod +x "$SNELL_BIN"

if [ ! -f "$SNELL_CONF" ]; then
    say "No Snell config exists yet."
    say "Snell will now generate a random PSK and port."
    say "At the prompt 'Create new? [Y/n]', enter Y."
    (
        cd "$SNELL_DIR"
        LD_LIBRARY_PATH="$GLIBC_DIR" "$SNELL_BIN"
    )
    [ -f "$SNELL_CONF" ] || die "Snell config was not created."
else
    say "Keeping existing config: $SNELL_CONF"
fi

say "Installing OpenRC service"
cat > /etc/init.d/snell <<EOF
#!/sbin/openrc-run

name="Snell Server"
description="Snell Proxy Server"

command="$SNELL_BIN"
command_args="-c $SNELL_CONF"
command_background="yes"
pidfile="/run/snell.pid"

export LD_LIBRARY_PATH="$GLIBC_DIR"

depend() {
    need net
}
EOF

chmod +x /etc/init.d/snell
rc-update add snell default >/dev/null 2>&1 || true

if rc-service snell status >/dev/null 2>&1; then
    rc-service snell restart
else
    rc-service snell start
fi

say "Snell service status"
rc-service snell status || true

say "Cleaning temporary installation files"
cd /
rm -rf "$WORKDIR"

cat <<'EOF'

Installation finished.

Useful commands:
  rc-service snell status
  rc-service snell restart
  rc-service snell stop
  cat /etc/snell/snell-server.conf

Surge v6 client configuration must use version=6.

If your VPS is behind NAT, map the public TCP port to the listen port
shown in /etc/snell/snell-server.conf.

Official Snell release notes:
  https://kb.nssurge.com/surge-knowledge-base/release-notes/snell

EOF
