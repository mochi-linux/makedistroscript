# MochiOS RootFS Minimal Build

A fully automated script that cross-compiles a minimal Linux root filesystem and toolchain from source.

## What It Builds

| Component     | Version |
|---------------|---------|
| Linux Headers | 7.0     |
| glibc         | 2.43    |
| GCC           | 15.2.0  |
| Binutils      | 2.46.0  |
| Bash          | 5.3     |
| Coreutils     | 9.10    |
| Readline      | 8.3     |
| Ncurses       | 6.6     |
| Inetutils     | 2.7     |
| sed           | 4.9     |
| gawk          | 5.4.0   |
| m4            | 1.4.21  |
| findutils     | 4.10.0  |
| grep          | 3.12    |

## Quick Start

```bash
curl -fsSL "https://raw.githubusercontent.com/mochi-linux/makedistroscript/refs/heads/main/buildrootfs.sh" | bash
```

Or clone and run locally:

```bash
git clone https://github.com/mochi-linux/makedistroscript
cd makedistroscript
bash buildrootfs.sh
```

## Project Folder

On first run, the script prompts you to choose a project directory:

```
══════════════════════════════════════════
  Set Project Folder To?
══════════════════════════════════════════
  1) ~/MochiOS  (default)
  2) $PWD
  3) Custom path
```

| Option | Path |
|--------|------|
| `1`    | `$HOME/MochiOS` — recommended default |
| `2`    | Current working directory |
| `3`    | Any custom absolute path |

## Directory Layout

```
<PROJECT_DIR>/
├── download/      # Downloaded source tarballs
├── sources/       # Extracted source trees
├── build/         # Out-of-tree build directories
├── rootfs/        # Target sysroot (the output rootfs)
├── tools/         # Cross-compilation toolchain (host-only)
└── .stamps/       # Step completion markers (resume support)
```

## Build Steps

| Step | Description |
|------|-------------|
| 1    | Initialize project workspace |
| 2    | Install host build dependencies (pacman / apt / dnf) |
| 3    | Download sources via aria2c (parallel) |
| 4    | Extract sources |
| 5    | Prepare build environment |
| 5b   | Fetch & extract rootfs template |
| 6    | Install Linux kernel headers |
| 7    | Build Binutils Stage 1 (cross) |
| 8    | Build GCC Stage 1 (C only, no libc) |
| 9    | Install glibc headers & startup files |
| 10   | Build full glibc |
| 11   | Build GCC Stage 2 (full C/C++) |
| 12–22 | Build target userland utilities |

> Steps are **resumable** — each step is stamped on completion and skipped on re-runs.

## Host Requirements

- **OS:** Linux (x86_64)
- **Package manager:** `pacman`, `apt`, or `dnf` (auto-detected)
- **Required tools:** `aria2c`, `wget`, `gcc`, `make`, `cmake`, `bison`, `flex`, `gawk`, `texinfo`, `python3`

The script installs missing host dependencies automatically in Step 2.

## Target

```
x86_64-mochios-linux-gnu
```

## License

See [LICENSE](LICENSE) if present, or refer to the upstream MochiOS project.
