#!/bin/bash
odin build . -extra-linker-flags:"-lmd4c-html" -debug -out:soma

if [ $? -eq 0 ]; then
    cp soma ~/.local/bin/soma
fi
