#!/bin/bash
# The directory where projects are stored
GENERIC_DIRECTORY=$PWD
# Supported targets in GNU format
SUPPORTED_TARGETS=('i686-elf' 'x86_64-elf' 'arm-none-eabi')
# SUPPORTED_TARGETS corresponding targets in qemu form
QEMU_TARGETS=('i386-softmmu' 'x86_64-softmmu' 'arm-softmmu')

# Name of environnement setter file
FNAME_ENV="setenv.bash"

# Name of directories to put tools
DNAME_GCC="gcc"
DNAME_GDB="gdb"
DNAME_QEMU="qemu"
DNAME_BINUTILS="binutils"
DNAME_NINJA="ninja"
DNAME_BIN="bin"

TAG_GCC="releases/gcc-12.2.0"
TAG_GDB=nothing # To implement !
TAG_BINUTILS="binutils-2_39"

# Name of general directories
DNAME_TOOLS="tools"
DNAME_BUILD="build"
DNAME_CACHE="cache"
DNAME_SCRIPTS="scripts"
DNAME_LOGS="logs"

# Internal global values
# boolean whenether packages are silently installed
INSTALL_PKGS=0
# boolean whenether tools are silently kept instead of downloaded again
KEEP_DOWNLOADED=0
# The cmdline name of download client see get_download_client
DOWNLOAD_CLIENT=""

ON_EXIT=""
OLD_PATH=""

# $1 code
exit_clean() {
	if [[ "$ON_EXIT" != "" ]]; then
		eval ON_EXIT
	fi
	if [[ "$PATH" != "$OLD_PATH" ]]; then
		echo "It is recommended to restart the terminal as env could be changed !"
	fi
	PATH="$OLD_PATH"
	exit $1
}

exit_user() {
  echo "User requesting exit..."
  exit_clean 1
}

exit_unsupported_distri() {
	echo "Unsupported distribution"
  exit_clean 2
}

exit_missing_dependency() {
  echo "Missing dependency, could not continue"
  exit_clean 3
}

exit_external_error() {
  exit_clean 4
}

# $1 source file .tar.gz
# $2 destination folder
untar_gz() {
  mkdir -p $2
  tar -xzf $1 -C $2
}

# $1: array
# $2: value
# R: the index where value is in array otherwise $#+1
get_index() {
  v=$1; i=0
  while [ "$v" != "$2" ] && [ $i -le $# ] ; do
    shift; ((i++))
  done
  return $i
}

# internal do not use
# $1: directory to clone
# R: 0: git clone, 1: do nothing
_git_clone_check() {
	if [ -d "$1" ]; then
    if [ $KEEP_DOWNLOADED -eq 1 ]; then
      return 1
    fi
    read -n 1 -r -p "Directory $1 already exists, do you want to keep it ? otherwise it will be re-downloaded (y/n/a) "
    case $REPLY in
    ^[Nn]) rm -rf "$1";;
    ^[Aa]) KEEP_DOWNLOADED=1; return 1;;
    *) return 1;;
    esac
  fi
  return 0
}

# $1: git url
# $2: directory
git_clone() {
  _git_clone_check "$2"
  if [ $? -eq 0 ]; then
    git clone $1 "$2"
  fi
}

# $1: git url
# $2: directory
# $3: tag
git_clone_tag() {
  _git_clone_check "$2"
  if [ $? -eq 0 ]; then
    git clone $1 "$2" --depth 1 --branch $3
  fi
}

prefetch_package() {
  case $ID in
  centos) yum updateinfo;;
  debian|ubuntu) apt update;;
  *) echo "Distribution not recognized, no prefetech to be done";;
  esac
}

# $1: pkg name
# R: status or noreturn
check_if_package() {
  case $ID in
  centos) rpm --quiet -q $1;;
  debian|ubuntu) dpkg -s $1 &> /dev/null;;
  *) echo "Could not check if package is present."
    echo "Please add package check support at check_if_package for this distribution"
    exit_unsupported_distri;;
  esac
  return $?
}

