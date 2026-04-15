#!/usr/bin/env bash
# =============================================================================
#  MochiOS Cross-Compilation Toolchain Builder
#  Builds: Linux 7.0, glibc 2.43, GCC 15.2, Binutils 2.46, Bash 5.3,
#          Coreutils 9.10, Readline 8.3, Ncurses 6.6, Inetutils 2.7,
#          sed 4.9, gawk 5.4.0, m4 1.4.21, diffutils 3.12, findutils 4.10.0, grep 3.12
# =============================================================================
set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${GREEN}[+]${RESET} $*"; }
info() { echo -e "${CYAN}[i]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
die()  { echo -e "${RED}[✗]${RESET} $*" >&2; exit 1; }
step() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; \
         echo -e "${BOLD}${CYAN}  $*${RESET}"; \
         echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; }

# ─── Directory Layout ─────────────────────────────────────────────────────────
export PROJECT_DIR="${HOME}/MochiOS"
DOWNLOAD_DIR="${PROJECT_DIR}/download"
SOURCES_DIR="${PROJECT_DIR}/sources"
BUILD_DIR="${PROJECT_DIR}/build"
export SYSROOT="${PROJECT_DIR}/rootfs"
export TARGET="$(uname -m)-mochios-linux-gnu"
TOOLCHAIN_DIR="${PROJECT_DIR}/tools"   # cross tools live here (not installed to host or rootfs)
STAMPS_DIR="${PROJECT_DIR}/.stamps"

# ─── Versions ─────────────────────────────────────────────────────────────────
VER_LINUX="7.0"
VER_GLIBC="2.43"
VER_GCC="15.2.0"
VER_BINUTILS="2.46.0"
VER_BASH="5.3"
VER_COREUTILS="9.10"
VER_READLINE="8.3"
VER_NCURSES="6.6"
VER_INETUTILS="2.7"
VER_SED="4.9"
VER_GAWK="5.4.0"
VER_M4="1.4.21"
VER_DIFFUTILS="3.12"
VER_FINDUTILS="4.10.0"
VER_GREP="3.12"

# ─── Parallel jobs ────────────────────────────────────────────────────────────
JOBS="$(nproc)"

# ─── Rootfs Template ─────────────────────────────────────────────────────────
ROOTFS_TEMPLATE_URL="https://cdn.mochilinux.org/mcrootfs.tar.xz"

# ─── Source URLs ──────────────────────────────────────────────────────────────
declare -A URLS=(
  ["linux-${VER_LINUX}.tar.xz"]="https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-${VER_LINUX}.tar.xz"
  ["glibc-${VER_GLIBC}.tar.xz"]="https://ftp.gnu.org/gnu/glibc/glibc-${VER_GLIBC}.tar.xz"
  ["gcc-${VER_GCC}.tar.xz"]="https://ftp.gnu.org/gnu/gcc/gcc-${VER_GCC}/gcc-${VER_GCC}.tar.xz"
  ["binutils-${VER_BINUTILS}.tar.xz"]="https://ftp.gnu.org/gnu/binutils/binutils-${VER_BINUTILS}.tar.xz"
  ["bash-${VER_BASH}.tar.gz"]="https://ftp.gnu.org/gnu/bash/bash-${VER_BASH}.tar.gz"
  ["coreutils-${VER_COREUTILS}.tar.xz"]="https://ftp.gnu.org/gnu/coreutils/coreutils-${VER_COREUTILS}.tar.xz"
  ["readline-${VER_READLINE}.tar.gz"]="https://ftp.gnu.org/gnu/readline/readline-${VER_READLINE}.tar.gz"
  ["ncurses-${VER_NCURSES}.tar.gz"]="https://ftp.gnu.org/gnu/ncurses/ncurses-${VER_NCURSES}.tar.gz"
  ["inetutils-${VER_INETUTILS}.tar.gz"]="https://ftp.gnu.org/gnu/inetutils/inetutils-${VER_INETUTILS}.tar.gz"
  ["sed-${VER_SED}.tar.xz"]="https://ftp.gnu.org/gnu/sed/sed-${VER_SED}.tar.xz"
  ["gawk-${VER_GAWK}.tar.xz"]="https://ftp.gnu.org/gnu/gawk/gawk-${VER_GAWK}.tar.xz"
  ["m4-${VER_M4}.tar.xz"]="https://ftp.gnu.org/gnu/m4/m4-${VER_M4}.tar.xz"
  ["diffutils-${VER_DIFFUTILS}.tar.xz"]="https://ftp.gnu.org/gnu/diffutils/diffutils-${VER_DIFFUTILS}.tar.xz"
  ["findutils-${VER_FINDUTILS}.tar.xz"]="https://ftp.gnu.org/gnu/findutils/findutils-${VER_FINDUTILS}.tar.xz"
  ["grep-${VER_GREP}.tar.xz"]="https://ftp.gnu.org/gnu/grep/grep-${VER_GREP}.tar.xz"
)

