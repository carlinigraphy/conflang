#!/bin/bash

#===============================================================================
# @section                           Errors
#-------------------------------------------------------------------------------

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
   [circular_import]='13,File Error'

   # Syntax errors
   [syntax_error]='14,Syntax Error'
   [invalid_interpolation_char]='15,Syntax Error'
   [unescaped_interpolation_brace]='16,Syntax Error'

   # Parse errors
   [parse_error]='17,Parse Error'
   [munch_error]='18,Parse Error'

   # Type errors
   [type_error]='19,Type Error'
   [not_a_type]='20,Type Error'
   [symbol_mismatch]='21,Type Error'
   [too_many_subtypes]='22,Type Error'

   # Key errors
   [index_error]='23,Name Error'
   [name_collision]='24,Name Error'
   [missing_var]='25,Name Error'

   # Misc. errors
   [idiot_programmer]='255,Idiot Programmer Error'
)


# @set ERROR
# @noargs
function error:new {
   (( ++_ERROR_NUM ))
   local err="ERROR_${_ERROR_NUM}"
   declare -gA "$err"
   declare -g  ERROR="$err"

   # Without a value, this isn't glob matched by ${!_LOC_*} expansion.
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

   raise_"${type}"  "${args[@]}"

   error:print  "$ERROR"
   exit "$code"
}


# build_error_location()
#
# @description
#  Compiles the start line/column of the anchor & caught positions into a single
#  `ERROR{}` object.
#
# @set   ERROR
# @arg   $1    :LOCATION   Node for the `start_ln` and `start_col`
# @arg   $2    :LOCATION   Node for the `end_ln` and `end_col`
function build_error_location {
   local -n anchor_r="$1"
   local -n caught_r="$2"
   local -n error_r="$ERROR"

   local anchor_file_name="${anchor_r[file]}"
   local -n anchor_file_r="${FILES[$anchor_file_name]}"
   error_r['anchor_file_name']="$anchor_file_name"
   error_r['anchor_file_lines']="${anchor_file_r[lines]}"
   error_r['anchor_ln']="${anchor_r[start_ln]}"
   error_r['anchor_col']="${anchor_r[start_col]}"

   local caught_file_name="${caught_r[file]}"
   local -n caught_file_r="${FILES[$caught_file_name]}"
   error_r['caught_file_name']="$caught_file_name"
   error_r['caught_file_lines']="${caught_file_r[lines]}"
   error_r['caught_ln']="${caught_r[start_ln]}"
   error_r['caught_col']="${caught_r[start_col]}"
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
   local file="${e_r[anchor_file_name]/$PWD/\.}"
   local file="${file/$HOME/\~}"
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
   local -n lines_r="${e_r[anchor_file_lines]}"

   # TODO:
   # Don't include more than say... 4 total lines of context. The anchor line +1
   # below, and the caught line with 1 above. Probably easier to just do this
   # by concatenating two array slices.
   #
   # Only want if there's more than 5 lines of context.
   #
   # Seems like I can do....
   #
   #> printf '%s\n'   "${lines[@]:idx_0:2}"
   #> printf '...\n'
   #> printf '%s\n'   "${lines[@]: idx_1 - max:2}"
   #
   # Want something like...
   #
   # Type Error(e22): unterminated string
   #    in ./sample/main.conf
   #    anchor -----------|
   #         3 | _ (str): "Here's the start of a string
   #         4 |           here's more of the string
   #         ...
   #         8 |           Why is the string still here?
   #         9 |
   #    caught --|
   #
   #
   #> context=( "${lines_r[@]:start:${#lines_r[@]} -max}" )
   #>
   #> if (( ${#context[@]} > 4 )) ; then
   #>    local -i start0 end0
   #>    (( start0 = start +1 ))
   #>    (( end0   = end   -1 ))
   #>
   #>    numbers=( start  start0 )
   #>    printf '%3s%6s | %s\n'  ''  "${numbers[@]}"  "${context[@]:0:2}"  
   #>
   #>    printf '%8s...\n'      ''
   #>
   #>    numbers=( end  end0 )
   #>    printf '%3s%6s | %s\n'  ''  "${numbers[@]}"  "${context[@]: -2:2}"
   #> else
   #>    printf '%3s%6s | %s\n'  ''  "${lines_r[@]}"
   #> fi
   #
   #
   # Oof, turns out the above doesn't work. Thought I was being clever. But
   # you can't printf two arrays to iterate both of them in parallel. It does
   # them in sequence. Hmm.
   #
   #
   # MORE THINKING IS AFOOTS.
   #
   # AFEET?
   #
   # AFOOTIES.
   #
   #
   for (( i=start; i <= end; ++i )) ; do
      printf '%3s%6s | %s\n'  ''   "$i"   "${lines_r[$i]}"
   done
}