# $1: pkg name
install_package() {
  case $ID in
  centos) sudo yum -y install $1;;
  debian|ubuntu) sudo apt -y install $1;;
  *) echo "Could not install package."
    echo "Please add package check support at install_package for this distribution"
    exit_unsupported_distri;;
  esac
  [ $? -eq 0 ] || exit_external_error
}

# $1: pkg name
check_if_package_mandatory() {
  check_if_package $1
  if [ $? -eq 1 ]; then
    if [ $INSTALL_PKGS -eq 0 ]; then
      install_package $1
    else
      echo "Could not find package \'$1\' while mandatory..." 
      read -p "Do you want to install it ? (y/n/a) " -n 1 -r
      case $REPLY in
      ^[Yy]) install_package $1;;
      ^[Nn]) exit_missing_dependency;;
      ^[Aa]) INSTALL_PKGS=1
        install_package $1;;
        *) exit_missing_dependency;;
      esac
    fi
  fi
}

# $1: pkg list
check_dependencies_mandatory() {
  for dep in $@; do
    check_if_package_mandatory $dep
    [ $? -eq 0 ] || echo "Error during dependency check/install process" || exit_missing_dependency
  done
}

# R: 0 or noreturn
get_download_client() {
  check_if_package curl
  [ $? -eq 0 ] && DOWNLOAD_CLIENT=curl && return 0
  check_if_package wget
  [ $? -eq 0 ] && DOWNLOAD_CLIENT=wget && return 0
  echo "Error: no download client available. To add a custom one"
  echo "implement it in get_download_client & download"
  exit_missing_dependency
}

# $1: url
# $2: local file
# R: Status
download() {
  if [ -f $2 ]; then
    read -n 1 -r -p "File $2 already exists, do you want to keep it ? (y/n) "
    echo 
    if [[ ${REPLY} =~ ^[Yy]$ ]]; then
      return 0
    else
      rm -rf "$2"
    fi
  fi
  case $DOWNLOAD_CLIENT in
  curl) curl $1 --output $2;;
  wget) wget $1 -O $2;;
  *) echo "Unimplemented download client. Please add it in download()."
    exit_external_error;;
  esac
  return $?
}

get_gcc() {
  git_clone_tag https://gcc.gnu.org/git/gcc.git $DIR_TOOLS/$DNAME_GCC $TAG_GCC
}

get_gdb() {
  if [ -d "$DIR_TOOLS/$DNAME_GDB" ]; then
    read -n 1 -r -p "Directory $DIR_TOOLS/$DNAME_GDB already exists, do you want to override it ? (y/n) "
    echo 
    
    if [[ ${REPLY} =~ ^[Yy]$ ]]; then
      rm -rf "$DIR_TOOLS/$DNAME_GDB"
    else
	  return 0
    fi
  fi
  # git version of gdb is instable so we download a release
  # git_clone https://sourceware.org/git/binutils-gdb.git $DIR_TOOLS/$DNAME_GDB
  download ftp://sourceware.org/pub/gdb/releases/gdb-12.1.tar.gz $DIR_CACHE/gdb.tar.gz
  untar_gz "$DIR_CACHE/gdb.tar.gz" "$DIR_TOOLS"
  
  # This should be changed
  mv "$DIR_TOOLS/gdb-12.1" "$DIR_TOOLS/$DNAME_GDB"
}

get_qemu() {
  git_clone https://gitlab.com/qemu-project/qemu.git $DIR_TOOLS/$DNAME_QEMU
}

get_binutils() {
  git_clone_tag https://sourceware.org/git/binutils-gdb.git $DIR_TOOLS/$DNAME_BINUTILS $TAG_BINUTILS
}

get_ninja() {
  git_clone http://github.com/ninja-build/ninja.git $DIR_TOOLS/$DNAME_NINJA
}

