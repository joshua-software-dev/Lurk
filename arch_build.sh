#!/bin/bash

optimize="Debug"
if [ "$1" = "fast" ]; then optimize="ReleaseFast";
elif [ "$1" = "safe" ]; then optimize="ReleaseSafe";
elif [ "$1" = "small" ]; then optimize="ReleaseSmall";
fi

ver=$(grep ".version" build.zig.zon | awk -F '"' '{print $2}')

rm -rf zig-out/
printf "zig build -Dcpu=baseline -Dtarget=x86_64-linux-gnu -Doptimize=$optimize\n"
zig build -Dcpu=baseline -Dtarget=x86_64-linux-gnu -Doptimize=$optimize
fpm -f -t pacman -a x86_64 -p "lurk_overlay-$ver-x86_64.pkg.tar.zst" --version "$ver" lib=/usr/ bin=/usr/

rm -rf zig-out/
printf "zig build -Dcpu=baseline -Dtarget=x86-linux-gnu -Doptimize=$optimize\n"
zig build -Dcpu=baseline -Dtarget=x86-linux-gnu -Doptimize=$optimize -Dbuild_cli=false
rm -rf zig-out/bin/
rm -rf zig-out/share/licenses
fpm -f -t pacman -a x86_64 -p "lurk_overlay-$ver-x86.pkg.tar.zst"    --version "$ver" --name lib32-lurk_overlay lib32=/usr/
