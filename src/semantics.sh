#!/bin/bash
#===============================================================================
# @section                      Dependency tree
# @description
#  Can't typecheck off the AST directly, as some dependent nodes may occur
#  earlier than their dependencies. Example:
#  ```
#  item (str): arr[1];
#
#  arr : [0, one];
#  one : 1;
#  ```
#
#  The array `arr` was declared with no type. Until we can walk its expression
#  to determine the "evaluated" type, it's impossible to know if `item` is
#  actually a valid assignment.
#
#  Building a tree of dependencies, and flatting the AST into an ordered list
#  ensures never walking a node before its dependants have been evaluated.
#-------------------------------------------------------------------------------

# @type
declare -g  DEPENDENCIES=
declare -gi _DEP_ARRAY_NUM=0

declare -gA UNORDERED_DEPS=()
declare -ga ORDERED_DEPS=()
# UNORDERED_DEPS{} -> DEPTH_MAP{} -> ORDERED_DEPS[]

declare -gA DEPTH_MAP=()
# Mapping of {NODE -> $depth}. Intermediate phase in going from unordered to
# ordered.

# @set   DEPENDENCIES
# @set   UNORDERED_DEPS{}
function dependency:new {
   local node="$1"
   local deps="_DEP_ARRAY_$(( ++_DEP_ARRAY_NUM ))"
   declare -ga "$deps"
   declare -g  DEPENDENCIES="$deps"
   UNORDERED_DEPS["$node"]="$deps"
}


# @description
#  Calls the appropriate `flatten` function based upon the node type. E.g.,
#  identifiers call `flatten_identifier()`.
#
# @set   NODE
function walk:flatten {
   declare -g NODE="$1"
   flatten_${TYPEOF[$NODE]}
}


function flatten_decl_section {
   local -n node_r="$NODE"
   local -n items_r="${node_r[items]}"
   local node

   for node in "${items_r[@]}"; do
      walk:flatten "$node"
   done
}


function flatten_decl_variable {
   local -n node_r="$NODE"

   dependency:new "$NODE"
   if [[ ${node_r[expr]} ]] ; then
      walk:flatten "${node_r[expr]}"
   fi
}


function flatten_typecast {
   local -n node_r="$NODE"
   walk:flatten "${node_r[expr]}"
}


# @set   TYPE
# @set   SYMTAB
# @set   DEPENDENCIES
function flatten_member {
   local node="$NODE"
   local -n node_r="$node"

   local -n left_r="${node_r[left]}"
   local -n right_r="${node_r[right]}"

   walk:flatten "${node_r[left]}"

   #  ┌── doesn't know about dynamically created $_SECTION var.
   # shellcheck disable=SC2154
   if ! type:eq  "$_SECTION"  "$TYPE" ; then
      e=( --anchor "${node_r[location]}"
          --caught "${left_r[location]}"
          'must evaluate to a section'
      ); raise type_error "${e[@]}"
   fi

   local index="${right_r[value]}"
   if ! symtab:strict "$index" ; then
      e=( --anchor "${node_r[location]}"
          --caught "${right_r[location]}"
          "$index"
      ); raise missing_var "${e[@]}"
   fi

   local -n dep="$DEPENDENCIES"
   local -n symbol_r="$SYMBOL"

   # Ignore sections.
   local target="${symbol_r[node]}" 
   if [[ ! ${TYPEOF[$target]} == decl_section ]] ; then
      dep+=( "$target" )
   fi

   symtab:descend "$index"
}


function flatten_index {
   local -n node_r="$NODE"
   walk:flatten "${node_r[left]}"
   walk:flatten "${node_r[right]}"
}


function flatten_unary {
   local -n node_r="$NODE"
   walk:flatten "${node_r[right]}"
}


function flatten_list {
   local -n node_r="$NODE"
   local -n items_r="${node_r[items]}"
   local node
   for node in "${items_r[@]}"; do
      walk:flatten "$node"
   done
}