# ─── Helper: check command ────────────────────────────────────────────────────
need_cmd()  { command -v "$1" &>/dev/null || die "Required command not found: $1 — run step 2 (install deps) first."; }
is_done()   { [[ -f "${STAMPS_DIR}/$1.done" ]]; }
mark_done() { mkdir -p "${STAMPS_DIR}"; touch "${STAMPS_DIR}/$1.done"; }

# =============================================================================
#  STEP 0 — Print banner & environment
# =============================================================================
banner() {
  echo -e "${BOLD}"
  cat << 'EOF'
  __  __            _     _        ___  ____
 |  \/  | ___   ___| |__ (_)___   / _ \/ ___|
 | |\/| |/ _ \ / __| '_ \| / __| | | | \___ \
 | |  | | (_) | (__| | | | \__ \ | |_| |___) |
 |_|  |_|\___/ \___|_| |_|_|___/  \___/|____/
  Toolchain Builder
EOF
  echo -e "${RESET}"
  info "TARGET   : ${TARGET}"
  info "PROJECT  : ${PROJECT_DIR}"
  info "SYSROOT  : ${SYSROOT}"
  info "TOOLS    : ${TOOLCHAIN_DIR}"
  info "JOBS     : ${JOBS}"
  echo ""
}

# =============================================================================
#  STEP 1 — Initialize Project Workspace
# =============================================================================
step_init_workspace() {
  step "STEP 1 — Initializing Project Workspace"
  
  if [[ ! -d "${PROJECT_DIR}" ]]; then
    log "Creating root project directory at: ${PROJECT_DIR}"
    mkdir -p "${PROJECT_DIR}"
  else
    info "Project directory already exists at: ${PROJECT_DIR}"
  fi
  
  # Ensure we are operating from within the project directory just in case
  cd "${PROJECT_DIR}"
}

# =============================================================================
#  STEP 2 — Install Host Build Dependencies (pacman / apt / dnf)
# =============================================================================
step_install_deps() {
  step "STEP 2 — Installing host build dependencies"
  is_done "install-deps" && { info "Already done — skipping."; return 0; }

  if command -v pacman &>/dev/null; then
    local PKGS=(
      base-devel gcc make cmake aria2 wget texinfo python python-pip
      bison flex gawk bc libmpc mpfr gmp xz zstd lzip rsync git
      patch help2man autoconf automake libtool
    )
    log "Detected pacman — updating database..."
    sudo pacman -Sy --noconfirm
    log "Installing packages: ${PKGS[*]}"
    sudo pacman -S --noconfirm "${PKGS[@]}"
    log "pacman install complete ✓"

  elif command -v apt &>/dev/null; then
    local PKGS=(
      build-essential gcc g++ make cmake aria2 wget texinfo
      python3 python3-pip bison flex gawk bc
      libmpc-dev libmpfr-dev libgmp-dev
      xz-utils zstd lzip rsync git
      patch help2man autoconf automake libtool
    )
    log "Detected apt — updating package lists..."
    sudo apt update -y
    log "Installing packages: ${PKGS[*]}"
    sudo apt install -y "${PKGS[@]}"
    log "apt install complete ✓"

  elif command -v dnf &>/dev/null; then
    local PKGS=(
      gcc gcc-c++ make cmake aria2 wget texinfo
      python3 python3-pip bison flex gawk bc
      libmpc-devel mpfr-devel gmp-devel
      xz zstd lzip rsync git
      patch help2man autoconf automake libtool
    )
    log "Detected dnf — installing packages: ${PKGS[*]}"
    sudo dnf install -y "${PKGS[@]}"
    log "dnf install complete ✓"

  else
    warn "No supported package manager found (pacman / apt / dnf)."
    warn "Please install the following manually:"
    warn "  gcc make cmake aria2 wget texinfo python3 bison flex gawk bc"
    warn "  libmpc libmpfr libgmp xz zstd lzip rsync git patch autoconf automake libtool"
  fi
  mark_done "install-deps"
}

