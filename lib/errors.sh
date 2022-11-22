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


declare -gA ERROR_CODE=(
   # I/O errors
   [argument_error]='10,Argument Error'
   [no_input]='11,File Error'
   [missing_file]='12,File Error'
   [missing_constraint]='13,File Error'
   [circular_import]='14,File Error'

   # Syntax errors
   [syntax_error]='15,Syntax Error'
   [invalid_interpolation_char]='16,Syntax Error'
   [unescaped_interpolation_brace]='17,Syntax Error'

   # Parse errors
   [parse_error]='18,Parse Error'
   [munch_error]='19,Parse Error'

   # Type errors
   [type_error]='20,Type Error'
   [undefined_type]='21,Type Error'
   [not_a_type]='22,Type Error'
   [symbol_mismatch]='23,Type Error'

   # Key errors
   [index_error]='24,Name Error'
   [name_collision]='25,Name Error'
   [missing_env_var]='26,Name Error'
   [missing_var]='27,Name Error'
   [missing_required]='28,Name Error'

   # Misc. errors
   [idiot_programmer]='255,Idiot Programmer Error'
)


declare -g  ERROR=''
declare -gi ERROR_NUM=0

function error:new {
   (( ++ERROR_NUM ))
   local err="ERROR_${ERROR_NUM}"
   declare -gA "$err"
   declare -g  ERROR="$err"

   # Without a value, this isn't glob matched by a ${!_LOC_*}
   local -n e="$err" ; e=()
}


function raise {
   local type="$1" ; shift

   local anchor  caught
   local -a args

   while (( $# )) ; do
      case "$1" in
         --anchor)   shift ; anchor="$1" ; shift  ;;
         --caught)   shift ; caught="$1" ; shift  ;;
         *)          args+=( "$1" )      ; shift  ;;
      esac
   done

   if [[ ! "${ERROR_CODE[$type]}" ]] ; then
      printf 'Idiot Programmer Error(255):\n'
      printf '   no such error [%s].\n'  "$type"
      exit 1
   fi

   local code="${ERROR_CODE[$type]%%,*}"
   local category="${ERROR_CODE[$type]##*,}"

   error:new
   local -n error_r="$ERROR"
   error_r[category]="$category"
   error_r[code]="e${code}"

   if [[ $anchor && $caught ]] ; then
      build_error_location  "$anchor"  "$caught"
   fi

   _"${type}"  "${args[@]}"

   error:print  "$ERROR"
   exit "$code"
}


# build_error_location()
#
# @description
#  Compiles the start line/column of the anchor & caught positions into a single
#  ERROR{} object.
#
# @arg $1 LOCATION  Node for the `start_ln` and `start_col`
# @arg $2 LOCATION  Node for the `end_ln` and `end_col`
function build_error_location {
   local -n anchor_r="$1"
   local -n caught_r="$2"
   local -n error_r="$ERROR"

   error_r[anchor_file_name]="${FILES[${anchor_r[file]}]}"
   error_r[anchor_file_lines]="FILE_${anchor_r[file]}_LINES"
   error_r[anchor_ln]="${anchor_r[start_ln]}"
   error_r[anchor_col]="${anchor_r[start_col]}"

   error_r[caught_file_name]="${FILES[${caught_r[file]}]}"
   error_r[caught_file_lines]="FILE_${caught_r[file]}_LINES"
   error_r[caught_ln]="${caught_r[start_ln]}"
   error_r[caught_col]="${caught_r[start_col]}"
}


#─────────────────────────────( printing errors )───────────────────────────────
function error:print {
   local -n e_r="$1"

   # Category, e.g., `Syntax Error(e17):`
   printf '%s(%s): '  "${e_r[category]}"  "${e_r[code]}"
   printf '%s\n'      "${e_r[msg]}"

   if [[ ! ${e_r[anchor_file_name]} ]] ; then
      return
   fi

   # Anchor file name.
   local file="${e_r[anchor_file_name]/$HOME/\~}"
   printf '%3sin %s\n'   ''  "$file"

   if [[ "${e_r[anchor_file_name]}" == "${e_r[caught_file_name]}" ]] ; then
      error:_single_file_context "$1"
   else
      error:_multi_file_context "$1"
   fi

   local filler='' ; local -i max
   (( max = ${e_r[caught_col]} + 1 ))
   for (( i=0; i<max ; ++i )) ; do
      filler+='-'
   done
   printf '%3scaught %s|\n'  ''  "$filler"
   printf '\n'
}


function error:_single_file_context {
   local -n e_r="$1"

   local filler='' ; local -i max
   (( max = ${e_r[anchor_col]} + 1 ))
   for (( i=0; i<max ; ++i )) ; do
      filler+='-'
   done

   printf '%3sanchor %s|\n'  ''  "$filler"

   # Print context lines.
   local -i start="${e_r[anchor_ln]}"
   local -i end="${e_r[caught_ln]}"
   local -n anchor_file_lines_r="${e_r[anchor_file_lines]}"

   for (( i=start; i <= end; ++i )) ; do
      printf '%3s%6s | %s\n'  ''   "$i"   "${anchor_file_lines_r[$i]}"
   done
}


function error:_multi_file_context {
   local -n e_r="$1"
}

#───────────────────────────────( I/O errors )──────────────────────────────────
function _no_input {
   local -n error_r="$ERROR"
   error_r[msg]='no input file'
}


function _missing_file {
   local -n error_r="$ERROR"
   error_r[msg]= "missing or unreadable source file [${1##*/}]"
}


function _missing_constraint {
   local -n error_r="$ERROR"
   error_r[msg]="no %constrain file exists"
}


function _circular_import {
   local -n error_r="$ERROR"
   error_r[msg]="cannot source [${1##*/}], circular import"
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
   error_r[msg]="expected [${1}], received [${2}], $3"
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
