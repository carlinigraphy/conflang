#!/bin/bash

function traceback {
   local -i depth="$1"
   local -i len=${#FUNCNAME[@]}-1

   (( depth = (depth < 1) ? 1 : depth ))

   printf 'Traceback:\n'
   for (( i=len; i>=depth; --i )) ; do
      printf '%5sln.%4d in %-28s%s\n'  \
         ''                            \
         "${BASH_LINENO[$i-1]}"        \
         "${FUNCNAME[$i]}"             \
         "${BASH_SOURCE[$i]##*/}"
   done
}


declare -gA EXIT_STATUS=(
   # I/O errors
   [no_input]=1
   [missing_file]=2
   [missing_constraint]=3
   [circular_import]=4
   [source_failure]=5

   # Syntax errors
   [syntax_error]=6
   [invalid_interpolation_char]=7
   [unescaped_interpolation_brace]=8

   # Parse errors
   [parse_error]=9
   [munch_error]=10

   # Type errors
   [type_error]=11
   [undefined_type]=12
   [not_a_type]=13
   [symbol_mismatch]=14

   # Key errors
   [index_error]=15
   [name_collision]=16
   [missing_env_var]=17
   [missing_var]=18
   [missing_required]=19

   # Misc. errors
   [invalid_positional_arguments]=20
   [idiot_programmer]=255
)


function raise {
   local type="$1" ; shift

   # Many errors will not require both a start & end location, however this
   # makes it available as an option.
   local start_loc_node  end_loc_node
   local -a args

   while (( $# )) ; do
      case "$1" in
         --start)    shift ; start_loc_node="$1" ;;
         --end)      shift ; end_loc_node="$1"   ;;
         *)          args+=( "$1" ) ; shift      ;;
      esac
   done

   status="${EXIT_STATUS[$type]}"
   if [[ ! $status ]] ; then
      status=255
      type='idiot_programmer'
      args=( "no such error $type" )
   fi

   print_"${type}" "${args[@]}" 1>&2
   exit "$status"
}

function print_idiot_programmer {
   printf 'Idiot Programmer Error: %s'  "$1"
}


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
function print_parse_error {
   printf 'Parse Error: %s\n'  "$1"
}

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


#───────────────────────────────( type errors )─────────────────────────────────
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

function print_undefined_type {
   local -- loc="$1"
   local -- msg="$2"

   walk_location "$loc"
   local -n loc_r="$LOC"

   printf 'Type Error: [%s:%s] %s not defined.\n' \
         "${loc_r[lineno]}" \
         "${loc_r[colno]}"  \
         "$1"
}

function print_not_a_type {
   local -- loc="$1"
   local -- msg="$2"

   walk_location "$loc"
   local -n loc_r="$LOC"

   printf 'Type Error: [%s:%s] %s is not a type.\n' \
         "${loc_r[lineno]}" \
         "${loc_r[colno]}"  \
         "$msg"
}

function print_symbol_mismatch {
   #local fq_name=''
   #for part in "${FQ_LOCATION[@]}" ; do
   #   fq_name+="${fq_name:+.}${part}"
   #done
   #
   #printf "Type Error: child key \`${fq_name}' does not match parent's type.\n"

   # TODO: error reporting
   # Part of the large error reporting overhaul, need to add more useful cursor
   # markers on every object before I can print helpful locations & error
   # messaging.
   printf "Type Error: child key doesn't match parent's type.\n"
}

#────────────────────────────────( key errors )─────────────────────────────────
function print_index_error {
   printf "Index Error: \`%s' not found.\n"  "$1"
}

function print_name_collision {
   printf "Name Error: \`%s' already defined in this scope.\n"  "$1"
}

function print_missing_env_var {
   printf "Name Error: env variable \`%s' is not defined.\n"  "$1"
}

function print_missing_var {
   printf "Name Error: variable \`%s' is not defined.\n"  "$1"
}

function print_missing_required {
   local fq_name=''
   for part in "${FQ_LOCATION[@]}" ; do
      fq_name+="${fq_name:+.}${part}"
   done

   printf "Key Error: \`${fq_name}' required in parent, missing in child.\n"
}

#───────────────────────────────( misc. errors)───────────────────────────────
function print_invalid_positional_arguments {
   local arguments=( "$@" )
   local arguments=( "${arguments[@]:1:${#arguments[@]}-1}" )

   printf 'Argument Error: Invalid positional arguments '
   printf '[%s]'  "${arguments[@]}"
   printf '\n'
}


function print_argument_order_error {
   local argument="$1"
   local message="$2"

   printf "Argument Error: \`%s', %s"  "${argument}"  "${message,}"
}
