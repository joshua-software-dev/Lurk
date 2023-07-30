#!/bin/bash

printf "zig build -Dcpu=baseline -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSmall\n"
zig build -Dcpu=baseline -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSmall
