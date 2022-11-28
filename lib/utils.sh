#!/bin/bash
#===============================================================================
# @section                           Utils
# @description
#  All of the utilities that tie together functionality from the lexer, parser,
#  and compiler. Allows re-entering the parser for each included file, and
#  concatenating (not literally, but in spirt) imported files.
#-------------------------------------------------------------------------------

function utils:init {
   # Compiled output tree file location. Defaults to stdout.
   declare -g OUTPUT=/dev/stdout

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

   # Create resulting "file tuple". Any parsed or imported files will be folded
   # into these blank resulting ones.
   declare -ga FILE_TUPLES=()
   declare -g  TUPLE=
   declare -gi _TUPLE_NUM=0

   # Results of the parsing, symtab, and import phases.
   declare -g  FINAL_AST
   declare -g  FINAL_SYMTAB
}


function location:new {
   (( ++LOC_NUM ))
   local loc="LOC_${LOC_NUM}"
   declare -gA "$loc"
   declare -g  LOCATION="$loc"

   # Without a value, this isn't glob matched by ${!_LOC_*} expansion
   local -n l="$loc" ; l=()
}


# location:copy()
# @description
#  Copies the properties from $1's location node to $2's. If no properties are
#  specified, copies all of them. May only operate on TOKENs and NODEs.
#
# @arg   $1    NODE,TOKEN  Source location-containing node
# @arg   $2    NODE,TOKEN  Destination location-containing node
function location:copy {
   local -n from_r="$1" ; shift
   local -n to_r="$1"   ; shift
   local -a props=( "$@" )

   local -n from_loc_r="${from_r[location]}"
   local -n to_loc_r="${to_r[location]}"

   if (( ! ${#props[@]} )) ; then
      props=( "${!from_loc_r[@]}" )
   fi

   local k v
   for k in "${props[@]}" ; do
      v="${from_loc_r[$k]}"
      to_loc_r["$k"]="$v"
   done
}


# location:cursor()
# @description
#  Convenience function to create a location at the current cursor's position.
#  Cleans up otherwise messy and repetitive code in the lexer.
#
# @sets LOCATION
# @env  FILE_IDX
# @env  CURSOR
# @noargs
function location:cursor {
   location:new
   local -n loc_r="$LOCATION"
   loc_r['file']="$FILE_IDX"
   loc_r['start_ln']="${CURSOR[lineno]}"
   loc_r['start_col']="${CURSOR[colno]}"
   loc_r['end_ln']="${CURSOR[lineno]}"
   loc_r['end_col']="${CURSOR[colno]}"
}


# utils:add_file()
# @description
#  Serves to both ensure we don't have circular imports, as well as resolving
#  relative paths to their fully qualified path.
#
# @sets  FILES[]
# @sets  FILE_IDX
# @arg   $1    str      Relative or absolute path to config file
# @arg   $2    LOCATION [Optional] For error reporting import statements
function utils:add_file {
   local file="$1"
   local location="$2"
   if [[ $location ]] ; then
      local -n location_r="$location"
   fi

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
      [[ ! "$f" == "$file" ]] && continue
      e=( circular_import
         --anchor "${location_r[location]}"
         --caught "${location_r[location]}"
         "$file"
      ); raise "${e[@]}"
   done

   if [[ ! -e "$fq_path" ]] ||
      [[ ! -r "$fq_path" ]] ||
      [[   -d "$fq_path" ]]
   then
      [[ ! "$f" == "$file" ]] && continue
      e=( missing_file
         --anchor "${location_r[location]}"
         --caught "${location_r[location]}"
         "$fq_path"
      ); raise "${e[@]}"
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
# @sets  FILE_TUPLES
# @sets  TUPLE
# @arg   $1    str         Path to file to parse
# @arg   $2    LOCATION    [Optional] For error reporting of import statements
function utils:parse {
   utils:add_file "$1" "$2"

   lexer:init
   lexer:scan

   parser:init
   parser:parse

   local root="$NODE"
   walk:symtab "$root"

   utils:mk_tuple  "$NODE"  "$SYMTAB"
   FILE_TUPLES+=( "$TUPLE" )
}


# utils:mk_tuple()
# @description
#  Creates a tuple of {AST,Symtab}, to be merged and folded.
#
# @see   imports:merge
# @see   imports:fold
#
# @sets  FILE_TUPLES[]
# @sets  TUPLE
#
# @arg   $1    NODE    Root node of AST
# @arg   $2    SYMTAB  Root node of corresponding symbol table
function utils:mk_tuple {
   local node="$1"  symtab="$2"

   (( ++_TUPLE_NUM ))
   local tuple="TUPLE_${_TUPLE_NUM}"
   declare -gA "$tuple"
   declare -g TUPLE="$tuple"

   local -n t_r="$tuple"
   t_r['node']="$node"
   t_r['symtab']="$symtab"
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

   imports:parse "$NODE"
   imports:fold

   #utils:eval
}
