#!/bin/bash

declare -ga EXIT_STATUS=(
   [no_input]=1
   [syntax_error]=2
   [parse_error]=3
   [type_error]=4
   [index_error]=5
   [circular_import]=6
)

function raise {
   local type="$1" ; shift
   print_${type} "$@"
   exit ${EXIT_STATUS[type]}
}

function print_no_input {
   echo "Input Error: missing input file." 1>&2
}

function print_syntax_error {
   local -n node="$1"
   echo "Syntax Error: [${node[lineno]}:${line[colno]}] \`${node[value]}." 1>&2
}

function print_parse_error {
   echo "Parse Error: ${1}" 1>&2
}

function print_type_error {
   local wants_type="$1"
   local got_type="$2"
}

function print_index_error {
   local index="$arg"
   echo "Key Error: \`$arg' not found." 1>&2
}

function print_circular_import {
   echo "Import Error: cannot source $1, circular import." 
}
