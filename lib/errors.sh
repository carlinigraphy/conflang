#!/bin/bash

#trap 'traceback $?' ERR EXIT
#function traceback {
#   printf 'Traceback:\n'
#   for (( i=${#FUNCNAME[@]}-1; i>=0 ; --i )) ; do
#      printf '%5sln.%4d in %-25s%s\n' \
#         ''                           \
#         "${BASH_LINENO[i-1]}"        \
#         "${FUNCNAME[i]}"             \
#         "${BASH_SOURCE[i]}"
#   done
#   exit "$1"
#}


# TODO:
# Exit statuses should be unique. BATS test to `sort | uniq` keys, compare len.
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
   [missing_int_var]=12
   [invalid_interpolation_char]=13
   [unescaped_interpolation_brace]=14
   [munch_error]=145
)

function raise {
   local type="$1" ; shift
   print_"${type}" "$@" 1>&2

   #printf 'Traceback:\n'
   #for (( i=${#FUNCNAME[@]}-1; i>=2 ; --i )) ; do
   #   printf '%5sln.%4d in %-25s%s\n' \
   #      ''                           \
   #      "${BASH_LINENO[i-1]}"        \
   #      "${FUNCNAME[i]}"             \
   #      "${BASH_SOURCE[i]}"
   #done

   exit "${EXIT_STATUS[$type]}"
}

#───────────────────────────────( I/O errors )──────────────────────────────────
function print_no_input {
   printf 'File Error: missing input file.\n'
}

function print_missing_file {
   printf 'File Error: missing source file %s.\n'  "$1"
}

function print_circular_import {
   printf 'Import Error: cannot source %q, circular import.\n'  "$1"
}

#──────────────────────────────( syntax errors )────────────────────────────────
function print_syntax_error {
   local -n node="$1"
   local -- msg="$2"

   printf 'Syntax Error: [%d:%d] %q\n' \
      "${node[lineno]}" \
      "${node[colno]}"  \
      "${node[value]}"
}

function print_invalid_interpolation_char {
   printf 'Syntax Error: %q not valid in string interpolation.\n'  "$1"
}

function print_unescaped_interpolation_brace {
   printf "Syntax Error: single \`}' not allowed in f-string.\n"
}

#───────────────────────────────( parse errors )────────────────────────────────
function print_munch_error {
   local -- expect="$1"
   local -n got="$2"
   local -- msg="$3"

   printf 'Parse Error: [%s:%s] expected %s, received %s. %s\n' \
      "${got[lineno]}"  \
      "${got[colno]}"   \
      "${expect,,}"     \
      "${got[type],,}"  \
      "${msg^}"
}

function print_parse_error {
   printf 'Parse Error: %s\n'  "$1"
}

function print_invalid_type_error {
   printf 'Type Error: %s not defined.\n'  "$1"
}

function print_type_error {
   declare -n node="$1"
   declare -- msg="$2"

   printf 'Type Error: [%s:%s] invalid type.%s\n' \
      "${node[lineno]}" \
      "${node[colno]}"  \
      "${msg:+ ${msg^}}"
      # Passing in a message is not required. If supplied, capitalize the first
      # word and prefix with a leading space.
}

#────────────────────────────────( key errors )─────────────────────────────────
function print_index_error {
   printf "Index Error: \`%s' not found.\n"  "$1"
}

function print_name_error {
   printf "Name Error: \`%s' already defined in this scope.\n"  "$1"
}

function print_missing_env_var {
   printf "Name Error: env variable \`%s' is not defined.\n"  "$1"
}

function print_stomped_env_var {
   printf "Name Error: env variable \`%s' stomped by program variable.\n"  "$1"
}

function print_missing_int_var {
   printf "Name Error: internal variable \`%s' is not defined.\n"  "$1"
}