# This must be called by build_gcc as it is a submodule sharing dependencies
build_binutils() {
  builddir=$DIR_BUILD/$DNAME_BINUTILS
  rm -rf $builddir
  mkdir -p $builddir
  cd $builddir
  $DIR_TOOLS/$DNAME_BINUTILS/configure --target=$GNU_TARGET --prefix="$PREFIX" --with-sysroot --disable-nls --disable-werror --enable-lto --enable-interwork --enable-multilib | tee $DIR_LOGS/binutils_configure.log
  make -j$(nproc) | tee $DIR_LOGS/binutils_make.log
  make install -j$(nproc) | tee $DIR_LOGS/binutils_make_install.log
  cd $DEV_DIR
}

build_gcc() {
  debian_dependencies=('build-essential' 'bison' 'flex' 'libgmp3-dev' 'libmpc-dev' 'libmpfr-dev' 'texinfo')
  centos_dependencies=('gcc' 'gcc-c++' 'make' 'bison' 'flex' 'gmp-devel' 'libmpc-devel' 'mpfr-devel' 'texinfo')
  dependencies=()
  case $ID in
    debian|ubuntu) dependencies="${debian_dependencies[@]}";;
	# On CentOS, we need GCC-7 to build other packages, we use it as scl in a new bash which must be exited
    centos) install_package centos-release-scl
	install_package devtoolset-7
	source scl_source enable devtoolset-7
	echo "GCC version:"
	gcc --version
	dependencies="${centos_dependencies[@]}";;
    *) echo "Could not deduce dependencies for this distribution. Please add support at build_gcc."
    exit_unsupported_distri;;
  esac
  check_dependencies_mandatory ${dependencies[@]}
  build_binutils
  builddir=$DIR_BUILD/$DNAME_GCC
  rm -rf $builddir
  mkdir -p $builddir
  cd $builddir
  $DIR_TOOLS/$DNAME_GCC/configure --target=$GNU_TARGET --prefix="$PREFIX" --disable-nls --enable-languages=c,c++ --without-headers --enable-interwork  --enable-multilib | tee $DIR_LOGS/gcc_configure.log
  make all-gcc -j$(nproc) | tee $DIR_LOGS/gcc_make_allgcc.log
  make -j$(nproc) | tee $DIR_LOGS/gcc_make.log
  make install -j$(nproc) | tee $DIR_LOGS/gcc_make_install.log
  make install-all-gcc -j$(nproc) | tee $DIR_LOGS/gcc_make_install_allgcc.log
  cd $DEV_DIR
}

build_gdb() {
  builddir=$DIR_BUILD/$DNAME_GDB
  rm -rf $builddir
  mkdir -p $builddir
  cd $builddir
  make distclean
  $DIR_TOOLS/$DNAME_GDB/configure --target=$GNU_TARGET --prefix="$PREFIX" | tee $DIR_LOGS/gdb_configure.log
  make -j$(nproc) | tee $DIR_LOGS/gdb_make.log
  make install -j$(nproc) | tee $DIR_LOGS/gdb_make_install.log
  cd $DEV_DIR
}


build_ninja() {
  check_dependencies_mandatory python2

  builddir=$DIR_BUILD/$DNAME_NINJA
  rm -rf $builddir
  mkdir -p $builddir
  cd $builddir
  # On CentOS, gcc by default is 2 but ninja requires 7
  if [ "$ID" == "centos" ]; then
    OLD_CC="$CC"
    OLD_CXX="$CXX"
    CC="/opt/rh/devtoolset-7/root/usr/bin/gcc"
	CXX="/opt/rh/devtoolset-7/root/usr/bin/g++"
	cmake3 -G "Unix Makefiles" $DIR_TOOLS/$DNAME_NINJA | tee $DIR_LOGS/ninja_cmake.log
	make | tee $DIR_LOGS/ninja_make.log
	CC="$OLD_CC"
    CXX="$OLD_CXX"
  else
	python2 $DIR_TOOLS/$DNAME_NINJA/configure.py --bootstrap | tee $DIR_LOGS/ninja_configure.log
  fi
  cd $DEV_DIR
}