# =============================================================================
#  STEP 3 — Download Sources with aria2c (parallel)
# =============================================================================
step_download() {
  step "STEP 3 — Downloading sources to ${DOWNLOAD_DIR}"
  is_done "download" && { info "Already done — skipping."; return 0; }

  need_cmd aria2c

  mkdir -p "${DOWNLOAD_DIR}"

  local INPUT_FILE="${DOWNLOAD_DIR}/aria2_input.txt"
  : > "${INPUT_FILE}"

  for TARBALL in "${!URLS[@]}"; do
    local URL="${URLS[$TARBALL]}"
    local DEST="${DOWNLOAD_DIR}/${TARBALL}"

    if [[ -f "${DEST}" ]]; then
      log "Already exists, skipping: ${TARBALL}"
      continue
    fi

    cat >> "${INPUT_FILE}" << EOF
${URL}
  out=${TARBALL}
  dir=${DOWNLOAD_DIR}
EOF
  done

  if [[ ! -s "${INPUT_FILE}" ]]; then
    log "All tarballs already downloaded ✓"
    mark_done "download"
    return 0
  fi

  log "Starting aria2c parallel download..."
  aria2c \
    --input-file="${INPUT_FILE}" \
    --max-concurrent-downloads=4 \
    --split=4 \
    --min-split-size=5M \
    --max-connection-per-server=4 \
    --continue=true \
    --retry-wait=5 \
    --max-tries=5 \
    --summary-interval=30 \
    --console-log-level=notice \
    --file-allocation=none

  log "All downloads complete ✓"
  mark_done "download"
}

# =============================================================================
#  STEP 4 — Extract Sources
# =============================================================================
step_extract() {
  step "STEP 4 — Extracting sources to ${SOURCES_DIR}"
  is_done "extract" && { info "Already done — skipping."; return 0; }

  mkdir -p "${SOURCES_DIR}"

  for TARBALL in "${!URLS[@]}"; do
    local ARCHIVE="${DOWNLOAD_DIR}/${TARBALL}"

    if [[ ! -f "${ARCHIVE}" ]]; then
      die "Archive not found: ${ARCHIVE} — run download step first."
    fi

    local DIRNAME="${TARBALL%.tar.*}"
    local DEST="${SOURCES_DIR}/${DIRNAME}"

    if [[ -d "${DEST}" ]]; then
      log "Already extracted: ${DIRNAME}"
      continue
    fi

    log "Extracting ${TARBALL}..."
    case "${TARBALL}" in
      *.tar.xz)  tar -xJf "${ARCHIVE}" -C "${SOURCES_DIR}" ;;
      *.tar.gz)  tar -xzf "${ARCHIVE}" -C "${SOURCES_DIR}" ;;
      *.tar.bz2) tar -xjf "${ARCHIVE}" -C "${SOURCES_DIR}" ;;
      *.tar.lz)  tar --lzip -xf "${ARCHIVE}" -C "${SOURCES_DIR}" ;;
      *.tar.zst) tar --zstd -xf "${ARCHIVE}" -C "${SOURCES_DIR}" ;;
      *) die "Unknown archive format: ${TARBALL}" ;;
    esac
  done

  log "All sources extracted ✓"
  mark_done "extract"
}

# =============================================================================
#  STEP 5 — Prepare directories & environment
# =============================================================================
step_prepare_env() {
  step "STEP 5 — Preparing build environment"
  export PATH="${TOOLCHAIN_DIR}/bin:${PATH}"
  is_done "prepare-env" && { info "Already done — skipping."; return 0; }

  mkdir -p "${BUILD_DIR}"/{binutils-stage1,gcc-stage1,glibc-headers,glibc,gcc-stage2}

  # Create cross-toolchain directories (host environment)
  mkdir -p "${TOOLCHAIN_DIR}/bin"

  log "Environment prepared ✓"
  info "PATH prefix: ${TOOLCHAIN_DIR}/bin"
  mark_done "prepare-env"
}

# =============================================================================
#  STEP 5b — Fetch & Extract Rootfs Template
# =============================================================================
step_rootfs_template() {
  step "STEP 5b — Fetching rootfs template"
  is_done "rootfs-template" && { info "Already done — skipping."; return 0; }

  local TARBALL="${DOWNLOAD_DIR}/mcrootfs.tar.xz"

  mkdir -p "${DOWNLOAD_DIR}"

  if [[ ! -f "${TARBALL}" ]]; then
    log "Downloading rootfs template..."
    wget -c --show-progress -O "${TARBALL}" "${ROOTFS_TEMPLATE_URL}"
  else
    log "Rootfs template already downloaded, skipping."
  fi

  log "Extracting rootfs template to ${SYSROOT}..."
  rm -rf "${SYSROOT}"
  mkdir -p "${SYSROOT}"
  tar -xJf "${TARBALL}" -C "${SYSROOT}"

  log "Rootfs template extracted ✓"
  mark_done "rootfs-template"
}

