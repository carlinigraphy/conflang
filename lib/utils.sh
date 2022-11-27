#!/bin/bash
#
# All of the utilities that tie together functionality from the lexer, parser,
# and compiler. Allows re-entering the parser for each included file, and
# concatenating (not literally, but in spirt) %include files.

function utils:init {
   # Compiled output tree file location. Defaults to stdout.
   declare -g DATA_OUT=/dev/stdout

   # The root NODE_$n of the parent and child AST trees.
   declare -g PARENT_ROOT=
   declare -g CHILD_ROOT=

   # The root of the compiled output.
   declare -g _SKELLY_ROOT=

   # Location nodes are created in both the lexer & parser. Not a great place
   # for these. Utils make sense, as they're shared, and referenced in many
   # places.
   declare -g  LOCATION=
   declare -gi LOC_NUM=0

   # Drops anchor at the start of a declaration, expression, etc. For error
   # reporting.
   declare -g  ANCHOR=''

   # Push each absolute file path to the FILES[] stack as we hit an %include or
   # %constrain statement.
   declare -ga FILES=()
   declare -gi FILE_IDX
}


function location:new {
   (( ++LOC_NUM ))
   local loc="LOC_${LOC_NUM}"
   declare -gA "$loc"
   declare -g  LOCATION="$loc"

   # Without a value, this isn't glob matched by a ${!_LOC_*}
   local -n l="$loc" ; l=()
}


function location:copy {
   # Copies the properties from $1's location node to $2's. If no properties are
   # specified, copies all of them. May only operate on TOKENs and NODEs.
   local -n from_r="$1" ; shift
   local -n to_r="$1"   ; shift
   local -a props=( "$@" )

   local -n from_loc_r="${from_r[location]}"
   local -n to_loc_r="${to_r[location]}"

   if (( ! ${#props[@]} )) ; then
      props=( "${!from[@]}" )
   fi

   local k v
   for k in "${props[@]}" ; do
      v="${from_loc_r[$k]}"
      to_loc_r["$k"]="$v"
   done
}


function location:cursor {
   # Convenience function to create a location at the current cursor's position.
   # Cleans up otherwise messy and repetitive code in the lexer.
   location:new
   local -n loc_r="$LOCATION"
   loc_r['file']="$FILE_IDX"
   loc_r['start_ln']="${CURSOR[lineno]}"
   loc_r['start_col']="${CURSOR[colno]}"
   loc_r['end_ln']="${CURSOR[lineno]}"
   loc_r['end_col']="${CURSOR[colno]}"
}


function utils:add_file {
   # Serves to both ensure we don't have circular imports, as well as resolving
   # relative paths to their fully qualified path.
   local file="$1"
   local fq_path parent

   if [[ "${#FILES[@]}" -eq 0 ]] ; then
      # If there's nothing in FILES[], it's our first run. Any path that's
      # relative is inherently relative to our current working directory.
      parent="$PWD"
   else
      parent="${FILES[-1]%/*}"
   fi

   case "$file" in
      # Absolute paths.
      /*)   fq_path="${file}"           ;;
      ~*)   fq_path="${file/\~/$HOME}"  ;;

      # Paths relative to the calling file.
      *)    fq_path=$( realpath -m "${parent}/${file}" -q )
            ;;
   esac

   for f in "${FILES[@]}" ; do
      # TODO: location reporting
      [[ "$f" == "$file" ]] && raise circular_import "$file"
   done

   if [[ ! -e "$fq_path" ]] ||
      [[ ! -r "$fq_path" ]] ||
      [[   -d "$fq_path" ]]
   then
      # TODO: location reporting
      raise missing_file "$fq_path"
   fi

   FILES+=( "$fq_path" )
   (( FILE_IDX = ${#FILES[@]} - 1 )) ||:
}


# utils:parse()
# @description
#  Generates the AST & symbol table for a single file.
#
# @sets  NODE
# @sets  SYMTAB
# @arg   $1    str         Path to file to parse
# @arg   $2    LOCATION    [Optional] For error reporting of import statements
function utils:parse {
   utils:add_file "$1" "$2"

   lexer:init
   lexer:scan
   # Exports:
   #  list  TOKENS[]
   #  dict  TOKEN_*

   parser:init
   parser:parse
   # Exports:
   #  dict  TYPEOF{}
   #  dict  NODE_*

   local root="$NODE"
   walk:symtab  "$root"
   utils:import "$root"  "$SYMTAB"
   # For each `import` statement, parse & concatenate returning a new AST and
   # symbol table.
}


# utils:import()
# @description
#  Identifies and merges all include statements for this given file.
#
# @arg   $1    NODE     Root AST node for a file
# @arg   $2    SYMTAB   Associated symbol table
function utils:import {
   local node="$1"
   local -n node_r="$node"
   local -n header_r="${node_r[header]}"
   local -n container_r="${node_r[container]}"

   local symtab="$2"
   local -n symtab_r="$symtab"

   local path location
   for h in "${header_r[@]}" ; do
      if [[ ! ${TYPEOF[$h]} == import ]] ; then
         continue
      fi

      local -n h_r="$h"
      utils:parse "${h_r[path]}"  "${h_r[location]}"
   done
}


# utils:eval
# @description
#  Requires all imports already merged into a single AST/symtab. Flattens AST
#  in order of dependencies for semantics & final evaluation.
#
# @noargs
function utils:eval {
   walk:flatten "$NODE"
   dependency_to_map
   dependency_sort

   for ast_node in "${ORDERED_DEPS[@]}" ; do
      walk:semantics "$ast_node"
   done

   walk:compiler "$NODE"
}


# evaluate()
# @description
#  Wrapper function to kick off the whole parse, typcheck, and evaluation
#  pieline.
#
# @env   NODE
# @env   SYMTAB
# @arg   $1    str   Initial file path to evaluate
function evaluate {
   utils:init
   utils:parse "$1"
   #utils:eval
}
