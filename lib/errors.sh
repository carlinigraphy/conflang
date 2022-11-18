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
   local origin  caught
   local -a args

   while (( $# )) ; do
      case "$1" in
         --origin)   shift ; origin="$1" ; shift  ;;
         --caught)   shift ; caught="$1" ; shift  ;;
         *)          args+=( "$1" )      ; shift  ;;
      esac
   done

   status="${EXIT_STATUS[$type]}"
   if [[ ! $status ]] ; then
      status=255
      type='idiot_programmer'
      args=( "no such error $type" )
   fi

   collect_error_info  "$origin"  "$caught"

   print_"${type}"  "$status"  "${args[@]}" 1>&2
   exit "$status"
}


# TODO: more thinkies :: the `origin` realistically is only useful in cases
# where the error began in a different file. Might want to change the
# terminology here. We're already passing in a start/end position with a
# single LOCATION node. Passing in a second would only be a case in which the
# start position cannot come from the same node. Kinda just in semantic
# analysis.
#
# Need to come up with better terms to more clearly express things. When type
# checking, there may be a distance between the type declaration, and the
# expression. Potentially spanning files. Though errors can occur within
# variable/section declarations themselves, so it doesn't make a lot of sense
# to use a `--expression` and `--declaration` flag. Maybe `--error-loc` and
# `--context`?
#
# Turns out naming things is hard.
#
# An inability to succinctly name this is kinda indicativve of not having a
# great understanding of this.
#
#

declare -A ERRORS=()
declare -a FILE_CTX=()        # Context in which the error occurred.
declare -a DECL_CTX=()        # If declaration occured outside of the file ctx.

# @arg $1 (LOCATION) Origin location
# @arg $2 (LOCATION) Caught location
function collect_error_info {
   [[ "$1" ]] && _collect_error_info  "$1"  'origin'
   [[ "$2" ]] && _collect_error_info  "$2"  'caught'
}

function _collect_error_info {
   local loc="$1"
   local prefix="$2"
   local -n loc_r="$loc"


}


function print_idiot_programmer {
   shift 2  # No location information, ignore origin/caught
   printf 'Idiot Programmer Error: %s'  "$1"
}

#───────────────────────────────( I/O errors )──────────────────────────────────
function print_no_input {
   printf 'File Error(%s): missing input.\n'  "$1"
}


function print_missing_file {
   local status="$1"
   shift 2  # No location information, ignore origin/caught

   printf 'File Error(%s): '  "$status"
   printf 'missing or unreadable source file %s.\n'  "$1"
}


function print_missing_constraint {
   printf 'File Error(%s): no file matches %%constrain list.\n'  "$1"
}


function print_circular_import {
   local status="$1"
   shift 2  # No location information, ignore origin/caught

   printf 'Import Error(%s): '  "$status"
   printf 'cannot source %s, circular import.\n'  "$1"
}


# TODO: need way more information than "failed to source". Did it not exist,
# was it not valid bash, etc.
function print_source_failure {
   local status="$1"
   shift 2  # No location information, ignore origin/caught

   printf 'File Error(%s):'  "$status"
   printf 'failed to source user-defined function %s.\n'  "$1"
}

#──────────────────────────────( syntax errors )────────────────────────────────
function print_syntax_error {
   local status="$1"  origin="$2"  caught="$3"

   local -n node="$4"
   local msg="$5"

   printf "Syntax Error: [%d:%d] \`%s'\n" \
      "${node[lineno]}" \
      "${node[colno]}"  \
      "${node[value]}"
}