# =============================================================================
#  STEP 6 — Install Linux Kernel Headers
# =============================================================================
step_linux_headers() {
  step "STEP 6 — Installing Linux ${VER_LINUX} kernel headers"
  is_done "linux-headers" && { info "Already done — skipping."; return 0; }

  local SRC="${SOURCES_DIR}/linux-${VER_LINUX}"
  [[ -d "${SRC}" ]] || die "Linux source not found: ${SRC}"

  cd "${SRC}"

  log "Installing kernel headers to ${SYSROOT}/usr..."
  make mrproper
  make headers_install \
    ARCH="$(uname -m | sed 's/x86_64/x86/')" \
    INSTALL_HDR_PATH="${SYSROOT}/usr"

  find "${SYSROOT}/usr/include" \( -name '.*' -o -name 'Makefile' \) -delete 2>/dev/null || true

  log "Kernel headers installed ✓"
  mark_done "linux-headers"
}

# =============================================================================
#  STEP 7 — Build Binutils (Stage 1 — Cross)
# =============================================================================
step_binutils_stage1() {
  step "STEP 7 — Building Binutils ${VER_BINUTILS} (Stage 1 cross)"
  is_done "binutils-stage1" && { info "Already done — skipping."; return 0; }

  local SRC="${SOURCES_DIR}/binutils-${VER_BINUTILS}"
  local BLD="${BUILD_DIR}/binutils-stage1"
  [[ -d "${SRC}" ]] || die "Binutils source not found: ${SRC}"

  cd "${BLD}"

  log "Configuring Binutils..."
  "${SRC}/configure" \
    --prefix="${TOOLCHAIN_DIR}" \
    --target="${TARGET}" \
    --with-sysroot="${SYSROOT}" \
    --with-lib-path="${TOOLCHAIN_DIR}/lib" \
    --disable-nls \
    --disable-werror \
    --enable-64-bit-bfd \
    --enable-gprofng=no \
    2>&1 | tee "${BLD}/configure.log"

  log "Building Binutils (${JOBS} jobs)..."
  make -j"${JOBS}" 2>&1 | tee "${BLD}/build.log"

  log "Installing Binutils..."
  make install 2>&1 | tee "${BLD}/install.log"

  log "Binutils Stage 1 complete ✓"
  mark_done "binutils-stage1"
}

# =============================================================================
#  STEP 8 — Build GCC (Stage 1 — C only, no libc)
# =============================================================================
step_gcc_stage1() {
  step "STEP 8 — Building GCC ${VER_GCC} (Stage 1 — C only)"
  is_done "gcc-stage1" && { info "Already done — skipping."; return 0; }

  local SRC="${SOURCES_DIR}/gcc-${VER_GCC}"
  local BLD="${BUILD_DIR}/gcc-stage1"
  [[ -d "${SRC}" ]] || die "GCC source not found: ${SRC}"

  if [[ ! -d "${SRC}/gmp" ]]; then
    log "Downloading GCC prerequisites (gmp, mpfr, mpc)..."
    cd "${SRC}"
    ./contrib/download_prerequisites
  fi

  cd "${BLD}"

  log "Configuring GCC Stage 1..."
  "${SRC}/configure" \
    --prefix="${TOOLCHAIN_DIR}" \
    --build="$(uname -m)-linux-gnu" \
    --host="$(uname -m)-linux-gnu" \
    --target="${TARGET}" \
    --with-sysroot="${SYSROOT}" \
    --with-newlib \
    --without-headers \
    --enable-languages=c,c++ \
    --disable-shared \
    --disable-threads \
    --disable-libatomic \
    --disable-libgomp \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libvtv \
    --disable-libstdcxx \
    --disable-nls \
    --disable-multilib \
    --disable-bootstrap \
    2>&1 | tee "${BLD}/configure.log"

  log "Building GCC Stage 1 (${JOBS} jobs)..."
  make -j"${JOBS}" all-gcc all-target-libgcc \
    2>&1 | tee "${BLD}/build.log"

  log "Installing GCC Stage 1..."
  make install-gcc install-target-libgcc \
    2>&1 | tee "${BLD}/install.log"

  log "GCC Stage 1 complete ✓"
  mark_done "gcc-stage1"
}

