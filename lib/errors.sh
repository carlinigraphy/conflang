#!/bin/bash

#trap 'traceback 2' ERR EXIT
function traceback {
   local -i depth="$1"
   (( depth = (depth < 1 ? 1 : depth) ))

   printf 'Traceback:\n'
   for (( i=${#FUNCNAME[@]}-1; i>="$depth" ; --i )) ; do
      printf '%5sln.%4d in %-25s%s\n' \
         ''                           \
         "${BASH_LINENO[i-1]}"        \
         "${FUNCNAME[i]}"             \
         "${BASH_SOURCE[i]##*/}"
   done
}


declare -gA EXIT_STATUS=(
   [no_input]=1
   [syntax_error]=2
   [parse_error]=3
   [type_error]=4
   [invalid_type_error]=5
   [not_a_type]=6
   [symbol_mismatch]=7
   [index_error]=8
   [circular_import]=9
   [name_error]=10
   [missing_file]=11
   [missing_constraint]=12
   [source_failure]=13
   [missing_env_var]=14
   [missing_int_var]=15
   [invalid_interpolation_char]=16
   [unescaped_interpolation_brace]=17
   [munch_error]=18
   [missing_required]=19
)

function raise {
   local type="$1" ; shift
   print_"${type}" "$@" 1>&2
   exit "${EXIT_STATUS[$type]}"
}

#────────────────────────────( find expr location )─────────────────────────────
# When receiving an expression, we may not directly have a node with a .lineno
# and .colno properties. Example: typecast nodes, or nested expressions. Must
# walk to provide the "root" of the expression.

declare -ga LOC

function walk_location {
   declare -g LOC="$1"
   location_${TYPEOF[$LOC]}
}


function location_typedef {
   local -n node="$LOC"
   walk_location "${node[kind]}"
}


function location_typecast {
   local -n node="$LOC"
   walk_location "${node[expr]}"
}


function semantics_unary {
   local -n node="$LOC"
   walk_location "${node[right]}"
}

# Non-complex nodes, no ability to descend further. Stop here.
function location_path       { :; }
function location_boolean    { :; }
function location_integer    { :; }
function location_string     { :; }
function location_identifier { :; }


#───────────────────────────────( I/O errors )──────────────────────────────────
function print_no_input {
   printf 'File Error: missing input file.\n'
}

function print_missing_file {
   printf 'File Error: missing or unreadable source file %s.\n'  "$1"
}

function print_missing_constraint {
   printf 'File Error: no file matches %%constrain list.\n'
}

function print_circular_import {
   printf 'Import Error: cannot source %s, circular import.\n'  "$1"
}

function print_source_failure {
   printf 'File Error: failed to source user-defined function %s.\n'  "$1"
}

#──────────────────────────────( syntax errors )────────────────────────────────
function print_syntax_error {
   local -n node="$1"
   local -- msg="$2"

   printf "Syntax Error: [%d:%d] \`%s'\n" \
      "${node[lineno]}" \
      "${node[colno]}"  \
      "${node[value]}"
}

function print_invalid_interpolation_char {
   printf "Syntax Error: \`%s' not valid in string interpolation.\n"  "$1"
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

function print_not_a_type {
   printf 'Type Error: %s is not a type.\n'  "$1"
}

function print_type_error {
   local -- _loc="$1"
   local -- msg="$2"

   walk_location "$_loc"
   local -n loc="$LOC"

   printf 'Type Error: [%s:%s] invalid type.%s\n' \
      "${loc[lineno]}" \
      "${loc[colno]}"  \
      "${msg:+ ${msg^}}"
      # Passing in a message is not required. If supplied, capitalize the first
      # word and prefix with a leading space.
}

function print_symbol_mismatch {
   local fq_name=''
   for part in "${FQ_LOCATION[@]}" ; do
      fq_name+="${fq_name:+.}${part}"
   done

   printf "Type Error: child key \`${fq_name}' does not match parent's type.\n"
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

function print_missing_int_var {
   printf "Name Error: internal variable \`%s' is not defined.\n"  "$1"
}

function print_missing_required {
   local fq_name=''
   for part in "${FQ_LOCATION[@]}" ; do
      fq_name+="${fq_name:+.}${part}"
   done

   printf "Key Error: \`${fq_name}' required in parent, missing in child.\n"
}
