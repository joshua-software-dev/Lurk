#!/bin/bash

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
cd "$SCRIPTPATH"

rm -rf cli_tool_lurk/zig-cache/ cli_tool_lurk/zig-out/
rm -rf discord_ws_conn/zig-cache/ discord_ws_conn/zig-out/
rm -rf vk_layer_lurk/zig-cache/ vk_layer_lurk/zig-out/
