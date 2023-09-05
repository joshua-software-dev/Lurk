#!/bin/bash

[ -z "$1" ] && optimize="ReleaseSmall" || optimize="Debug"

ver=$(grep ".version" build.zig.zon | awk -F '"' '{print $2}')

rm -rf zig-out/
printf "zig build -Dcpu=baseline -Dtarget=x86_64-linux-gnu -Doptimize=$optimize\n"
zig build -Dcpu=baseline -Dtarget=x86_64-linux-gnu -Doptimize=$optimize
fpm -f -t pacman -a x86_64 -p "vk_layer_lurk-$ver-x86_64.pkg.tar.zst" --version "$ver" lib=/usr/

rm -rf zig-out/
printf "zig build -Dcpu=baseline -Dtarget=x86-linux-gnu -Doptimize=$optimize\n"
zig build -Dcpu=baseline -Dtarget=x86-linux-gnu -Doptimize=$optimize
rm -rf zig-out/share/licenses
fpm -f -t pacman -a x86_64 -p "vk_layer_lurk-$ver-x86.pkg.tar.zst"    --version "$ver" --name lib32-vk_layer_lurk lib32=/usr/
