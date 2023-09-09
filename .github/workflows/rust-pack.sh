#!/bin/bash
set -ex

pack() {
    local tempdir
    local out_dir
    local package_name
    local gcc_prefix

    tempdir=$(mktemp -d 2>/dev/null || mktemp -d -t tmp)
    out_dir=$(pwd)

    [[ $GITHUB_REF == *"refs/tags"* ]] && TAG=$GITHUB_REF || TAG="manual-continous-deployment"

    package_name="$PROJECT_NAME-${TAG/refs\/tags\//}-$TARGET"

    if [[ $TARGET == "arm-unknown-linux-gnueabihf" ]]; then
        gcc_prefix="arm-linux-gnueabihf-"
    elif [[ $TARGET == "aarch64-unknown-linux-gnu" ]]; then
        gcc_prefix="aarch64-linux-gnu-"
    elif [[ $TARGET == "aarch64-unknown-linux-musl" ]]; then
        gcc_prefix="/tmp/aarch64-linux-musl-cross/bin/aarch64-linux-musl-" # TODO: Refactorme
    else
        gcc_prefix=""
    fi

    # create a "staging" directory
    mkdir "$tempdir/$package_name"

    # copying the main binary
    cp "target/$TARGET/release/$PROJECT_NAME" "$tempdir/$package_name/"
    if [ "$OS_NAME" != windows-latest ]; then
        "${gcc_prefix}"strip "$tempdir/$package_name/$PROJECT_NAME"
    fi

    # manpage, readme and licence
    cp README.md "$tempdir/$package_name"
    cp LICENCE.md "$tempdir/$package_name"

    # archiving
    pushd "$tempdir/$package_name"
    if [ "$OS_NAME" = windows-latest ]; then
        7z a "$out_dir/$package_name.zip" *
    else
        tar czf "$out_dir/$package_name.tar.gz" *
    fi
    popd
    rm -r "$tempdir"
}


make_deb() {
    local tempdir
    local architecture
    local version
    local dpkgname
    local conflictname
    local gcc_prefix

    case $TARGET in
        x86_64*)
            architecture=amd64
            gcc_prefix=""
            library_dir=""
            ;;
        i686*)
            architecture=i386
            gcc_prefix=""
            library_dir=""
            ;;
        aarch64-unknown-linux-gnu*)
            architecture=arm64
            gcc_prefix="aarch64-linux-gnu-"
            library_dir="-l/usr/aarch64-linux-gnu/lib"
            ;;
        aarch64-unknown-linux-musl*)
            architecture=arm64
            gcc_prefix="/tmp/aarch64-linux-musl-cross/bin/aarch64-linux-musl-" #TODO: Refactorme
            library_dir="-l/usr/aarch64-linux-gnu/lib"
            ;;
        arm*hf)
            architecture=armhf
            gcc_prefix="arm-linux-gnueabihf-"
            library_dir="-l/usr/arm-linux-gnueabihf/lib"
            ;;
        *)
            echo "make_deb: skipping target '${TARGET}'" >&2
            return 0
            ;;
    esac
    [[ $GITHUB_REF == *"refs/tags"* ]] && TAG=$GITHUB_REF || TAG="0-manual-continous-deployment"
    version=${TAG/refs\/tags\//}

    if [[ $TARGET = *musl* ]]; then
      dpkgname=$PROJECT_NAME-musl
      conflictname=$PROJECT_NAME
    else
      dpkgname=$PROJECT_NAME
      conflictname=$PROJECT_NAME-musl
    fi

    tempdir=$(mktemp -d 2>/dev/null || mktemp -d -t tmp)

    # copy the main binary
    install -Dm755 "target/$TARGET/release/$PROJECT_NAME" "$tempdir/usr/bin/$PROJECT_NAME"
    "${gcc_prefix}"strip "$tempdir/usr/bin/$PROJECT_NAME"

    # Work out shared library dependencies
    # dpkg-shlibdeps requires debian/control file. Dummy it and clean up
    mkdir "./debian"
    touch "./debian/control"
    depends="$(dpkg-shlibdeps $library_dir -O "$tempdir/usr/bin/$PROJECT_NAME" 2> /dev/null | sed 's/^shlibs:Depends=//')"
    rm -rf "./debian"

    # readme and licence
    install -Dm644 README.md "$tempdir/usr/share/doc/$dpkgname/README.md"
    cat > "$tempdir/usr/share/doc/$dpkgname/copyright" <<EOF
Format: http://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: $PROJECT_NAME
Source: $HOMEPAGE
Files: *
Copyright: $COPYRIGHT_YEARS $MAINTAINER
Licence:
EOF
    cat LICENCE.md >> "$tempdir/usr/share/doc/$dpkgname/copyright"
    chmod 644 "$tempdir/usr/share/doc/$dpkgname/copyright"

    # Control file
    mkdir "$tempdir/DEBIAN"
    cat > "$tempdir/DEBIAN/control" <<EOF
Package: $dpkgname
Version: $version
Section: utils
Priority: optional
Maintainer: $MAINTAINER
Architecture: $architecture
Depends: $depends
Provides: $PROJECT_NAME
Conflicts: $conflictname
Description: $DESCRIPTION
EOF

    fakeroot dpkg-deb --build "$tempdir" "${dpkgname}_${version}_${architecture}.deb"
}

main() {
    if [[ $TARGET == "aarch64-unknown-linux-musl" ]]; then
        wget https://musl.cc/aarch64-linux-musl-cross.tgz -q --show-progress --progress=bar:force 2>&1
        tar zxf aarch64-linux-musl-cross.tgz
        mv aarch64-linux-musl-cross/ /tmp
    fi
    pack
    if [[ $TARGET = *linux* ]]; then
      make_deb
    fi
}

main