# =============================================================================
#  STEP 9 — Install glibc Headers & Startup Files
# =============================================================================
step_glibc_headers() {
  step "STEP 9 — Installing glibc ${VER_GLIBC} headers & startup files"
  is_done "glibc-headers" && { info "Already done — skipping."; return 0; }

  local SRC="${SOURCES_DIR}/glibc-${VER_GLIBC}"
  local BLD="${BUILD_DIR}/glibc-headers"
  [[ -d "${SRC}" ]] || die "glibc source not found: ${SRC}"

  cd "${BLD}"

  log "Configuring glibc (headers only)..."
  "${SRC}/configure" \
    --prefix=/usr \
    --host="${TARGET}" \
    --build="$(uname -m)-linux-gnu" \
    --with-headers="${SYSROOT}/usr/include" \
    --enable-kernel=5.4 \
    --disable-nls \
    --disable-sanity-checks \
    libc_cv_slibdir=/lib \
    libc_cv_forced_unwind=yes \
    2>&1 | tee "${BLD}/configure.log"

  log "Installing glibc headers..."
  make install-bootstrap-headers=yes install-headers \
    DESTDIR="${SYSROOT}" \
    2>&1 | tee "${BLD}/install-headers.log"

  log "Building glibc startup files..."
  make -j"${JOBS}" csu/subdir_lib \
    2>&1 | tee "${BLD}/csu.log"

  install -v csu/crt1.o csu/crti.o csu/crtn.o "${SYSROOT}/usr/lib/"

  "${TARGET}-gcc" \
    -nostdlib \
    -nostartfiles \
    -shared \
    -x c /dev/null \
    -o "${SYSROOT}/usr/lib/libc.so" \
    || warn "dummy libc.so creation failed — continuing anyway"

  touch "${SYSROOT}/usr/include/gnu/stubs.h"

  log "glibc headers & startup files installed ✓"
  mark_done "glibc-headers"
}

# =============================================================================
#  STEP 10 — Build Full glibc
# =============================================================================
step_glibc_full() {
  step "STEP 10 — Building full glibc ${VER_GLIBC}"
  is_done "glibc-full" && { info "Already done — skipping."; return 0; }

  local SRC="${SOURCES_DIR}/glibc-${VER_GLIBC}"
  local BLD="${BUILD_DIR}/glibc"
  [[ -d "${SRC}" ]] || die "glibc source not found: ${SRC}"

  cd "${BLD}"

  log "Configuring glibc (full build)..."
  CC="${TARGET}-gcc" \
  CXX="${TARGET}-g++" \
  AR="${TARGET}-ar" \
  RANLIB="${TARGET}-ranlib" \
  "${SRC}/configure" \
    --prefix=/usr \
    --host="${TARGET}" \
    --build="$(uname -m)-linux-gnu" \
    --with-headers="${SYSROOT}/usr/include" \
    --enable-kernel=5.4 \
    --enable-shared \
    --enable-stack-protector=strong \
    --disable-nls \
    --disable-werror \
    libc_cv_slibdir=/lib \
    libc_cv_forced_unwind=yes \
    2>&1 | tee "${BLD}/configure.log"

  log "Building glibc (${JOBS} jobs)..."
  make -j"${JOBS}" \
    2>&1 | tee "${BLD}/build.log"

  log "Installing glibc to sysroot..."
  make install DESTDIR="${SYSROOT}" \
    2>&1 | tee "${BLD}/install.log"

  log "glibc full build complete ✓"
  mark_done "glibc-full"
}

# =============================================================================
#  STEP 11 — Build GCC (Stage 2 — Full C/C++)
# =============================================================================
step_gcc_stage2() {
  step "STEP 11 — Building GCC ${VER_GCC} (Stage 2 — full C/C++)"
  is_done "gcc-stage2" && { info "Already done — skipping."; return 0; }

  local SRC="${SOURCES_DIR}/gcc-${VER_GCC}"
  local BLD="${BUILD_DIR}/gcc-stage2"
  [[ -d "${SRC}" ]] || die "GCC source not found: ${SRC}"

  cd "${BLD}"

  log "Configuring GCC Stage 2..."
  "${SRC}/configure" \
    --prefix="${TOOLCHAIN_DIR}" \
    --build="$(uname -m)-linux-gnu" \
    --host="$(uname -m)-linux-gnu" \
    --target="${TARGET}" \
    --with-sysroot="${SYSROOT}" \
    --enable-languages=c,c++ \
    --enable-shared \
    --enable-threads=posix \
    --enable-__cxa_atexit \
    --enable-clocale=gnu \
    --disable-libstdcxx-backtrace \
    --disable-libstdcxx-pch \
    --with-native-system-header-dir=/usr/include \
    --enable-lto \
    --enable-default-pie \
    --enable-default-ssp \
    --disable-nls \
    --disable-multilib \
    --disable-bootstrap \
    2>&1 | tee "${BLD}/configure.log"

  log "Building GCC Stage 2 (${JOBS} jobs)..."
  make -j"${JOBS}" \
    2>&1 | tee "${BLD}/build.log"

  log "Installing GCC Stage 2..."
  make install \
    2>&1 | tee "${BLD}/install.log"

  ln -sfv "${TARGET}-gcc" "${TOOLCHAIN_DIR}/bin/${TARGET}-cc" 2>/dev/null || true

  log "GCC Stage 2 complete ✓"
  mark_done "gcc-stage2"
}

