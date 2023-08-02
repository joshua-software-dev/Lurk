#!/bin/bash

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
cd "$SCRIPTPATH"

printf "zig\n" && zig build && \
env \
    ENABLE_LURK=1 \
    VK_ADD_LAYER_PATH="$(realpath ./manifests)" \
    VK_LOADER_LAYERS_ENABLE="VK_LAYER_Lurk" \
    VK_LOADER_DEBUG=all \
    vkcube
