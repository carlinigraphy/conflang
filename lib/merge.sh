#!/bin/bash
#===============================================================================
# @section                        Merge trees
# @description
#  Functions for merging a right hand side (RHS) {AST,Symtab} tuple into the
#  left hand side (LHS) tuple.
#-------------------------------------------------------------------------------

# fold()
# @description
#  Not technically a fold, but in spirit. Iter each item in `FILES[]`, merges
#  into the leftmost FILE.
#
# @env   FILES{}
# @env   IMPORTS[]
#
# @set   FILE
# @set   NODE
# @set   SYMTAB
# @noargs
function fold {
   local _path="${IMPORTS[0]}"
   declare -g FILE="${FILES[$_path]}"

   local -n lhs_r="$FILE"
   local lhs_ast="${lhs_r[ast]}"
   local lhs_symtab="${lhs_r[symtab]}"

   for path in "${IMPORTS[@]:1}" ; do
      local -n rhs_r="${FILES[$path]}"
      local rhs_ast="${rhs_r[ast]}"
      local rhs_symtab="${rhs_r[symtab]}"
      merge  "$lhs_ast"  "$lhs_symtab"  "$rhs_ast"  "$rhs_symtab"
   done

   declare -g NODE="$lhs_ast"
   declare -g SYMTAB="$lhs_symtab"
}


# merge()
# @description
#  Merges two files by the rules below:
#  - Expressions maybe overwritten
#  - Types may be overwritten with equal or greater specificity
#    - [GOOD]: `arr @list;`  ->  `arr @list[str];`
#    - [BAD]: `arr @list[str]`  ->  `arr @list[int];`
#    - [BAD]: `arr @list[str];`  ->  `arr @str;`
#
# @see   merge:section
# @see   merge:variable
# @see   merge:type
#
# @arg   $1    :NODE       LHS ast
# @arg   $2    :SYMTAB     LHS symtab
# @arg   $3    :NODE       RHS ast
# @arg   $4    :SYMTAB     RHS symtab
function merge {
   local lhs_ast="$1"
   local lhs_symtab="$2"
   local -n lhs_symtab_r="$lhs_symtab"
   local -n lhs_ast_r="$lhs_ast"

   local rhs_ast="$3"
   local rhs_symtab="$4"
   local -n rhs_symtab_r="$rhs_symtab"
   local -n rhs_ast_r="$rhs_ast"

   # Will hold keys present in rhs not found in lhs... "overflow".
   local -A overflow=()
   for symbol_name in "${!rhs_symtab_r[@]}" ; do
      overflow["$symbol_name"]="${rhs_symtab_r[$symbol_name]}" 
   done

   for symbol_name in "${!lhs_symtab_r[@]}" ; do
      local lhs_sym="${lhs_symtab_r[$symbol_name]}"
      local -n lhs_sym_r="$lhs_sym"
      local -n lhs_type_r="${lhs_sym_r[type]}"

      local rhs_sym="${rhs_symtab_r[$symbol_name]}"
      [[ ! "$rhs_sym" ]] && continue
      #--^ Symbol not found in RHS, nothing to do.

      unset 'overflow[$symbol_name]'

      case "${lhs_type_r[kind]}" in
         SECTION) merge:section   "$lhs_sym"  "$rhs_sym"                 ;;
         TYPE)    merge:typedef   "$lhs_sym"  "$rhs_sym"                 ;;
         *)       merge:variable  "$lhs_sym"  "$rhs_sym"  "$lhs_symtab"  ;;
      esac
   done

   # Set rhs's symtab parent to lhs's parent. Necessary for overflow statements.
   SYMTAB_PARENT["$rhs_symtab"]="${SYMTAB_PARENT["$lhs_symtab"]}"

   # Merge overflow back in.
   local -n lhs_items_r="${lhs_ast_r[items]}"
   for symbol_name in "${!overflow[@]}" ; do
      local rhs_sym="${overflow[$symbol_name]}"
      local -n rhs_sym_r="$rhs_sym"
      local rhs_node="${rhs_sym_r[node]}"

      lhs_items_r+=( "$rhs_node" )
      lhs_symtab_r["$symbol_name"]="$rhs_sym"
   done
}


# merge:section()
# @description
#  This is a validation step. Ensures the rhs symbol is also a Section. Then
#  calls `merge()` on the inner symtab.
#
# @see   merge
#
# @arg   $1    :SYMBOL
# @arg   $2    :SYMBOL
function merge:section {
   local lhs_sym="$1"
   local rhs_sym="$2"

   #-- LHS dogshit.
   local -n lhs_sym_r="$lhs_sym"
   local -n lhs_type_r="${lhs_sym_r[type]}"

   local lhs_node="${lhs_sym_r[node]}"
   local -n lhs_node_r="$lhs_node"

   #-- RHS bullshit.
   local -n rhs_sym_r="$rhs_sym"
   local -n rhs_type_r="${rhs_sym_r[type]}"

   local rhs_node="${rhs_sym_r[node]}"
   local -n rhs_node_r="$rhs_node"
   
   # validation.
   if [[ ! ${rhs_type_r[kind]} == SECTION ]] ; then
      local -n lhs_name_r="${lhs_node_r[name]}"
      local -n rhs_name_r="${rhs_node_r[name]}"

      e=( symbol_mismatch
         --anchor "${lhs_name_r[location]}"
         --caught "${rhs_name_r[location]}"
      ); raise "${e[@]}"
   fi

   local lhs_symtab="${lhs_node_r[symtab]}"
   local rhs_symtab="${rhs_node_r[symtab]}"

   merge  "$lhs_node"  "$lhs_symtab"  "$rhs_node"  "$rhs_symtab"
}


