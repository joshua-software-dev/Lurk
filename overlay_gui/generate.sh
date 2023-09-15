#!/bin/bash

zig translate-c -lc "cimgui_zig.h" > "src/cimgui.zig"
