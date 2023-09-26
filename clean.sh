#!/bin/bash

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
cd "$SCRIPTPATH"

declare -a projects=("cli" "discord_ws_conn" "opengl_layer" "overlay_gui" "vulkan_layer" "vulkan_layer/..")

for dir in "${projects[@]}"
do
    rm -rf "$dir/zig-cache"
    rm -rf "$dir/zig-out"
done

rm -rf lurk_overlay-*.zst
rm -f overlay_gui/src/*.ttf
rm -f overlay_gui/src/*.otf
rm -f overlay_gui/src/*.woff
rm -f overlay_gui/src/*.woff2