function flatten_record {
   local -n node_r="$NODE"
   local -n items_r="${node_r[items]}"
   local node
   for node in "${items_r[@]}"; do
      walk:flatten "$node"
   done
}


# @set   TYPE
# @set   SYMTAB
function flatten_identifier {
   local -n node_r="$NODE"
   local name="${node_r[value]}"

   symtab:from "$NODE"
   if ! symtab:get "$name" ; then
      e=( --anchor "${node_r[location]}"
          --caught "${node_r[location]}"
          "$name"
      ); raise missing_var "${e[@]}"
   fi

   # Add variable target as a dependency.
   local -n symbol_r="$SYMBOL"
   local target="${symbol_r[node]}" 

   local -n target_r="$target"
   declare -g SYMTAB="${target_r[symtab]}"
   declare -g TYPE="${symbol_r[type]}"

   # Ignore sections.
   if [[ ${TYPEOF[$target]} == decl_section ]] ; then
      return
   fi

   # Ignore built-in types, which do not contain a .node ref.
   if [[ ! "$target" ]] ; then
      return
   fi

   local -n dep="$DEPENDENCIES"
   dep+=( "$target" )
}


function flatten_boolean { :; }
function flatten_integer { :; }
function flatten_string  { :; }
function flatten_path    { :; }
function flatten_env_var { :; }

#===============================================================================
# @section                      Order dependencies
# @description
#  Orders `UNORDERED_DEPS{}` array from the `flatten` phase. Iterates each
#  variable declaration, counts the "depth" of its dependencies. Sorta based on
#  minimum -> maximum depth.
#
#-------------------------------------------------------------------------------

declare -gi DEPTH=0
declare -gA DEPTH_VISITED=()

function dependency_to_map {
   local node items
   for node in "${!UNORDERED_DEPS[@]}" ; do
      items="${UNORDERED_DEPS[$node]}" 

      DEPTH_VISITED=()
      DEPTH_VISITED[$node]='yes'

      dependency_depth "$items"
      DEPTH_MAP[$node]="$DEPTH"
   done
}


