#!/bin/bash
#===============================================================================
# @section                           Utils
# @description
#  All of the utilities that tie together functionality from the lexer, parser,
#  and compiler. Allows re-entering the parser for each included file, and
#  concatenating (not literally, but in spirt) imported files.
#-------------------------------------------------------------------------------

# file:new()
# @description
#  Creates new object representing "files".
#
# @env   _FILE_NUM
# @env   _FILE_LINES_NUM
#
# @set   FILE
# @set   _FILE_NUM
# @set   _FILE_LINES_NUM
# @noargs
function file:new {
   (( ++_FILE_NUM ))
   local file="FILE_${_FILE_NUM}"
   declare -gA "$file"
   declare -g FILE="$file"

   (( ++_FILE_LINES_NUM ))
   local lines="FILE_LINES_${_FILE_LINES_NUM}"
   declare -ga "$lines"

   local -n file_r="$file"
   file_r['path']=''             #< absolute path to file
   file_r['symtab']=''           #< root symbol table for file
   file_r['container']=''        #< .container node of AST
   file_r['lines']="$lines"
}


# file:resolve()
# @description
#  Throws error on circular imports, resolves relative paths to fully qualified
#  path.
#
# @env   FILE
# @set   FILES{}
#
# @arg   $1    :str        Relative or absolute path to the file
# @arg   $2    :str        Parent to which this file is relative
# @arg   $3    :LOCATION   For error reporting invalid import statements
function file:resolve {
   local path="$1"
   local parent="$2"
   local location="$3"
   if [[ "$location" ]] ; then
      local -n location_r="$location"
   fi

   local fq_path
   case "$path" in
      # Absolute paths.
      /*) fq_path="${path}"           ;;
      ~*) fq_path="${path/\~/$HOME}"  ;;

      # Paths relative to the calling file.
      *)  fq_path=$( realpath -m "${parent}/${path}" -q )
          ;;
   esac

   # throw:  circular_import
   if [[ "${FILES[$fq_path]}" ]] ; then
      e=( circular_import
         --anchor "${location_r[location]}"
         --caught "${location_r[location]}"
         "$path"
      ); raise "${e[@]}"
   fi

   # throw:  missing_file
   if [[ ! -e "$fq_path" ]] ||
      [[ ! -r "$fq_path" ]] ||
      [[   -d "$fq_path" ]]
   then
      e=( missing_file
         --anchor "${location_r[location]}"
         --caught "${location_r[location]}"
         "$fq_path"
      ); raise "${e[@]}"
   fi

   local -n file_r="$FILE"
   file_r['path']="$fq_path"

   FILES["$fq_path"]="$FILE"
   IMPORTS+=( "$fq_path" )
}


# file:parse()
# @description
#  Generates the AST & symbol table for a single file.
#
# @set   NODE
# @set   SYMTAB
# @env   FILE
#
# @arg   $1    :FILE    Globally sets $FILE pointer for lexer & parser
function file:parse {
   local file="$1"
   local -n file_r="$file"
   declare -g FILE="$file"

   lexer:init
   lexer:scan

   parser:init
   parser:parse
   local -n node_r="$NODE"
   file_r['ast']="${node_r[container]}"

   walk:symtab "$NODE"
   file_r['symtab']="$SYMTAB"
}


#===============================================================================
# @section                          Imports
# @description
#  Pulls out `import` statements from each AST, parses, folds into resulting
#  tree & symtab tuple.
#-------------------------------------------------------------------------------

# imports:parse()
# @description
#  Identifies and calls `utils:parse` on all import statements.
#
# @see   utils:parse
# @arg   $1    :NODE     Root AST node for a file
function imports:parse {
   local node="$1"

   # Drill down to node.header[].import
   local -n node_r="$node"
   local -n header_r="${node_r[header]}"
   local -n items_r="${header_r[items]}"

   local path location
   for h in "${items_r[@]}" ; do
      if [[ ! ${TYPEOF[$h]} == import ]] ; then
         continue
      fi
      local -n h_r="$h"
      local -n ident_r="${h_r[path]}"  
      utils:parse "${ident_r[value]}"  "${h_r[location]}"
   done
}


# imports:fold()
# @description
#  Not technically a fold, but in spirit. Iter each item in `FILE_TUPLES[]`,
#  merges into the current resulting `ACCUM_TUPLE`.
#
# @set   FINAL_AST
# @set   FINAL_SYMTAB
# @set   ACCUM_TUPLE
# @noargs
function imports:fold {
   declare -g ACCUM_TUPLE="${FILE_TUPLES[0]}"
   for t in "${FILE_TUPLES[@]:1}" ; do
      merge "$t"
   done

   local -n tuple_r="${FILE_TUPLES[0]}"
   declare -g FINAL_AST="${tuple_r[node]}"
   declare -g FINAL_SYMTAB="${tuple_r[symtab]}"
}


#===============================================================================
# @section                        Merge trees
# @description
#  Functions for merging a right hand side (RHS) {AST,Symtab} tuple into the
#  left hand side (LHS) tuple.
#-------------------------------------------------------------------------------

# merge()
# @description
#  Merges two files by the rules below:
#  - Expressions maybe overwritten
#  - Types may be imported with equal or greater specificity
#    - [GOOD]: `arr @list;`  ->  `arr @list[str];`
#    - [BAD]: `arr @list[str]`  ->  `arr @list[int];`
#    - [BAD]: `arr @list[str];`  ->  `arr @str;`
#
# @see   merge:symtab
# @see   merge:section
# @see   merge:variable
# @see   merge:type
#
# @set   ACCUM_TUPLE
# @arg   $1    :TUPLE    RHS tuple, merged into $ACCUM_TUPLE
function merge {
   local -n l_tuple_r="$ACCUM_TUPLE"
   local l_container="${l_tuple_r[container]}"
   local l_symtab="${l_tuple_r[symtab]}"

   local -n r_tuple_r="$1"
   local r_container="${r_tuple_r[container]}"
   local r_symtab="${r_tuple_r[symtab]}"

   merge:symtab "$l_symtab"  "$l_container"  "$r_symtab"  "$r_container"
}


function merge:symtab {
   local lhs_symtab="$1"
   local lhs_container="$2"
   local -n lhs_symtab_r="$lhs_symtab"
   local -n lhs_container_r="$lhs_container"

   local rhs_symtab="$3"
   local rhs_container="$4"
   local -n rhs_symtab_r="$rhs_symtab"
   local -n rhs_containerhs_r="$rhs_container"

   # As iterating symtab, unset all keys if also found in the left container.
   # What's left is: set(rhs) - set(lhs). Then copy these over.
   local -a overflow=( "${!rhs_container[@]}" )

   # Checks at the symtab level:
   # - If not present in RHS , skip
   # - If type inequality    , throw error
   # - If variable           , merge:variable && walk:merge
   # - If section            , descend and call merge:symtab on sub-scope
   #
   # Must always update .symtab reference in the node. This may require a
   # walk:merge to reach identifiers in expressions
   #
   for symbol_name in "${!lhs_symtab_r[@]}" ; do
      local lhs_sym="${lhs_symtab_r[$symbol_name]}"
      local -n lhs_sym_r="$lhs_sym"
      local lhs_type="${lhs_sym_r[type]}"

      # case 1:  variable not declared in rhs, nothing to do
      if [[ ! "${rhs_symtab_r[$symbol_name]}" ]] ; then
         continue
      fi

      unset 'overflow[$symbol_name]'

      local -n rhs_sym_r="$rhs_sym"
      local rhs_type="${rhs_sym_r[type]}"

      # case 2:  type inequality
      if ! merge:type  "$lhs_type"  "$rhs_type" ; then
         :;
      fi

      # TODO: copy type across if met equality check

      # TODO: if section, iter its scopes and whatnot

      # TODO: need to also copy the names/symbols themselves from the rhs to lhs
      # with respect to name collisions.
   done
}


function merge:section {
   :;
}


function merge:variable {
   :;
}


function merge:type {
   :;
}












function merge_symtab {
   local -n parent_section_r="$1"
   local p_symtab="$2"
   local -n p_symtab_r="$p_symtab"
   local -n c_symtab_r="$3"

   # We iterate over the parent symtab. So we're guaranteed to hit every key
   # there. The child symtab may contain *extra* keys that we need to merge in.
   # Every time we match a key from the parent->child, we can pop it from this
   # copy. Anything left is a duplicate that must be merged.
   local -A overflow=()
   for k in "${!c_symtab_r[@]}" ; do
      overflow["$k"]=
   done

   for p_key in "${!p_symtab_r[@]}" ; do
      # Parent Symbol.
      local p_sym="${p_symtab_r[$p_key]}"
      local -n p_sym_r="$p_sym"
      local p_node="${p_sym_r[node]}"

      # Parent type information.
      local p_type="${p_sym_r[type]}"
      local -n p_type_r="$p_type"

      # Child Symbol.
      # The child symbol may not necessarily exist. These cases, and the error
      # reporting, are both handled in their respective functions:
      # `merge_variable`, `merge_section`.
      local c_sym="${c_symtab_r[$p_key]}"

      unset 'overflow[$p_key]'
      # Pop reference to child symbol from the `overflow[]` copy. Will allow
      # us to check at the end if there are leftover keys that are defined in
      # the child, but not in the parent.

      if [[ "${p_type_r[kind]}" == 'SECTION' ]] ; then
         merge_section  "$p_sym" "$c_sym"
      else
         merge_variable "$p_sym" "$c_sym"
      fi
   done

   # Any additional keys from the child need to be copied into both...
   #  1. the parent's .items[] array
   #  2. the parent's symbol table
   local -n items_r="${parent_section_r[items]}"
   for c_key in "${!overflow[@]}" ; do
      local c_sym="${c_symtab_r[$c_key]}"

      # Add to symtab.
      p_symtab_r["$c_key"]="$c_sym"

      # Add to items.
      local -n c_sym_r="${c_symtab_r[$c_key]}"
      items_r+=( "${c_sym_r[node]}" )

      # Update symtab pointer.
      local -n c_sym_r="$c_sym"
      local -n c_node_r="${c_sym_r[node]}"
      c_node_r[symtab]="$p_symtab"
   done
}


function merge_section {
   # It's easier to think about the conditions in which a merge *fails*. A
   # section merge fails when:
   #  1. It is required in the parent, and missing in the child
   #  2. It is of a non-Section type in the child

   local -n p_sym_r="$1"
   local -n p_node_r="${p_sym_r[node]}"
   local -n p_name_r="${p_node_r[name]}"

   local c_sym="$2"

   # case 1.
   # Child section is missing, but was required in the parent.
   if [[ ! "$c_sym" ]] ; then
      if [[ "${p_sym_r[required]}" ]] ; then
         e=( missing_required
            --anchor "${p_name_r[location]}"
            --caught "${p_name_r[location]}"
            "${p_sym_r[name]}"
         ); raise "${e[@]}"
      else
         return 0  # if not required, can ignore.
      fi
   fi

   local -n c_sym_r="$c_sym"
   local -n c_type_r="${c_sym_r[type]}"
   local -n c_node_r="${c_sym_r[node]}"
   local -n c_name_r="${c_node_r[name]}"

   # case 2.
   # Found child node under the same identifier, but not a Section.
   if [[ ${c_type_r[kind]} != 'SECTION' ]] ; then
      e=( symbol_mismatch
         --anchor "${p_name_r[location]}"
         --caught "${c_name_r[location]}"
         "${p_sym_r[name]}"
      ); raise "${e[@]}"
   fi

   merge_symtab "${p_sym_r[node]}"  "${p_node_r[symtab]}"  "${c_node_r[symtab]}"
   #               ^-- parent node     ^-- parent symtab      ^-- child symtab

   # If they occur in different files, must also copy over the reference to the
   # parent symtab.
   c_node_r[symtab]="${p_node_r[symtab]}"
}


function merge_variable {
   # It's easier to think about the conditions in which a merge *fails*. A
   # variable merge fails when:
   #  1. If the child does not exist, and...
   #     a. the parent was required
   #  2. If the child exist, and...
   #     a. it's not also a type(var_decl)
   #     b. it's declaring a different type

   local -n p_sym_r="$1"
   local -n p_node_r="${p_sym_r[node]}"
   local -n p_name_r="${p_node_r[name]}"

   local c_sym="$2"

   # case 1a.
   if [[ ! "$c_sym" ]] ; then
      if [[ "${p_sym_r[required]}" ]] ; then
         e=( missing_required
            --anchor "${p_name_r[location]}"
            --caught "${p_name_r[location]}"
            "${p_sym_r[name]}"
         ); raise "${e[@]}"
      else
         return 0  # if not required, can ignore.
      fi
   fi

   local -n c_sym_r="$c_sym"
   local -n c_node_r="${c_sym_r[node]}"
   local -n c_name_r="${c_node_r[name]}"

   # case 2a.
   # Expecting a variable declaration, child is actually a Section.
   local -n c_type_r="${c_sym_r[type]}"
   if [[ "${c_type_r[kind]}" == 'SECTION' ]] ; then
      e=( symbol_mismatch
         --anchor "${p_name_r[location]}"
         --caught "${c_name_r[location]}"
         "${p_sym_r[name]}"
      ); raise "${e[@]}"
   fi

   # case 2b.
   # The type of the child must defer to the type of the parent.
   if ! merge_type "${p_sym_r[type]}" "${c_sym_r[type]}" ; then
      e=( symbol_mismatch
         --anchor "${p_name_r[location]}"
         --caught "${c_name_r[location]}"
         "${p_sym_r[name]}"
      ); raise "${e[@]}"
   fi

   # If we haven't hit any errors, can safely copy over the child's value to the
   # parent.
   local -n p_node_r="${p_sym_r[node]}"
   local -n c_node_r="${c_sym_r[node]}"
   if [[ "${c_node_r[expr]}" ]] ; then
      #  ┌── does not understand namerefs
      # shellcheck disable=SC2034
      p_node_r['expr']="${c_node_r[expr]}"
   fi

   # If they occur in different files, must also copy over the reference to the
   # parent symtab.
   c_node_r[symtab]="${p_node_r[symtab]}"
}


function merge_type {
   # This it's not a semantic typecheck. It only enforces the deference in a
   # child's type. The child must either...
   #  1. match exactly
   #  2. be 'ANY'
   #  3. not exist (in the case of a parent subtype, and the child's is empty)

   # case 3.
   # If there's a defined parent type, but no child.
   [[ $1 && ! $2 ]] && return 0

   local -n t1_r="$1"
   local -n t2_r="$2"

   # case 2.
   # Doesn't matter what the parent's type was. The child is not declaring it,
   # thus respecting the imposed type.
   [[ "${t2_r[kind]}" == 'ANY' ]] && return 0

   # case 1.
   # First match base types.
   [[ ${t1_r['kind']} != "${t2_r[kind]}" ]] && return 1

   # Then match subtypes.
   if [[ ${t1_r['subtype']} ]] ; then
      merge_type "${t1_r[subtype]}" "${t2_r[subtype]}"
      return $?
   fi

   return 0
}


