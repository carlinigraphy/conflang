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
   [munch_error]=13
)

function raise {
   local type="$1" ; shift
   print_"${type}" "$@" 1>&2

   #ifs="$IFS" ; IFS=$'\n'
   #for i in "${BASH_SOURCE[@]}" ; do
   #   local -a "FPARTS_${i}"=(
   #      $()
   #   )
   #done
   #IFS="$ifs"

   printf 'Traceback:\n'
   for (( i=${#FUNCNAME[@]}-1; i>=2 ; --i )) ; do
      printf '%5sln.%4d in %-25s%s\n' \
         ''                           \
         "${BASH_LINENO[i-1]}"        \
         "${FUNCNAME[i]}"             \
         "${BASH_SOURCE[i]}"
   done

   exit "${EXIT_STATUS[$type]}"
}

#───────────────────────────────( I/O errors )──────────────────────────────────
function print_no_input {
   printf 'File Error: missing input file.'
}

function print_missing_file {
   printf 'File Error: missing source file %s.'  "$1"
}

function print_circular_import {
   printf 'Import Error: cannot source %q, circular import.'  "$1"
}

#──────────────────────────────( syntax errors )────────────────────────────────
function print_syntax_error {
   local -n node="$1"
   printf 'Syntax Error: [%d:%d] %q.' \
      "${node[lineno]}" \
      "${node[colno]}"  \
      "${node[value]}"
}

function print_invalid_interpolation_char {
   printf 'Syntax Error: %q not valid in string interpolation.'  "$1"
}

#───────────────────────────────( parse errors )────────────────────────────────
function print_munch_error {
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

function print_parse_error {
   printf 'Parse Error: %s\n'  "$1"
}

function print_invalid_type_error {
   printf 'Type Error: %q not defined.'  "$1"
}

function print_type_error { :; }

#────────────────────────────────( key errors )─────────────────────────────────
function print_index_error {
   printf 'Index Error: %q not found.'  "$1"
}

function print_name_error {
   printf 'Name Error: %q already defined in this scope.'  "$1"
}

function print_missing_env_var {
   printf 'Name Error: env variable %q is not defined.'  "$1"
}

function print_stomped_env_var {
   printf 'Name Error: env variable %q stomped by program variable.'  "$1"
}