function dependency_depth {
   local -n items_r="$1"
   local -i level="${2:-0}"

   # When we've reached the end of a dependency chain, return the accumulated
   # depth level.
   if ! (( ${#items_r[@]} )) ; then
      DEPTH="$level" ; return
   fi

   (( ++level ))

   local -a sub_levels=()
   local node
   for node in "${items_r[@]}" ; do
      if [[ ${DEPTH_VISITED[$node]} ]] ; then
         local -n node_r="$node"
         e=( --anchor "${node_r[location]}"
             --caught "${node_r[location]}"
         ); raise circular_reference "${e[@]}"
      fi
      DEPTH_VISITED[$node]='yes'

      dependency_depth "${UNORDERED_DEPS[$node]}"  "$level"
      sub_levels+=( "$DEPTH" )
   done

   local -i max="${sub_levels[0]}"
   local n
   for n in "${sub_levels[@]}" ; do
      (( max = (n > max)? n : max ))
   done

   declare -g DEPTH="$max"
}


function dependency_sort {
   local node
   local -i  i=0  depth=0

   while (( ${#DEPTH_MAP[@]} )) ; do
      for node in "${!DEPTH_MAP[@]}" ; do
         depth="${DEPTH_MAP[$node]}"
         if (( depth == i )) ; then
            unset 'DEPTH_MAP[$node]'
            ORDERED_DEPS+=( "$node" )
         fi
      done
      (( ++i ))
   done
}


#─────────────────────────────( semantic analysis )─────────────────────────────
function walk:semantics {
   declare -g NODE="$1"
   semantics_${TYPEOF[$NODE]}
}


function semantics_decl_variable {
   local -n node_r="$NODE"
   local -n name_r="${node_r[name]}"
   local name="${name_r[value]}"

   symtab:from "$NODE"
   symtab:get "$name"
   local symbol="$SYMBOL"

   # Initially set Type(NONE). Potentially overwritten by the expr.
   type:copy "$_NONE"
   if [[ "${node_r[expr]}" ]] ; then
      walk:semantics "${node_r[expr]}"
   fi
   local actual="$TYPE"

   # As above, initial Type(ANY).
   type:copy "$_ANY"
   if [[ "${node_r[type]}" ]] ; then
      walk:semantics "${node_r[type]}"
   fi
   local target="$TYPE"

   if ! type:eq  "$target"  "$actual" ; then
      local -n type_r="${node_r[type]}"
      local -n expr_r="${node_r[expr]}"
      e=( --anchor "${type_r[location]}"
          --caught "${expr_r[location]}"
          'expression type does not match declared type'
          "$target"  "$actual"
      ); raise type_error "${e[@]}"
   fi

   local -n symbol_r="$symbol"
   symbol_r['type']="$actual"
}


function semantics_type {
   local node="$NODE"
   local -n node_r="$node"
   local -n name_r="${node_r[kind]}"
   local name="${name_r[value]}"

   symtab:get "$name"
   local -n symbol_r="$SYMBOL"
   local outer_type="${symbol_r[type]}"

   local -n outer_type_r="$outer_type"
   type:copy "${outer_type_r[subtype]}"
   local type="$TYPE"
   local -n type_r="$type"

   if [[ ${node_r['next']} ]] ; then
      walk:semantics "${node_r[next]}"
      type_r['next']="$TYPE"
   fi

   if [[ ${node_r['subtype']} ]] ; then
      walk:semantics "${node_r[subtype]}"
      type_r[subtype]="$TYPE"
   elif (( node_r["slots"] )) ; then
      type:copy "$_ANY"
      type_r[subtype]="$TYPE"
   fi

   declare -g TYPE="$type"
}


function semantics_typecast {
   local -n node_r="$NODE"
   walk:semantics "${node_r[type]}"
}


function semantics_member {
   local -n node_r="$NODE"

   local -n left_r="${node_r[left]}"
   local -n right_r="${node_r[right]}"

   walk:semantics "${node_r[left]}"

   local index="${right_r[value]}"
   symtab:strict "$index"

   local -n symbol_r="$SYMBOL"
   declare -g TYPE="${symbol_r[type]}"

   symtab:descend "$index"
}


function semantics_index {
   local -n node_r="$NODE"

   walk:semantics "${node_r[left]}"
   local -n type_r="$TYPE"

   # shellcheck disable=SC2154
   if ! type:shallow_eq  "$_LIST"  "$TYPE" ; then
      local -n rhs_node_r="${node_r[right]}"
      e=( --anchor "${node_r[location]}"
          --caught "${rhs_node_r[location]}"
          'must evaluate to a list'
          "$_LIST"  "$TYPE"
      ); raise type_error "${e[@]}"
   fi

   walk:semantics "${node_r[right]}"

   #  ┌── doesn't know about dynamically created $_INTEGER var.
   # shellcheck disable=SC2154
   if ! type:eq "$_INTEGER"  "$TYPE" ; then
      local -n rhs_node_r="${node_r[right]}"
      e=( --anchor "${node_r[location]}"
          --caught "${rhs_node_r[location]}"
          'list indexes must evaluate to an integer'
          "$_INTEGER"  "$TYPE"
      ); raise type_error "${e[@]}"
   fi

   declare -g TYPE="${type_r[subtype]}"
}


function semantics_unary {
   local -n node_r="$NODE"
   walk:semantics "${node_r[right]}"

   #  ┌── doesn't know about dynamically created $_INTEGER var.
   # shellcheck disable=SC2154
   if ! type:eq  "$_INTEGER"  "$TYPE" ; then
      local -n right_r="${node_r[right]}"
      e=( --anchor "${node_r[location]}"
          --caught "${right_r[location]}"
          'may only negate integers'
          "$_INTEGER"  "$TYPE"
      ); raise type_error "${e[@]}"
   fi

   # If it hasn't exploded, it's an integer.
   type:copy "$_INTEGER"
}


function semantics_list {
   local -n node_r="$NODE"
   local -n items_r="${node_r[items]}"

   # shellcheck disable=SC2154
   type:copy "$_LIST"
   local type="$TYPE"
   local -n type_r="$TYPE"

   # Set initial item type to NONE. Overwritten by the 1st item of the list.
   type:copy "$_NONE"

   local prev_type prev_node
   local cur_node
   for cur_node in "${items_r[@]}" ; do
      walk:semantics "$cur_node"

      if [[ $prev_type ]] && ! type:eq "$prev_type" "$TYPE" --strict ; then
         local -n current_r="$cur_node"
         local -n previous_r="$prev_node"
         e=( --anchor "${previous_r[location]}"
             --caught "${current_r[location]}"
             'lists must be of the same type'
             "$prev_type"  "$TYPE"
         ); raise type_error "${e[@]}"
      fi

      local prev_type="$TYPE"
      local prev_node="$cur_node"
   done

   type_r['subtype']="$TYPE"
   declare -g TYPE="$type"
}


# @description
#  I don't know if this is more hacky than I'd like. What it do:
#
#  Given the base case...
#        rec
#          `-- none
#
#  ...and the standard case...
#        rec
#          `-- type1 ->>- type2 ->>- typeN
#
#  ...the chain of types are connected to each other's `.next` parameter, and
#  tacked onto the parent `rec` type's `.subtype`.
#
#  Problem arises from how to set the first `$TYPE` to the `rec`'s `.subtype`,
#  and the subsequent ones to *it's* `.next`.
#
#  Temporarily just attaching all of them like so:
#        rec ->>- type1 ->>- type2 ->>- typeN
#
#  Then after iterating the subtypes, cut `rec.next`, paste onto `rec.subtype`.
#
function semantics_record {
   local -n node_r="$NODE"
   local -n items_r="${node_r[items]}"

   # shellcheck disable=SC2154
   type:copy "$_RECORD"
   local type="$TYPE"
   local -n type_r="$TYPE"

   local node
   for node in "${items_r[@]}" ; do
      walk:semantics "$node"
      type_r['next']="$TYPE"
      local -n type_r="$TYPE"
   done

   local -n type_r="$type"
   if [[ ${type_r[next]} ]] ; then
      declare -g TYPE="${type_r[next]}"
   else
      type:copy "$_NONE"
   fi

   type_r['subtype']="$TYPE"
   unset 'type_r[next]'

   declare -g TYPE="$type"
}


function semantics_identifier {
   local -n node_r="$NODE"

   symtab:from "$NODE"
   symtab:get "${node_r[value]}"

   local -n symbol_r="$SYMBOL"
   local target="${symbol_r[node]}" 
   local -n target_r="$target"

   declare -g SYMTAB="${target_r[symtab]}"
   declare -g TYPE="${symbol_r[type]}"
}


function semantics_env_var {
   local -n node_r="$NODE"
   local name="${node_r[value]}"

   if [[ ! "${SNAPSHOT[$name]+_}" ]] ; then
      raise missing_env_var "$name"
   fi

   # shellcheck disable=SC2154
   declare -g TYPE="$_ANY"
}

# shellcheck disable=SC2154
function semantics_path    { type:copy "$_PATH"    ;}

# shellcheck disable=SC2154
function semantics_boolean { type:copy "$_BOOLEAN" ;}

# shellcheck disable=SC2154
function semantics_integer { type:copy "$_INTEGER" ;}

# shellcheck disable=SC2154
function semantics_string  { type:copy "$_STRING"  ;}
