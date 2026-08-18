# Alpine Snell Server Installer

![License](https://img.shields.io/badge/License-MIT-green)
![Alpine](https://img.shields.io/badge/Alpine-Linux-0D597F?logo=alpinelinux&logoColor=white)
![Shell](https://img.shields.io/badge/Shell-Script-89E051)
![Arch](https://img.shields.io/badge/Arch-x86__64-orange)

A lightweight installer for running the official Surge Snell Server on Alpine Linux x86_64 without Docker.

Designed for tiny Alpine VPS instances (including 128 MB memory class) by creating an isolated Debian Bookworm glibc runtime while keeping Alpine's native musl environment untouched.

## ✨ Features

- Run the official Snell Server on Alpine Linux without Docker.
- Automatically install an isolated Debian Bookworm glibc runtime.
- Preserve Alpine's native musl environment.
- Automatically remove `gcompat` to avoid loader conflicts.
- Install and enable an OpenRC service.
- Preserve existing Snell configuration during upgrades.
- Designed for very small VPS instances (tested on 128 MB memory).

## Why this exists

Alpine uses **musl libc**, while the official Snell Linux binary requires **glibc**. A common `gcompat` approach did not work reliably with the Snell self-loading executable.

This installer keeps Alpine/musl untouched and creates a separate Debian Bookworm runtime under:

```text
/opt/glibc
```

It extracts:

- `libc6`
- `libstdc++6`
- `libgcc-s1`

from Debian Bookworm, then points `/lib64/ld-linux-x86-64.so.2` to the isolated glibc loader.

## Tested setup

- Alpine Linux 3.21 x86_64
- Very small LXC/NAT VPS
- 128 MB memory class
- Snell Server v6.0.0 RC2

Snell v6 is beta/RC software. Check the official release notes before deploying.

## 🚀 Quick Start

```bash
wget https://raw.githubusercontent.com/kid-oh/Snell-Server-Alpine-Installer/main/install-snell-alpine.sh

chmod +x install-snell-alpine.sh

./install-snell-alpine.sh
```

## Install

```sh
chmod +x install-snell-alpine.sh
./install-snell-alpine.sh
```

On first install, Snell asks:

```text
Create new? [Y/n]
```

Enter `Y`. It generates a random PSK and listening port.

## After installation

```sh
rc-service snell status
rc-service snell restart
cat /etc/snell/snell-server.conf
```

The OpenRC service is enabled at boot.

For a NAT VPS, map the public TCP port to the Snell listening port in `snell-server.conf`.

For Snell v6, configure Surge with `version=6`.

## Update Snell

The script defaults to the tested RC2 URL. To test another official amd64 build without editing the script:

```sh
SNELL_URL="OFFICIAL_SNELL_AMD64_ZIP_URL" ./install-snell-alpine.sh
```

Existing Snell configuration is preserved, and the current binary is backed up before replacement.

## Important notes

- x86_64/amd64 only.
- Do not mix Alpine's musl `libstdc++` with the isolated glibc runtime.
- Do not use `gcompat` together with this setup.
- The script intentionally does not replace Alpine's system libc.
- Review the script before running it on production systems.

## Official documentation

Surge Snell release notes:

https://kb.nssurge.com/surge-knowledge-base/release-notes/snell
