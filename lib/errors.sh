#!/bin/bash

# THINKIES: two approaches to printing errors. Can spit out everything as it is
# encountered. Set global flag to indicate that we hit an error, so don't eval
# the final result. Or collect things, report on everything at the end. I think
# the "collect & report" is a better strategy.
#
# For errors in the lexer, should log them as an error, but do not create a
# token. Will make parser have errors, but should be able to sync past them.
#
#


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


declare -gA ERROR_CODE=(
   # I/O errors
   [argument_error]='e10,Argument Error'
   [no_input]='e11,File Error'
   [missing_file]='e12,File Error'
   [missing_constraint]='e13,File Error'
   [circular_import]='e14,File Error'
   [source_failure]='e15,File Error'

   # Syntax errors
   [syntax_error]='e16,Syntax Error'
   [invalid_interpolation_char]='e17,Syntax Error'
   [unescaped_interpolation_brace]='e18,Syntax Error'

   # Parse errors
   [parse_error]='e19,Parse Error'
   [munch_error]='e20,Parse Error'

   # Type errors
   [type_error]='e21,Type Error'
   [undefined_type]='e22,Type Error'
   [not_a_type]='e23,Type Error'
   [symbol_mismatch]='e24,Type Error'

   # Key errors
   [index_error]='e25,Name Error'
   [name_collision]='e26,Name Error'
   [missing_env_var]='e27,Name Error'
   [missing_var]='e28,Name Error'
   [missing_required]='e29,Name Error'

   # Misc. errors
   [idiot_programmer]='e255,Idiot Programmer Error'
)


declare -g  ERROR=''
declare -ga ALL_ERRORS=()
declare -gi ERROR_NUM=0

function error:new {
   (( ++ERROR_NUM ))
   local err="ERROR_${ERROR_NUM}"
   declare -gA "$err"
   declare -g  ERROR="$err"

   ALL_ERRORS+=( "$err" )

   # Without a value, this isn't glob matched by a ${!_LOC_*}
   local -n e="$err" ; e=()
}


function raise {
   local type="$1" ; shift

   local kill  origin  caught
   local -a args

   while (( $# )) ; do
      case "$1" in
         --kill)     shift ; kill=true            ;;
         --origin)   shift ; origin="$1" ; shift  ;;
         --caught)   shift ; caught="$1" ; shift  ;;
         *)          args+=( "$1" )      ; shift  ;;
      esac
   done

   if [[ ! ($origin && $caught) ]] ; then
      printf 'Idiot Programmer Error(e255):\n'
      printf "   didn't pass \`--origin' or \`--caught' to \`raise()\`.\n"
      exit 1
   fi

   if [[ ! "${ERROR_CODE[$type]}" ]] ; then
      printf 'Idiot Programmer Error(e255):\n'
      printf '   no such error [%s].\n'  "$type"
      exit 1
   fi

   local code="${ERROR_CODE[$type]%%,*}"
   local category="${ERROR_CODE[$type]##*,}"

   build_error_info  "$category"  "$code"  "$origin"  "$caught"
   _"${type}"  "${args[@]}"  1>&2

   if [[ $kill ]] ; then
      error:print  "$ERROR"
      exit 1
   fi
}


# @arg $1 (str)       Category of error: File Error, Parse Error, etc.
# @arg $2 (str)       Code for this specific error
# @arg $2 (LOCATION)  Node for the `start_ln` and `start_col`
# @arg $3 (LOCATION)  Node for the `end_ln` and `end_col`
function build_error_info {
   local category="$1"
   local code="$2"
   local -n origin_r="$3"
   local -n caught_r="$4"

   error:new
   local -n error_r="$ERROR"
   error_r[category]="$category"
   error_r[code]="$code"

   error_r[origin_file_name]="${FILES[${origin[file]}]}"
   error_r[origin_file_lines]="FILE_${origin_r[file]}_LINES"
   error_r[origin_ln]="${origin_r[start_ln]}"
   error_r[origin_col]="${origin_r[start_col]}"

   error_r[caught_file_name]="${FILES[${caught[file]}]}"
   error_r[caught_file_lines]="FILE_${caught_r[file]}_LINES"
   error_r[caught_ln]="${caught_r[start_ln]}"
   error_r[caught_col]="${caught_r[start_col]}"
}


#─────────────────────────────( printing errors )───────────────────────────────
# TODO: allow for user-supplied format strings, print error output as they see
# fit. Provide a default CLI output and json. Maybe waayy down the line look
# into what's required for integrating into vim/nvim/IDEs. Actually show errors
# on the line themselves.

