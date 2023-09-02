#!/bin/bash

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
cd "$SCRIPTPATH"

rm -rf "cli_tool_lurk/zig-cache/"
rm -rf "cli_tool_lurk/zig-out/"

rm -rf "discord_ws_conn/zig-cache/"
rm -rf "discord_ws_conn/zig-out/"

rm -rf "imgui_ui/zig-cache/"
rm -rf "imgui_ui/zig-out/"
rm -rf "imgui_ui/deps/"

rm -rf "vk_layer_lurk/zig-cache/"
rm -rf "vk_layer_lurk/zig-out/"
