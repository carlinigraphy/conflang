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
   [missing_env_var]=10
   [stomped_env_var]=11
   [invalid_interpolation_char]=12
)

function raise {
   local type="$1" ; shift
   print_"${type}" "$@" 1>&2

   printf 'Traceback:\n'
   for (( i=${#FUNCNAME[@]}-1; i>=2 ; --i )) ; do
      printf '%5sln.%4d in %-25s%s\n' \
         ''                          \
         "${BASH_LINENO[i-1]}"       \
         "${FUNCNAME[i]}"            \
         "${BASH_SOURCE[i]}"
   done

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

function print_invalid_interpolation_char {
   echo "Syntax Error: ${1@Q} not valid in string interpolation."
}

function print_parse_error {
   local -- expect="$1"
   local -n got="$2"
   local -- msg="$3"

   printf 'Parse Error: [%s:%s] expected %s, received %s. %s\n' \
      "${got[lineno]}"  \
      "${got[colno]}"   \
      "${1,,}"          \
      "${got[type],,}"  \
      "${msg^}"
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

function print_missing_env_var {
   echo "Name Error: env variable ${1@Q} is not defined."
}

function print_stomped_env_var {
   echo "Name Error: env variable ${1@Q} stomped by program variable."
}
