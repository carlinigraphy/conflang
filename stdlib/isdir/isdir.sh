#!/bin/bash

function isdir-test {
   [[ -d "$DATA" ]]
}

function isdir-directive {
   mkdir -p "$DATA"
}