function error:print_all {
   for e in "${ALL_ERRORS[@]}" ; do
      error:print "$e"
   done
}

function error:print {
   local -n e_r="$1"

   # Category, e.g., `Syntax Error(e17):`
   printf '%s(%s): '  "${e_r[category]}"  "${e_r[code]}"
   printf '%s\n'      "${e_r[msg]}"

   # Originating file name.
   printf '%3sin %s\n'   ''   "${e_r[origin_file_name]}"

   if [[ "${e_r[origin_file_name]}" != "${e_r[caught_file_name]}" ]] ; then
      error:_multi_file_context "$1"
   else
      error:_single_file_context "$1"
   fi

   local filler=''
   for (( i=(end_col + 1); i>0; --i )) ; do
      filler+='-'
   done
   printf '%3scaught %s^\n'  ''  "$filler"
}


function error:_single_file_context {
   local -n e_r="$1"

   local filler=''
   for (( i=0; i <= ${e_r[origin_col]}; ++i )) ; do
      filler+='-'
   done

   printf "%${offset}s"  ''
   printf '%3sorigin %s.\n'  ''  "$filler"

   # Print context lines.
   local -i start="${e_r[origin_ln]}"
   local -i end="${e_r[caught_ln]}"
   local -n origin_file_lines_r="${e_r[origin_file_lines]}"
   for (( i=start; i <= end; ++i )) ; do
      printf '%3s%6s | %s\n'  ''   "$i"   "${origin_file_lines_r[$i]}"
   done
}


function error:_multi_file_context {
   local -n e_r="$1"
}

#───────────────────────────────( I/O errors )──────────────────────────────────
function _no_input {
   local -n error_r="$ERROR"
   error_r[msg]='missing input'
}


function _missing_file {
   local -n error_r="$ERROR"
   error_r[msg]= "missing or unreadable source file [${1}]"
}


function _missing_constraint {
   local -n error_r="$ERROR"
   error_r[msg]="no %constrain file exists"
}


function _circular_import {
   local -n error_r="$ERROR"
   error_r[msg]="cannot source [${1}], circular import"
}


# TODO: need way more information than "failed to source". Did it not exist,
# was it not valid bash, etc.
function _source_failure {
   local -n error_r="$ERROR"
   error_r[msg]"failed to source user-defined function [${1}]"
}

#──────────────────────────────( syntax errors )────────────────────────────────
function _syntax_error {
   local -n error_r="$ERROR"
   error_r[msg]="${1}"
}


function _invalid_interpolation_char {
   local -n error_r="$ERROR"
   error_r[msg]="${1}"
}

function _unescaped_interpolation_brace {
   local -n error_r="$ERROR"
   error_r[msg]="single \`}' not allowed in f-string."
}

#───────────────────────────────( parse errors )────────────────────────────────
function _parse_error {
   local -n error_r="$ERROR"
   error_r[msg]="${1}"
}

function _munch_error {
   local -n error_r="$ERROR"
   error_r[msg]="expected [${1}], received [${2}]"
}


#───────────────────────────────( type errors )─────────────────────────────────
function _type_error {
   local -n error_r="$ERROR"
   error_r[msg]="$1"
}

function _undefined_type {
   local -n error_r="$ERROR"
   error_r[msg]="[${1}] is not defined"
}

function _not_a_type {
   local -n error_r="$ERROR"
   error_r[msg]="[${1}] is not a type"
}

function _symbol_mismatch {
   local -n error_r="$ERROR"
   error_r[msg]="does not match parent's type"
}

#────────────────────────────────( key errors )─────────────────────────────────
function _index_error {
   local -n error_r="$ERROR"
   error_r[msg]="[${1}] not found"  
}

function _name_collision {
   local -n error_r="$ERROR"
   error_r[msg]="[${1}] already defined in this scope"  
}

function _missing_env_var {
   local -n error_r="$ERROR"
   error_r[msg]="env variable [${1}] is not defined"  
}

function _missing_var {
   local -n error_r="$ERROR"
   error_r[msg]="variable [${1}] is not defined"
}

function _missing_required {
   local -n error_r="$ERROR"
   error_r[msg]="[${1}] required in parent, missing in child"
}

#───────────────────────────────( misc. errors)───────────────────────────────
function _argument_error {
   local msg='invalid arguments: '
   for a in "$@" ; do
      msg+="[${a}]"
   done

   local -n error_r="$ERROR"
   error_r[msg]="$msg"
}

function _idiot_programmer {
   local -n error_r="$ERROR"
   error_r[msg]="$1"
}