# =============================================================================
#  STEP 12 — Build Ncurses (target)
# =============================================================================
step_ncurses() {
  step "STEP 12 — Building Ncurses ${VER_NCURSES} for target"
  is_done "ncurses" && { info "Already done — skipping."; return 0; }

  local SRC="${SOURCES_DIR}/ncurses-${VER_NCURSES}"
  local BLD="${BUILD_DIR}/ncurses"
  [[ -d "${SRC}" ]] || die "ncurses source not found: ${SRC}"

  mkdir -p "${BLD}"; cd "${BLD}"

  CC="${TARGET}-gcc" \
  "${SRC}/configure" \
    --prefix=/usr \
    --host="${TARGET}" \
    --build="$(uname -m)-linux-gnu" \
    --with-shared \
    --without-debug \
    --without-ada \
    --enable-widec \
    --enable-pc-files \
    --with-pkg-config-libdir=/usr/lib/pkgconfig \
    2>&1 | tee "${BLD}/configure.log"

  make -j"${JOBS}" 2>&1 | tee "${BLD}/build.log"
  make install DESTDIR="${SYSROOT}" 2>&1 | tee "${BLD}/install.log"

  for lib in ncurses form panel menu; do
    ln -sfv lib${lib}w.so "${SYSROOT}/usr/lib/lib${lib}.so" 2>/dev/null || true
  done

  log "Ncurses complete ✓"
  mark_done "ncurses"
}

# =============================================================================
#  STEP 13 — Build Readline (target)
# =============================================================================
step_readline() {
  step "STEP 13 — Building Readline ${VER_READLINE} for target"
  is_done "readline" && { info "Already done — skipping."; return 0; }

  local SRC="${SOURCES_DIR}/readline-${VER_READLINE}"
  local BLD="${BUILD_DIR}/readline"
  [[ -d "${SRC}" ]] || die "readline source not found: ${SRC}"

  mkdir -p "${BLD}"; cd "${BLD}"

  CC="${TARGET}-gcc" \
  "${SRC}/configure" \
    --prefix=/usr \
    --host="${TARGET}" \
    --build="$(uname -m)-linux-gnu" \
    --enable-shared \
    --disable-static \
    2>&1 | tee "${BLD}/configure.log"

  make -j"${JOBS}" SHLIB_LIBS="-lncursesw" \
    2>&1 | tee "${BLD}/build.log"
  make install DESTDIR="${SYSROOT}" \
    2>&1 | tee "${BLD}/install.log"

  log "Readline complete ✓"
  mark_done "readline"
}

# =============================================================================
#  STEP 14 — Build Bash (target)
# =============================================================================
step_bash() {
  step "STEP 14 — Building Bash ${VER_BASH} for target"
  is_done "bash" && { info "Already done — skipping."; return 0; }

  local SRC="${SOURCES_DIR}/bash-${VER_BASH}"
  local BLD="${BUILD_DIR}/bash"
  [[ -d "${SRC}" ]] || die "bash source not found: ${SRC}"

  mkdir -p "${BLD}"; cd "${BLD}"

  CC="${TARGET}-gcc" \
  "${SRC}/configure" \
    --prefix=/usr \
    --host="${TARGET}" \
    --build="$(uname -m)-linux-gnu" \
    --without-bash-malloc \
    --with-installed-readline="${SYSROOT}/usr" \
    bash_cv_strtold_broken=no \
    2>&1 | tee "${BLD}/configure.log"

  make -j"${JOBS}" 2>&1 | tee "${BLD}/build.log"
  make install DESTDIR="${SYSROOT}" 2>&1 | tee "${BLD}/install.log"

  ln -sfv bash "${SYSROOT}/usr/bin/sh" 2>/dev/null || true

  log "Bash complete ✓"
  mark_done "bash"
}

# =============================================================================
#  STEP 15 — Build Coreutils (target)
# =============================================================================
step_coreutils() {
  step "STEP 15 — Building Coreutils ${VER_COREUTILS} for target"
  is_done "coreutils" && { info "Already done — skipping."; return 0; }

  local SRC="${SOURCES_DIR}/coreutils-${VER_COREUTILS}"
  local BLD="${BUILD_DIR}/coreutils"
  [[ -d "${SRC}" ]] || die "coreutils source not found: ${SRC}"

  mkdir -p "${BLD}"; cd "${BLD}"

  CC="${TARGET}-gcc" \
  "${SRC}/configure" \
    --prefix=/usr \
    --host="${TARGET}" \
    --build="$(uname -m)-linux-gnu" \
    --enable-install-program=hostname \
    --enable-no-install-program=kill,uptime \
    gl_cv_macro_MB_CUR_MAX_good=y \
    fu_cv_sys_mounted_mtab=yes \
    2>&1 | tee "${BLD}/configure.log"

  make -j"${JOBS}" 2>&1 | tee "${BLD}/build.log"
  make install DESTDIR="${SYSROOT}" 2>&1 | tee "${BLD}/install.log"

  log "Coreutils complete ✓"
  mark_done "coreutils"
}