# TODO(CURRENT):
#  Definitely now think that built-in types need to live in their own symbol
#  table, at a level above the regular user table. Or maybe they're not
#  introduced until after the merging phase? Either way, it adds unnecessary
#  complexity to need to merge them across every time as well. Shouldn't need
#  to consider merging copies of the same BITs for every file, it's a waste.
#
#  Options are:
#     - Create a separate "BITs" table that's set as the parent of the merged
#       result
#     - Nvm I like that solution


# merge:typedef()
# @description
#  This is a validation step. Cannot re-define typedefs.
#
# @see   merge
#
# @arg   $1    :SYMBOL
# @arg   $2    :SYMBOL
function merge:typedef {
   local lhs_sym="$1"
   local rhs_sym="$2"

   #-- LHS dogshit.
   local -n lhs_sym_r="$lhs_sym"
   local -n lhs_type_r="${lhs_sym_r[type]}"

   #-- RHS bullshit.
   local -n rhs_sym_r="$rhs_sym"
   local -n rhs_type_r="${rhs_sym_r[type]}"
   
   # validation.
   if [[ ! ${rhs_type_r[kind]} == TYPE ]] ; then
      # Any non-type rhs must have a ['node']. Safe to index.
      local -n rhs_node_r="${rhs_sym_r[node]}"
      local -n rhs_name_r="${rhs_node_r[name]}"

      if [[ ! "${lhs_sym_r[node]}" ]] ; then
         # Only built-in types do not have associated ['node']s.
         e=( --anchor "${rhs_node_r[location]}"
             --caught "${rhs_name_r[location]}"
             "[${rhs_sym_r[name]}] conflicts with built-in type"
         ); raise type_error "${e[@]}"
      else
         local -n lhs_node_r="${lhs_sym_r[node]}" 
         e=( --anchor "${lhs_node_r[location]}"
             --caught "${rhs_name_r[location]}"
         ); raise symbol_mismatch "${e[@]}"
      fi
   fi
}


# merge:variable()
# @description
function merge:variable {
   local lhs_sym="$1"
   local rhs_sym="$2"
   local symtab="$3"

   #-- LHS dogshit.
   local -n lhs_sym_r="$lhs_sym"
   local -n lhs_type_r="${lhs_sym_r[type]}"

   local lhs_node="${lhs_sym_r[node]}"
   local -n lhs_node_r="$lhs_node"

   #-- RHS bullshit.
   local -n rhs_sym_r="$rhs_sym"
   local -n rhs_type_r="${rhs_sym_r[type]}"

   local rhs_node="${rhs_sym_r[node]}"
   local -n rhs_node_r="$rhs_node"
}


# merge:type()
# @description
#  This it's not a semantic typecheck. It only enforces the deference in an
#  imported file's type, which must be at minimum equal to the LHS type.
#  
# @arg   $1    :SYMBOL     LHS symbol
# @arg   $2    :SYMBOL     RHS symbol
function merge:type {
   local -n lhs_sym_r="$1"
   local -n rhs_sym_r="$2"

   local -n lhs_type_r="${lhs_sym_r[type]}"
   local -n rhs_type_r="${rhs_sym_r[type]}"

   merge:type  "$lhs_sym"  "$rhs_sym"

   # RHS has not declared a type -- change nothing.
   #[[ "${rhs_type_r[kind]}" == ANY ]] && return 0

   


   # TODO: maybe we want to first establish all the cases in which we DON'T
   #       copy tye type across and return. If nothing needs to be done, can
   #       return 0. Else return 1 for the `throw error` options below.

   # TODO: hmm, this isn't quite what we need.
   #       The cases for the calling function are:
   #       1. [x] f0 has no type, fN has no type          (change nothing)
   #       2. [x] f0 declares a type, fN does not         (change nothing)
   #       3. [ ] f0 declares a type, fN same type        (change nothing)
   #
   #       4. [ ] f0 declares a type, fN more specific    (use fN type)
   #
   #       5. [ ] f0 has no type, f1 declares a type      (throw error)
   #       6. [ ] f0 declares a type, fN less specific    (throw error)
   #       7. [ ] f0 declares a type, fN different type   (throw error)
   #
   #       Recall that declaring no type gives an implicit ANY.
   #
   #       Probably need to have this function call some sub functions.
   
   # TODO: I think if I reverse their order, it makes more sense. Pretty much
   #       the same as it was before, except reverse lhs/rhs order.

   lhs_sym_r[type]="${rhs_sym_r[type]}"
}


function walk:merge {
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
   if [[ ! ${c_type_r[kind]} == SECTION ]] ; then
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
   [[ ! ${t1_r['kind']} == "${t2_r[kind]}" ]] && return 1

   # Then match subtypes.
   if [[ ${t1_r['subtype']} ]] ; then
      merge_type "${t1_r[subtype]}" "${t2_r[subtype]}"
      return $?
   fi

   return 0
}
