#!/bin/bash
#===============================================================================
# @section                         Fold trees
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

   # shellcheck disable=SC2153
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
#
#  - Expressions may be overwritten
#  - Types may be overwritten with equal or greater specificity
#    - (good): `arr @list;`  ->  `arr @list[str];`
#    - (bad): `arr @list[str];`  ->  `arr @list[int];`
#    - (bad): `arr @list[str];`  ->  `arr @str;`
#
#  Easier to think about it as: the rhs always overwrites the lhs unless the
#  declared type is of lesser specificity.
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

   # Will hold rhs keys not found in lhs... thus "overflow".
   local -A overflow=()
   for symbol_name in "${!rhs_symtab_r[@]}" ; do
      overflow["$symbol_name"]="${rhs_symtab_r[$symbol_name]}" 
   done

   for symbol_name in "${!lhs_symtab_r[@]}" ; do
      local lhs_sym="${lhs_symtab_r[$symbol_name]}"
      local -n lhs_sym_r="$lhs_sym"
      local -n lhs_type_r="${lhs_sym_r[type]}"

      local rhs_sym="${rhs_symtab_r[$symbol_name]}"
      if [[ ! "$rhs_sym" ]] ; then
         continue
      fi

      unset 'overflow[$symbol_name]'

      # TODO: May be unnecessary to merge types, as all typedefs are now
      #       assigned directly to the global symbol table.
      case "${lhs_type_r[kind]}" in
         SECTION) merge:section   "$lhs_sym"  "$rhs_sym"                 ;;
         TYPE)    merge:typedef   "$lhs_sym"  "$rhs_sym"                 ;;
         *)       merge:variable  "$lhs_sym"  "$rhs_sym"  "$lhs_symtab"  ;;
      esac
   done

   # Set rhs's symtab parent to lhs's parent. Necessary for overflow statements.
   SYMTAB_PARENT["$rhs_symtab"]="${SYMTAB_PARENT[$lhs_symtab]}"

   # Merge overflow back in.
   local -n lhs_items_r="${lhs_ast_r[items]}"
   for symbol_name in "${!overflow[@]}" ; do
      local rhs_sym="${overflow[$symbol_name]}"
      local -n rhs_sym_r="$rhs_sym"
      local rhs_node="${rhs_sym_r[node]}"

      lhs_items_r+=( "$rhs_node" )
      lhs_symtab_r["$symbol_name"]="$rhs_sym"

      # Walk the rhs node's expression. Ensures updating `.symtab` in any
      # identifiers.
      declare -g SYMTAB="$lhs_symtab"
      walk:merge "$rhs_node"
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
      e=( --anchor "${lhs_name_r[location]}"
          --caught "${rhs_name_r[location]}"
      ); raise symbol_mismatch "${e[@]}"
   fi

   local lhs_symtab="${lhs_node_r[symtab]}"
   local rhs_symtab="${rhs_node_r[symtab]}"

   merge  "$lhs_node"  "$lhs_symtab"  "$rhs_node"  "$rhs_symtab"
}


# merge:typedef()
# @description
#  This it's not a semantic typecheck. It only requires a duplicate typedef in
#  an imported file *exactly* matches. You can declare a variable is more
#  specific, but cannot change the underlying typedef itself.
#
# @arg   $1    :SYMBOL     LHS symbol
# @arg   $2    :SYMBOL     RHS symbol
function merge:typedef {
   local -n lhs_sym_r="$1"
   local -n rhs_sym_r="$2"

   local lhs_type="${lhs_sym_r[type]}"
   local rhs_type="${rhs_sym_r[type]}"

   if ! type:eq  "$lhs_type"  "$rhs_type"  --strict ; then
      local lhs_node="${lhs_sym_r[node]}"
      local -n lhs_node_r="$lhs_node"
      local -n lhs_typedef_r="${lhs_node_r[type]}"

      local rhs_node="${rhs_sym_r[node]}"
      local -n rhs_node_r="$rhs_node"
      local -n rhs_typedef_r="${rhs_node_r[type]}"

      e=( --anchor "${lhs_typedef_r[location]}"
          --caught "${rhs_typedef_r[location]}"
          'May not re-define a typedef'
          "$lhs_type"  "$rhs_type"
      ); raise type_error "${e[@]}"
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
   local lhs_type="${lhs_sym_r[type]}"
   local lhs_node="${lhs_sym_r[node]}"
   local -n lhs_node_r="$lhs_node"

   #-- RHS bullshit.
   local -n rhs_sym_r="$rhs_sym"
   local rhs_type="${rhs_sym_r[type]}"
   local rhs_node="${rhs_sym_r[node]}"
   local -n rhs_node_r="$rhs_node"

   # Need to check both
   # 1. If rhs declared a type
   # 2. Rhs is greater 
   if [[ ${rhs_node_r[type]} ]] && ! type:eq "$lhs_type"  "$rhs_type" ; then
      local -n lhs_type_r="${lhs_node_r[type]}"
      local -n rhs_type_r="${rhs_node_r[type]}"
      e=( --anchor "${lhs_type_r[location]}"
          --caught "${rhs_type_r[location]}"
          'overwriting type annotations must be of equal or greater specificity'
          "$lhs_type"  "$rhs_type"
      ); raise type_error "${e[@]}"
   fi

   lhs_node_r["expr"]="${rhs_node_r[expr]}"

   # Gotta walk the rhs expression to find any identifiers. Update their symtab
   # pointer to the appropriate lhs symtab.
   declare -g SYMTAB="$symtab"
   walk:merge "$rhs_node"
}


function walk:merge {
   declare -g NODE="$1"
   merge_"${TYPEOF[$NODE]}"
}


function merge_decl_section {
   local -n node_r="$NODE"
   local -n items_r="${node_r[items]}"
   for ast_node in "${items_r[@]}" ; do
      walk:merge "$ast_node"
   done
}


function merge_decl_variable {
   local -n node_r="$NODE"

   if [[ ${node_r[type]} ]] ; then
      walk:merge "${node_r[type]}"
   fi

   if [[ ${node_r[expr]} ]] ; then
      walk:merge "${node_r[expr]}"
   fi
}


function merge_type {
   local -n node_r="$NODE"
   walk:merge "${node_r[kind]}"

   if [[ "${node_r[subtype]}" ]] ; then
      walk:merge "${node_r[subtype]}"
   fi

   if [[ "${node_r[next]}" ]] ; then
      walk:merge "${node_r[next]}"
   fi
}


function merge_typecast {
   local -n node_r="$NODE"
   walk:merge "${node_r[expr]}"
}


function merge_member {
   local -n node_r="$NODE"
   walk:merge "${node_r[left]}"
   walk:merge "${node_r[right]}"
}


function merge_index {
   local -n node_r="$NODE"
   walk:merge "${node_r[left]}"
   walk:merge "${node_r[right]}"
}


function merge_unary {
   local -n node_r="$NODE"
   walk:merge "${node_r[right]}"
}


function merge_list {
   local -n node_r="$NODE"
   local -n items_r="${node_r[items]}"
   for ast_node in "${items_r[@]}"; do
      walk:merge "$ast_node"
   done
}


function merge_record {
   local -n node_r="$NODE"
   local -n items_r="${node_r[items]}"
   for ast_node in "${items_r[@]}"; do
      walk:merge "$ast_node"
   done
}


function merge_identifier {
   local -n node_r="$NODE"
   node_r['symtab']="$SYMTAB"
}


function merge_boolean { :; }
function merge_integer { :; }
function merge_string  { :; }
function merge_path    { :; }
function merge_env_var { :; }