# =============================================================================
#  STEP 16 — Build Inetutils (target)
# =============================================================================
step_inetutils() {
  step "STEP 16 — Building Inetutils ${VER_INETUTILS} for target"
  is_done "inetutils" && { info "Already done — skipping."; return 0; }

  local SRC="${SOURCES_DIR}/inetutils-${VER_INETUTILS}"
  local BLD="${BUILD_DIR}/inetutils"
  [[ -d "${SRC}" ]] || die "inetutils source not found: ${SRC}"

  mkdir -p "${BLD}"; cd "${BLD}"

  CC="${TARGET}-gcc" \
  "${SRC}/configure" \
    --prefix=/usr \
    --host="${TARGET}" \
    --build="$(uname -m)-linux-gnu" \
    --disable-servers \
    --disable-dnsdomainname \
    --disable-hostname \
    --disable-ping \
    --disable-ping6 \
    --disable-rcp \
    --disable-rexec \
    --disable-rlogin \
    --disable-rsh \
    --disable-logger \
    --disable-whois \
    --disable-ifconfig \
    --disable-traceroute \
    2>&1 | tee "${BLD}/configure.log"

  make -j"${JOBS}" 2>&1 | tee "${BLD}/build.log"
  make install DESTDIR="${SYSROOT}" 2>&1 | tee "${BLD}/install.log"

  log "Inetutils complete ✓"
  mark_done "inetutils"
}

# =============================================================================
#  STEP 17 — Build sed (target)
# =============================================================================
step_sed() {
  step "STEP 17 — Building sed ${VER_SED} for target"
  is_done "sed" && { info "Already done — skipping."; return 0; }

  local SRC="${SOURCES_DIR}/sed-${VER_SED}"
  local BLD="${BUILD_DIR}/sed"
  [[ -d "${SRC}" ]] || die "sed source not found: ${SRC}"

  mkdir -p "${BLD}"; cd "${BLD}"

  CC="${TARGET}-gcc" \
  "${SRC}/configure" \
    --prefix=/usr \
    --host="${TARGET}" \
    --build="$(uname -m)-linux-gnu" \
    --disable-nls \
    2>&1 | tee "${BLD}/configure.log"

  make -j"${JOBS}" 2>&1 | tee "${BLD}/build.log"
  make install DESTDIR="${SYSROOT}" 2>&1 | tee "${BLD}/install.log"

  log "sed complete ✓"
  mark_done "sed"
}

# =============================================================================
#  STEP 18 — Build gawk (target)
# =============================================================================
step_gawk() {
  step "STEP 18 — Building gawk ${VER_GAWK} for target"
  is_done "gawk" && { info "Already done — skipping."; return 0; }

  local SRC="${SOURCES_DIR}/gawk-${VER_GAWK}"
  local BLD="${BUILD_DIR}/gawk"
  [[ -d "${SRC}" ]] || die "gawk source not found: ${SRC}"

  mkdir -p "${BLD}"; cd "${BLD}"

  CC="${TARGET}-gcc" \
  "${SRC}/configure" \
    --prefix=/usr \
    --host="${TARGET}" \
    --build="$(uname -m)-linux-gnu" \
    --disable-nls \
    --without-mpfr \
    2>&1 | tee "${BLD}/configure.log"

  make -j"${JOBS}" 2>&1 | tee "${BLD}/build.log"
  make install DESTDIR="${SYSROOT}" 2>&1 | tee "${BLD}/install.log"

  log "gawk complete ✓"
  mark_done "gawk"
}

# =============================================================================
#  STEP 19 — Build m4 (target)
# =============================================================================
step_m4() {
  step "STEP 19 — Building m4 ${VER_M4} for target"
  is_done "m4" && { info "Already done — skipping."; return 0; }

  local SRC="${SOURCES_DIR}/m4-${VER_M4}"
  local BLD="${BUILD_DIR}/m4"
  [[ -d "${SRC}" ]] || die "m4 source not found: ${SRC}"

  mkdir -p "${BLD}"; cd "${BLD}"

  CC="${TARGET}-gcc" \
  "${SRC}/configure" \
    --prefix=/usr \
    --host="${TARGET}" \
    --build="$(uname -m)-linux-gnu" \
    --disable-nls \
    2>&1 | tee "${BLD}/configure.log"

  make -j"${JOBS}" 2>&1 | tee "${BLD}/build.log"
  make install DESTDIR="${SYSROOT}" 2>&1 | tee "${BLD}/install.log"

  log "m4 complete ✓"
  mark_done "m4"
}