function error:_multi_file_context {
   local -n e_r="$1"

   local filler='' ; local -i max
   (( max = ${e_r[anchor_col]} + 1 ))
   for (( i=0; i<max ; ++i )) ; do
      filler+='-'
   done
   printf '%3sanchor %s|\n'  ''  "$filler"

   local -i anchor_idx="${e_r[anchor_ln]}"
   local -n anchor_file_lines_r="${e_r[anchor_file_lines]}"
   local anchor_line="${anchor_file_lines_r[$anchor_idx]}"
   printf '%3s%6s | %s\n'  ''   "$anchor_idx"   "$anchor_line"

   # Caught file name.
   local file="${e_r[caught_file_name]/$PWD/\.}"
   local file="${file/$HOME/\~}"
   printf '\n%3sin %s\n'   ''  "$file"

   local -i caught_idx="${e_r[caught_ln]}"
   local -n caught_file_lines_r="${e_r[caught_file_lines]}"
   local caught_line="${caught_file_lines_r[$caught_idx]}"
   printf '%3s%6s | %s\n'  ''   "$caught_idx"   "$caught_line"
}

#───────────────────────────────( I/O errors )──────────────────────────────────
function raise_no_input {
   local -n error_r="$ERROR"
   error_r[msg]='no input file'
}


function raise_missing_file {
   local -n error_r="$ERROR"
   error_r[msg]="missing or unreadable source file [${1##*/}]"
}


function raise_circular_import {
   local -n error_r="$ERROR"
   error_r[msg]="cannot source [${1##*/}], circular import"
}

#──────────────────────────────( syntax errors )────────────────────────────────
function raise_syntax_error {
   local -n error_r="$ERROR"
   error_r[msg]="${1}"
}


function raise_invalid_interpolation_char {
   local -n error_r="$ERROR"
   error_r[msg]="${1}"
}

function raise_unescaped_interpolation_brace {
   local -n error_r="$ERROR"
   error_r[msg]="single \`}' not allowed in f-string."
}

#───────────────────────────────( parse errors )────────────────────────────────
function raise_parse_error {
   local -n error_r="$ERROR"
   error_r[msg]="${1}"
}

function raise_munch_error {
   local -n error_r="$ERROR"
   error_r[msg]="expected [${1}], received [${2}], $3"
}


#───────────────────────────────( type errors )─────────────────────────────────
function raise_type_error {
   local -n error_r="$ERROR"
   error_r[msg]="$1"
}

function raise_not_a_type {
   local -n error_r="$ERROR"
   error_r[msg]="[${1}] is not a type"
}

function raise_symbol_mismatch {
   local -n error_r="$ERROR"
   error_r[msg]="does not match parent's type"
}

function raise_too_many_subtypes {
   local -n error_r="$ERROR"
   error_r[msg]="[${1,,}] only takes one subtype"
}

#────────────────────────────────( key errors )─────────────────────────────────
function raise_index_error {
   local -n error_r="$ERROR"
   error_r[msg]="[${1}] not found"  
}

function raise_name_collision {
   local -n error_r="$ERROR"
   declare -p $ERROR
   error_r[msg]="[${1}] already defined in this scope"  
}

function raise_missing_var {
   local -n error_r="$ERROR"
   error_r[msg]="[${1}] undefined"
}

#───────────────────────────────( misc. errors)───────────────────────────────
function raise_argument_error {
   local msg='invalid arguments: '
   for a in "$@" ; do
      msg+="[${a}]"
   done

   local -n error_r="$ERROR"
   error_r[msg]="$msg"
}

function raise_idiot_programmer {
   local -n error_r="$ERROR"
   error_r[msg]="$1"
}
