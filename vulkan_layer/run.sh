#!/bin/bash

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
cd "$SCRIPTPATH"

printf "zig\n" && \
env \
    ENABLE_LURK=1 \
    VK_ADD_LAYER_PATH="$(realpath ./manifests/debug)" \
    VK_LOADER_LAYERS_ENABLE="VK_LAYER_Lurk_*" \
    VK_LOADER_DEBUG=all \
    vkcube
