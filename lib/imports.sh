#!/bin/bash
#===============================================================================
# @section                        Merge trees
# @description
#  Functions for merging a right hand side (RHS) {AST,Symtab} tuple into the
#  left hand side (LHS) tuple.
#-------------------------------------------------------------------------------

# imports:parse()
# @description
#  Identifies and calls `utils:parse` on all import statements.
#
# @see   utils:parse
#
# @arg   $1    NODE     Root AST node for a file
function imports:parse {
   local node="$1"
   local -n node_r="$node"
   local -n header_r="${node_r[header]}"
   local -n container_r="${node_r[container]}"

   local path location
   for h in "${header_r[@]}" ; do
      if [[ ! ${TYPEOF[$h]} == import ]] ; then
         continue
      fi
      local -n h_r="$h"
      utils:parse "${h_r[path]}"  "${h_r[location]}"
   done
}


# imports:fold()
# @description
#  Thanks FP, you've come in handy! Effectively:
#  ```erlang
#  {Rv_Ast, Rv_Symtab} = fold(merge, {AST:new(), Symtab:new()}, FILE_TUPLES)
#  ```
# @env   FILE_TUPLES[]
# @sets  FINAL_AST
# @sets  FINAL_SYMTAB
# @sets  ACCUM_TUPLE
function imports:fold {
   if (( ${#FILE_TUPLES[@]} )) ; then
      local -n tuple_r="${FILE_TUPLES[0]}"
      declare -g FINAL_AST="${tuple_r[node]}"
      declare -g FINAL_SYMTAB="${tuple_r[symtab]}"
      return
   fi

   ast:new program ; symtab new
   utils:mk_tuple "$NODE" "$SYMTAB"
   declare -g ACCUM_TUPLE="$TUPLE"

   for t in "${FILE_TUPLES[@]}" ; do
      imports:merge "$ACCUM_TUPLE"  "$t"
   done
}


# imports:merge()
# @description
#  Merges a pair of {AST/Symtab} together. When `import`ing files, users may not
#  overwrite typedefs with less specificity, or overwrite an expression with a
#  different type.
#
# @sets  ACCUM_TUPLE
# @arg   $1    TUPLE    LHS tuple
# @arg   $2    TUPLE    RHS tuple, merged into LHS
function imports:merge {
   local left_tuple="$1"
   local -n l_tuple_r="$left_tuple"

   local right_tuple="$2"
   local -n r_tuple_r="$right_tuple"

   # TODO:
   # Not quite sure how the trees should be merged. One of two approaches.
   #  (1) Merge symbol tables.
   # As every element of the %container is a declaration, every element has a
   # Symbol at its Section's scope. Iterating each scope yields each decl.
   #  (2) Walk AST, merge trees.
   # Takes a little more--
   #
   # brain blast.
   #
   # Pretty sure we need to walk the symbol table, then use it to descend into
   # each new section. Similar to the approach below. Cannot iterate the ASTs
   # directly, because there's no way to compare *names* between LHS & RHS.
   # Section is just a collection of declarations, doesn't have indices.
   #
   # 1. Merge "global" section of thesymtab, containing typedefs.
   # 2. Select %container section
   # 3. Walk sections, compare keys & overflow
   # 4. Disallow changing Section > var, or var -> Section
   # 5. Disallow changing the type of variable declarations nodes to be *less*
   #    specific. Must be an equal type, or one with greater specificity
   # 6. Create a new AST and Symtab on every merge? or continuously fold into
   #    the left.
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
      echo ":[ $k ]"
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


