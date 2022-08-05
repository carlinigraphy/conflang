#!/bin/bash

declare -gA EXIT_STATUS=(
   [no_input]=1
   [syntax_error]=2
   [parse_error]=3
   [type_error]=4
   [index_error]=5
   [circular_import]=6
   [name_error]=7
   [invalid_type_error]=8
   [missing_file]=9
)

function raise {
   local type="$1" ; shift
   print_"${type}" "$@" 1>&2

   exit "${EXIT_STATUS[$type]}"
}

function print_no_input {
   echo "File Error: missing input file."
}

function print_missing_file {
   echo "File Error: missing source file ${1@Q}."
}

function print_syntax_error {
   local -n node="$1"
   echo "Syntax Error: [${node[lineno]}:${node[colno]}] ${node[value]@Q}."
}

function print_parse_error {
   echo "Parse Error: ${1}"
}

function print_type_error { :; }

function print_index_error {
   echo "Index Error: ${1@Q} not found."
}

function print_circular_import {
   echo "Import Error: cannot source ${1@Q}, circular import." 
}

function print_name_error {
   echo "Name Error: ${1@Q} already defined in this scope."
}

function print_invalid_type_error {
   echo "Type Error: ${1@Q} not defined."
}
