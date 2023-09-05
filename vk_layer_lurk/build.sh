#!/bin/bash

printf "zig build -Dcpu=baseline -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSmall\n"
zig build -Dcpu=baseline -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSmall

# printf "zig build -Dcpu=baseline -Dtarget=x86-linux-gnu -Doptimize=ReleaseSmall\n"
# zig build -Dcpu=baseline -Dtarget=x86-linux-gnu -Doptimize=ReleaseSmall

# Inspiration for any packagers
# https://github.com/jordansissel/fpm

# ver=$(grep ".version" build.zig.zon | awk -F '"' '{print $2}')
# fpm -f -t deb    -a x86_64 -p "vk_layer_lurk-$ver-x86.deb"            --version "$ver" lib32=/usr/
# fpm -f -t rpm    -a x86_64 -p "vk_layer_lurk-$ver-x86.rpm"            --version "$ver" lib32=/usr/
# fpm -f -t pacman -a x86_64 -p "vk_layer_lurk-$ver-x86.pkg.tar.zst"    --version "$ver" lib32=/usr/
# fpm -f -t tar    -a x86_64 -p "vk_layer_lurk-$ver-x86.tar.gz"         --version "$ver" lib32=/usr/
# fpm -f -t deb    -a x86_64 -p "vk_layer_lurk-$ver-x86_64.deb"         --version "$ver" lib=/usr/
# fpm -f -t rpm    -a x86_64 -p "vk_layer_lurk-$ver-x86_64.rpm"         --version "$ver" lib=/usr/
# fpm -f -t pacman -a x86_64 -p "vk_layer_lurk-$ver-x86_64.pkg.tar.zst" --version "$ver" lib=/usr/
# fpm -f -t tar    -a x86_64 -p "vk_layer_lurk-$ver-x86_64.tar.gz"      --version "$ver" lib=/usr/

# $ file vk_layer_lurk-*
# vk_layer_lurk-1.0.0-x86_64.deb:         Debian binary package (format 2.0), with control.tar.gz, data compression gz
# vk_layer_lurk-1.0.0-x86_64.pkg.tar.zst: Zstandard compressed data (v0.8+), Dictionary ID: None
# vk_layer_lurk-1.0.0-x86_64.rpm:         RPM v3.0 bin i386/x86_64
# vk_layer_lurk-1.0.0-x86_64.tar.gz:      gzip compressed data, from Unix, original size modulo 2^32 1003520
# vk_layer_lurk-1.0.0-x86.deb:            Debian binary package (format 2.0), with control.tar.gz, data compression gz
# vk_layer_lurk-1.0.0-x86.pkg.tar.zst:    Zstandard compressed data (v0.8+), Dictionary ID: None
# vk_layer_lurk-1.0.0-x86.rpm:            RPM v3.0 bin noarch
# vk_layer_lurk-1.0.0-x86.tar.gz:         gzip compressed data, from Unix, original size modulo 2^32 1218560
