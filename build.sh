#!/usr/bin/env bash

set -e

QT_CFG=''

BUILD_CONFIRM=0
COMPILE_JOBS=1
MAKEFLAGS_JOBS=''

if [[ "$MAKEFLAGS" != "" ]]; then
  MAKEFLAGS_JOBS=$(echo $MAKEFLAGS | egrep -o '\-j[0-9]+' | egrep -o '[0-9]+')
fi

if [[ "$MAKEFLAGS_JOBS" != "" ]]; then
  # user defined number of jobs in MAKEFLAGS, re-use that number
  COMPILE_JOBS=$MAKEFLAGS_JOBS
elif [[ $OSTYPE = darwin* ]]; then
   # We only support modern Mac machines, they are at least using
   # hyperthreaded dual-core CPU.
   COMPILE_JOBS=4
elif [[ $OSTYPE == freebsd* ]]; then
   COMPILE_JOBS=`sysctl -n hw.ncpu`
else
   CPU_CORES=`grep -c ^processor /proc/cpuinfo`
   if [[ "$CPU_CORES" -gt 1 ]]; then
       COMPILE_JOBS=$CPU_CORES
   fi
fi

if [[ "$COMPILE_JOBS" -gt 8 ]]; then
   # Safety net.
   COMPILE_JOBS=8
fi

SILENT=''
QTDEPLIBS=bundled
QTCORE=bundled
QTWEBKIT=bundled

until [ -z "$1" ]; do
    case $1 in
        "--qt-config")
            shift
            QT_CFG=" $1"
            shift;;
        "--qmake-args")
            shift
            QMAKE_ARGS=$1
            shift;;
        "--jobs")
            shift
            COMPILE_JOBS=$1
            shift;;
        "--confirm")
            BUILD_CONFIRM=1
            shift;;
        "--silent")
            SILENT=silent
            shift;;
        "--system-qtdeps")
            QTDEPLIBS=system
            shift;;
        "--system-qt")
            QTDEPLIBS=system
            QTCORE=system
            shift;;
        "--system-qtwebkit")
            QTDEPLIBS=system
            QTCORE=system
            QTWEBKIT=system
            shift;;
        "--help")
            cat <<EOF
Usage: $0 [--qt-config CONFIG] [--jobs NUM]

  --confirm                   Do not prompt for confirmation of this
                              very slow build process.
  --silent                    Produce less verbose output.
  --jobs NUM                  How many parallel compile jobs to use.
                              Defaults to the number of CPU cores you have,
                              with a maximum of 8.
  --qt-config CONFIG          Specify extra config options to be used when
                              configuring Qt.
  --system-qtdeps             Use system-provided libraries for all of Qt's
                              dependencies (e.g. freetype, libpng).
                              EXPERIMENTAL.
  --system-qt                 Use system-provided Qt core libraries.
                              EXPERIMENTAL, build may not succeed.
                              Implies --system-qtdeps.
                              Mutually exclusive with --qt-config.
  --system-qtwebkit           Use system-provided QtWebkit.
                              EXPERIMENTAL, build may not succeed.
                              Implies --system-qt and --system-qtdeps.
                              Mutually exclusive with --qt-config.

EOF
            exit 0
            ;;
        *)
            echo "Unrecognised option: $1" >&2
            exit 1;;
    esac
done

if [[ "$QTCORE" = system ]] && [[ -n "$QT_CFG" ]]; then
    echo "$0: --qt-config and --system-qt(webkit) are mutually exclusive" >&2
    exit 1
fi

if [[ "$BUILD_CONFIRM" -eq 0 ]]; then
cat << EOF
----------------------------------------
               WARNING
----------------------------------------

Building PhantomJS from source takes a very long time, anywhere from 30
minutes to several hours (depending on the machine configuration).
We recommend you use the premade binary packages on supported operating
systems.

For details, please go the the web site: http://phantomjs.org/download.html.

EOF

    echo "Do you want to continue (y/n)?"
    read continue
    if [[ "$continue" != "y" ]]; then
        exit 1
    fi
    echo
    echo
fi

UNAME_SYSTEM=`(uname -s) 2>/dev/null`  || UNAME_SYSTEM=unknown
UNAME_RELEASE=`(uname -r) 2>/dev/null` || UNAME_RELEASE=unknown
UNAME_MACHINE=`(uname -m) 2>/dev/null` || UNAME_MACHINE=unknown

MAKE_S=""
if [[ "$SILENT" == "silent" ]]; then
    MAKE_S="-s"
    QT_CFG+=" -silent"
fi

echo "System architecture... ($UNAME_SYSTEM $UNAME_RELEASE $UNAME_MACHINE)"
echo

if [[ "$QTCORE" == "bundled" ]]; then
    export QMAKE=$PWD/src/qt/qtbase/bin/qmake
    ( cd src/qt && ./preconfig.sh $QTDEPLIBS $QT_CFG )

    echo
    echo "Building Qt..."
    echo
    ( cd src/qt/qtbase && make -j$COMPILE_JOBS $MAKE_S )
else
    export QMAKE=qmake
    # some Linux distros (e.g. Debian) allow you to parallel-install
    # Qt4 and Qt5, using this environment variable to declare which
    # one you want
    export QT_SELECT=qt5
fi

if [[ "$QTWEBKIT" == "bundled" ]]; then
    echo
    echo "Building QtWebkit..."
    echo
    if [[ "$QTDEPLIBS" == "bundled" ]]; then
        export SQLITE3SRCDIR=$PWD/src/qt/qtbase/src/3rdparty/sqlite/
    fi
    ( cd src/qt/qtwebkit &&
        $QMAKE $QMAKE_ARGS &&
        make -j$COMPILE_JOBS $MAKE_S )
fi

echo
echo "Building main PhantomJS application..."
echo
$QMAKE $QMAKE_ARGS
make -j$COMPILE_JOBS