# TODO: oof, definitely need to wrap a bunch of these in helper functions.
#       There's a lot of boilerplate here. Don't know how much I can abstract
#       away though. Need to reduce the number of edge cases. Gotta treat multi
#       line, multi file, and single character errors all have the same output.
#       Multi-file probably can't. It has a different output format. Pretty sure
#       only the symtab & typechecking phases can have errors occuring across
#       files.
#
#       Formatting the header should be fairly universal. If they can all be
#       consolidated to a format string and a single argument, it can be built
#       separately. Largely to move the $status and $args out of the print_
#       functions below.
#
#       Globally declaring an ERROR{} associative array, and passing in the
#       --origin and --caught LOCATION nodes can flatten those out, and remove
#       the need for all the namerefs. Pretty much make a:
#       ERRORS: {
#           origin_file_name;
#           origin_start_col;
#           origin_start_ln;
#           origin_end_col;
#           origin_end_ln;
#           caught_file_name;
#           caught_start_col;
#           caught_start_ln;
#           caught_end_col;
#           caught_end_ln;
#       }
#
#       Then the file lines themselves can be thrown into two arrays:
#       ORIGIN_LINES and CAUGHT_LINES, based upon the start/end lines of their
#       respective locations. The array indices will be the matching line
#       numbers from the file. Arrays don't need to have elements that start
#       from `0`.
#
#       Can pull lines with something like the following.
#       > ORIGIN_LINES=${FILE_LINES[@]:$startln:$startln-$endln}
#
#       If the origin and caught files are the same, need to make a choice as
#       to which to consistently use.
#
# @arg $1 (int)       Error code
# @arg $4 (str)       The invalid character
function print_invalid_interpolation_char {
   local status="$1"
   local character="$2"

   local -i file_idx="${caught_r[file]}"
   local file="${FILES[$file_idx]}"

   local -n file_lines_r="FILE_${file_idx}_LINES"
   local -i lineno="${caught_r[start_ln]}"
   local line="${file_lines_r[$lineno -1]}"

   local -i start_col="${caught_r[start_col]}"
   local -i end_col="${caught_r[end_col]}"

   printf 'Syntax Error(%s): '  "$status"
   printf "\`%s' not valid in string interpolation.\n"  "$character"

   local -i offset=3

   local filler=''
   for (( i=(end_col + 1); i>0; --i )) ; do
      filler+='-'
   done

   printf '   in %s\n'   "$file"
   printf "%${offset}s"   ''
   printf 'origin %s.\n'  "$filler"
   printf '   %6s | %s'  "$lineno"  "$line"

   local filler=''
   for (( i=(end_col + 1); i>0; --i )) ; do
      filler+='-'
   done

   printf "%${offset}s"   ''
   printf 'caught %s^\n'  "$filler"
}

function print_unescaped_interpolation_brace {
   local origin="$1" ; shift
   local caught="$1" ; shift

   printf "Syntax Error: single \`}' not allowed in f-string.\n"
}

#───────────────────────────────( parse errors )────────────────────────────────
function print_parse_error {
   local origin="$1" ; shift
   local caught="$1" ; shift

   printf 'Parse Error: %s\n'  "$1"
}

function print_munch_error {
   local origin="$1" ; shift
   local caught="$1" ; shift

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
   local origin="$1" ; shift
   local caught="$1" ; shift

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
   local origin="$1" ; shift
   local caught="$1" ; shift

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
   local origin="$1" ; shift
   local caught="$1" ; shift

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
   local origin="$1" ; shift
   local caught="$1" ; shift

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
   local origin="$1" ; shift
   local caught="$1" ; shift

   printf "Index Error: \`%s' not found.\n"  "$1"
}


function print_name_collision {
   local origin="$1" ; shift
   local caught="$1" ; shift

   printf "Name Error: \`%s' already defined in this scope.\n"  "$1"
}


function print_missing_env_var {
   local origin="$1" ; shift
   local caught="$1" ; shift

   printf "Name Error: env variable \`%s' is not defined.\n"  "$1"
}


function print_missing_var {
   local origin="$1" ; shift
   local caught="$1" ; shift

   printf "Name Error: variable \`%s' is not defined.\n"  "$1"
}


function print_missing_required {
   local origin="$1" ; shift
   local caught="$1" ; shift

   local fq_name=''
   for part in "${FQ_LOCATION[@]}" ; do
      fq_name+="${fq_name:+.}${part}"
   done

   printf "Key Error: \`${fq_name}' required in parent, missing in child.\n"
}

#───────────────────────────────( misc. errors)───────────────────────────────
function print_invalid_positional_arguments {
   local origin="$1" ; shift
   local caught="$1" ; shift

   local arguments=( "$@" )
   local arguments=( "${arguments[@]:1:${#arguments[@]}-1}" )

   printf 'Argument Error: Invalid positional arguments '
   printf '[%s]'  "${arguments[@]}"
   printf '\n'
}


function print_argument_order_error {
   local origin="$1" ; shift
   local caught="$1" ; shift

   local argument="$1"
   local message="$2"

   printf "Argument Error: \`%s', %s"  "${argument}"  "${message,}"
}
