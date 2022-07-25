#!/bin/bash

declare -ga EXIT_STATUS=(
   [parse_error]=1
   [type_error]=2
)

function raise {
   local type="$1" ; shift
   raise_${type} "$@"
   exit ${EXIT_STATUS[type]}
}

function raise_parse_error { :; }

function raise_type_error {
   local -- wants_type="$1"
   local -- got_type="$2"
}