build_qemu() {
  debian_dependencies=('libglib2.0-dev' 'libfdt-dev' 'libpixman-1-dev' 'zlib1g-dev')
  centos_dependencies=('glib2-devel' 'cmake3' 'libfdt-devel' 'pixman-devel' 'zlib-devel')
  dependencies=()
  case $ID in
    debian|ubuntu) dependencies="${debian_dependencies[@]}";;
    centos) dependencies="${centos_dependencies[@]}";;
    *) echo "Could not deduce dependencies for this distribution. Please add support at build_qemu."
    exit_unsupported_distri;;
  esac
  check_dependencies_mandatory ${dependencies[@]}
  build_ninja

  builddir=$DIR_BUILD/$DNAME_QEMU
  rm -rf $builddir
  mkdir -p $builddir
  cd $builddir
  get_index $GNU_TARGET ${SUPPORTED_TARGETS[@]}
  export QEMU_TARGET=${QEMU_TARGETS[$?]}
  $DIR_TOOLS/$DNAME_QEMU/configure --enable-system --target-list=$QEMU_TARGET --ninja="$DIR_BUILD/$DNAME_NINJA/ninja" | tee $DIR_LOGS/qemu_configure.log
  make -j$(nproc) | tee $DIR_LOGS/qemu_make.log
  cd $DEV_DIR
}

# ENTRY
# set -x # for debug purposes
OLD_PATH="$PATH"
echo "Select a directory or enter a new one: "
ls -d */
read in_dir
DEV_DIR=$PWD/$in_dir

if [ ! -d $DEV_DIR ]; then
  read -p "$DEV_DIR doesn't exists, create ? (y/N) " -n 1 -r
  echo
  if [[ ${REPLY} =~ ^[Yy]$ ]]; then
    mkdir -p $DEV_DIR
  else
    exit_user
  fi
fi

export FILE_ENV=$DEV_DIR/$FNAME_ENV
export DIR_CACHE=$DEV_DIR/$DNAME_CACHE
export DIR_SCRIPTS=$DEV_DIR/$DNAME_SCRIPTS

cd $DEV_DIR

should_exit=0
while [ $should_exit -eq 0 ]; do

if [ ! -s $FILE_ENV ]; then
  echo "Empty ENV file, first-time startup"
  cat << EOF >> "$FILE_ENV"
export PATH="$DIR_BIN/bin:$DIR_BUILD/$DNAME_QEMU:\$PATH"
pushd .
cd $DIR_SCRIPTS
export OSDEV_TARGETS=(\$(for n in *; do if [ -f \$n ]; then echo "\${n%.*}"; fi; done))
popd
if [ "\$#" -ne 0 ]; then
  export ENV_FILE="$DIR_SCRIPTS/$1.bash"
  if [ ! -f "\$ENV_FILE" ]; then
    echo "Error: \$0 target is not installed ! check osdev.sh"
    exit 1
  else
    source "\$ENV_FILE"
  fi
fi
EOF

  REPLY=1 # Simulate entry 1
else
  source $FILE_ENV
  cat << _EOF
  [Workspace]: $DEV_DIR
  [Targets]: $OSDEV_TARGETS
  [Host]: $(arch)

  What do you want ?
  0 - Exit
  1 - Create a new target
  2 - Delete a target
  3 - Rebuild a target (full/part)
_EOF
  read -n 1 -r
fi

#Since this point, we could need distrib-specific stuff
. /etc/os-release

