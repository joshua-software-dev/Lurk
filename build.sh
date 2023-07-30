#!/bin/bash

printf "zig build -Dcpu=baseline -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSmall\n"
zig build -Dcpu=baseline -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSmall

# Inspiration for any packagers
# https://github.com/jordansissel/fpm

# currentversion=$(grep ".version" build.zig.zon | awk -F '"' '{print $2}')
# fpm -f -t deb -p "lurk-$currentversion-$(uname -m).deb" --version "$currentversion"
# fpm -f -t rpm -p "lurk-$currentversion-$(uname -m).rpm" --version "$currentversion"
# fpm -f -t pacman -p "lurk-$currentversion-$(uname -m).pkg.tar.zst" --version "$currentversion"
# fpm -f -t tar -p "lurk-$currentversion-$(uname -m).tar.gz" --version "$currentversion"

# $ file lurk-1.0.0-x86_64.*
# lurk-1.0.0-x86_64.deb:         Debian binary package (format 2.0), with control.tar.gz, data compression gz
# lurk-1.0.0-x86_64.pkg.tar.zst: Zstandard compressed data (v0.8+), Dictionary ID: None
# lurk-1.0.0-x86_64.rpm:         RPM v3.0 bin i386/x86_64
# lurk-1.0.0-x86_64.tar.gz:      gzip compressed data, from Unix, original size modulo 2^32 911360