# =============================================================================
#  STEP 20 — Build diffutils (target)
# =============================================================================
step_diffutils() {
  step "STEP 20 — Building diffutils ${VER_DIFFUTILS} for target"
  is_done "diffutils" && { info "Already done — skipping."; return 0; }

  local SRC="${SOURCES_DIR}/diffutils-${VER_DIFFUTILS}"
  local BLD="${BUILD_DIR}/diffutils"
  [[ -d "${SRC}" ]] || die "diffutils source not found: ${SRC}"

  mkdir -p "${BLD}"; cd "${BLD}"

  CC="${TARGET}-gcc" \
  "${SRC}/configure" \
    --prefix=/usr \
    --host="${TARGET}" \
    --build="$(uname -m)-linux-gnu" \
    --disable-nls \
    2>&1 | tee "${BLD}/configure.log"

  make -j"${JOBS}" 2>&1 | tee "${BLD}/build.log"
  make install DESTDIR="${SYSROOT}" 2>&1 | tee "${BLD}/install.log"

  log "diffutils complete ✓"
  mark_done "diffutils"
}

# =============================================================================
#  STEP 21 — Build findutils (target)
# =============================================================================
step_findutils() {
  step "STEP 21 — Building findutils ${VER_FINDUTILS} for target"
  is_done "findutils" && { info "Already done — skipping."; return 0; }

  local SRC="${SOURCES_DIR}/findutils-${VER_FINDUTILS}"
  local BLD="${BUILD_DIR}/findutils"
  [[ -d "${SRC}" ]] || die "findutils source not found: ${SRC}"

  mkdir -p "${BLD}"; cd "${BLD}"

  CC="${TARGET}-gcc" \
  "${SRC}/configure" \
    --prefix=/usr \
    --host="${TARGET}" \
    --build="$(uname -m)-linux-gnu" \
    --disable-nls \
    2>&1 | tee "${BLD}/configure.log"

  make -j"${JOBS}" 2>&1 | tee "${BLD}/build.log"
  make install DESTDIR="${SYSROOT}" 2>&1 | tee "${BLD}/install.log"

  log "findutils complete ✓"
  mark_done "findutils"
}

# =============================================================================
#  STEP 22 — Build grep (target)
# =============================================================================
step_grep() {
  step "STEP 22 — Building grep ${VER_GREP} for target"
  is_done "grep" && { info "Already done — skipping."; return 0; }

  local SRC="${SOURCES_DIR}/grep-${VER_GREP}"
  local BLD="${BUILD_DIR}/grep"
  [[ -d "${SRC}" ]] || die "grep source not found: ${SRC}"

  mkdir -p "${BLD}"; cd "${BLD}"

  CC="${TARGET}-gcc" \
  "${SRC}/configure" \
    --prefix=/usr \
    --host="${TARGET}" \
    --build="$(uname -m)-linux-gnu" \
    --disable-nls \
    2>&1 | tee "${BLD}/configure.log"

  make -j"${JOBS}" 2>&1 | tee "${BLD}/build.log"
  make install DESTDIR="${SYSROOT}" 2>&1 | tee "${BLD}/install.log"

  log "grep complete ✓"
  mark_done "grep"
}

# =============================================================================
#  Main Execution
# =============================================================================
main() {
  banner
  
  # Step 1: Initialize Workspace
  step_init_workspace
  
  # Step 2: Install host dependencies (pacman / apt / dnf)
  step_install_deps
  
  # Step 3 & 4: Get and prep sources
  step_download
  step_extract
  
  # Step 5: Setup directory tree
  step_prepare_env
  
  # Step 5b: Fetch & extract rootfs template
  step_rootfs_template

  # Step 6: Kernel headers
  step_linux_headers
  
  # Step 7 & 8: Initial toolchain build (Stage 1)
  step_binutils_stage1
  step_gcc_stage1
  
  # Step 9 & 10: C Library
  step_glibc_headers
  step_glibc_full
  
  # Step 11: Final compiler (Stage 2)
  step_gcc_stage2
  
  # Steps 12-22: Target utilities
  step_ncurses
  step_readline
  step_bash
  step_coreutils
  step_inetutils
  step_sed
  step_gawk
  step_m4
  step_diffutils
  step_findutils
  step_grep

  step "🎉 Toolchain and Base System Build Complete! 🎉"
  log "Project Directory: ${PROJECT_DIR}"
  log "Sysroot is available at: ${SYSROOT}"
  log "Cross-tools are at: ${TOOLCHAIN_DIR}"
}

# Run main
main "$@"