_pre_target_work() {
  get_download_client
  prefetch_package
  check_if_package_mandatory git
  
  export DIR_BUILD="$DEV_DIR/$DNAME_BUILD/$GNU_TARGET"
  export DIR_BIN="$DEV_DIR/$DNAME_BIN/$GNU_TARGET"
  export DIR_TOOLS="$DEV_DIR/$DNAME_TOOLS/$GNU_TARGET"
  export DIR_LOGS="$DEV_DIR/$DNAME_LOGS/$GNU_TARGET"
  export PREFIX="$DIR_BIN"
  
  
  mkdir -p $DIR_TOOLS
  mkdir -p $DIR_CACHE
  rm -rf $DIR_BIN
  mkdir -p $DIR_BIN
  mkdir -p $DIR_SCRIPTS
  mkdir -p $DIR_LOGS
}

rebuild_target() {
  if [ ${#OSDEV_TARGETS[@]} -eq 0 ]; then
    echo "No targets are available, please create one first"
    return 1
  fi
  if [ ${#OSDEV_TARGETS[@]} -eq 1 ]; then
    echo "Auto selecting target ${OSDEV_TARGETS[0]}"
    GNU_TARGET=${OSDEV_TARGETS[0]}
  else
    echo "Select target to modify"
    select GNU_TARGET in "${SUPPORTED_TARGETS[@]}"; do
    if [ $REPLY -le 0 ] || [ $REPLY -gt ${#SUPPORTED_TARGETS[@]} ]; then
      echo "Incorrect target id";
    else
      return 1
    fi
  done
  fi

  _pre_target_work

  cat << _EOF
  ===== Target rebuild tool =====
  [Workspace]: $DEV_DIR
  [Target]: $GNU_TARGET

  What do you want ?
  0 - Cancel
  1 - Rebuild full target
  2 - Rebuild GCC (+ binutils)
  3 - Rebuild GDB
  4 - Rebuild QEMU (+ ninja)
_EOF
  KEEP_DOWNLOADED=1
  read -n 1 -r
  case $REPLY in
  0) should_exit=1; return 2;;
  1) rm -rf $DIR_BIN
     rm -rf $DIR_SCRIPTS
     rm $FILE_ENV
     create_target $GNU_TARGET;;
  2) get_gcc
     get_binutils 
     build_gcc;;
  3) get_gdb
     build_gdb;;
  4) get_qemu
     get_ninja
     build_qemu;;
  *) echo "Incorrect option";;
  esac
  KEEP_DOWNLOADED=0
}

# $1: target to create (asked if empty)
create_target() {
  if [ $# -gt 0 ]; then
    GNU_TARGET=$0
  else
    echo "Creating a new target. Select target: "
    select GNU_TARGET in "${SUPPORTED_TARGETS[@]}"; do
      if [ $REPLY -le 0 ] || [ $REPLY -gt ${#SUPPORTED_TARGETS[@]} ]; then
        echo "Incorrect target id";
      else
        return 1
      fi
    done
  fi
  echo "Creating target: $GNU_TARGET"
  _pre_target_work
  
  get_gcc
  get_binutils
  get_gdb
  get_qemu
  get_ninja
  build_gcc
  build_gdb
  build_qemu
  # ln -s $DIR_BUILD/$DNAME_QEMU/${target_target%-*-*}
  cat << EOF >> "$DIR_SCRIPTS/$GNU_TARGET.bash"
export OSDEV_TARGET=$GNU_TARGET
export OSDEV_QEMU_TARGET=$QEMU_TARGET
EOF
  should_exit=1
}

# $1 $GNU_TARGET of target to delete
delete_target() {
  rm -f "$DIR_SCRIPTS/$1.bash"
  rm -rf "$DEV_DIR/$DNAME_BIN/$1"
  rm -rf "$DEV_DIR/$DNAME_BUILD/$1"
  rm -rf "$DEV_DIR/$DNAME_TOOLS/$1"
  rm -rf "$DEV_DIR/$DNAME_LOGS/$1"
}

case $REPLY in
  0) should_exit=1;;
  1) create_target;;
  2) delete_target $GNU_TARGET;;
  3) rebuild_target;;
  *) echo "Incorrect option";;
esac
done

cd $GENERIC_DIRECTORY
exit_clean 0
