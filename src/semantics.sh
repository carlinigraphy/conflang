#!/bin/bash
#===============================================================================
# @section                      Dependency tree
# @description
#  Can't typecheck off the AST directly, as some dependent nodes may occur
#  earlier than their dependencies. Example:
#  ```
#  item (str): arr[0];
#  arr: [0, 1];
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
declare -g  DEPENDENCY=
declare -ga UNORDERED_DEPS=()
declare -ga ORDERED_DEPS=()
# UNORDERED_DEPS[] -> DEPTH_MAP{} -> ORDERED_DEPS[]

declare -gA DEPTH_MAP=()
# Mapping of {NODE -> $depth}. Intermediate phase in going from unordered to
# ordered.


function dependency:new {
   local dep="DEP_${1}"
   declare -ga "$dep"
   declare -g  DEPENDENCY="$dep"
   UNORDERED_DEPS+=( "$dep" )
}


function walk:flatten {
   declare -g NODE="$1"
   flatten_"${TYPEOF[$NODE]}"
}


function flatten_program {
   local -n node_r="$NODE"
   local -n container_r="${node_r[container]}"
   local -n items_r="${container_r[items]}"
   for node in "${items_r[@]}" ; do
      walk:flatten "$node"
   done
}


function flatten_decl_section {
   local node="$NODE"
   local -n node_r="$node"

   local symtab="$SYMTAB"
   symtab:from "$node"

   local -n items_r="${node_r[items]}"
   for var_decl in "${items_r[@]}"; do
      walk:flatten "$var_decl"
   done

   declare -g NODE="$node"
   declare -g SYMTAB="$symtab"
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


function flatten_member {
   local -n node_r="$NODE"
   walk:flatten "${node_r[left]}"
   walk:flatten "${node_r[right]}"
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
   for ast_node in "${items_r[@]}"; do
      walk:flatten "$ast_node"
   done
}


function flatten_identifier {
   # Get identifier name.
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
   local -n dep="$DEPENDENCY"
   dep+=( "$target" )
}


function flatten_boolean { :; }
function flatten_integer { :; }
function flatten_string  { :; }
function flatten_path    { :; }
function flatten_env_var { :; }

#────────────────────────────( order dependencies )─────────────────────────────
declare -gi DEPTH=0

function dependency_to_map {
   for dep_node in "${UNORDERED_DEPS[@]}" ; do
      dependency_depth "$dep_node"

      local ast_node="${dep_node/DEP_/}"
      DEPTH_MAP[$ast_node]="$DEPTH"
   done
}


function dependency_depth {
   local -n node_r="$1"
   local -i level="${2:-0}"

   # When we've reached the end of a dependency chain, return the accumulated
   # depth level.
   if ! (( ${#node_r[@]} )) ; then
      DEPTH="$level" ; return
   fi

   (( ++level ))

   local -a sub_levels=()
   for ast_node in "${node_r[@]}" ; do
      dependency_depth "DEP_${ast_node}"  "$level"
      sub_levels+=( "$DEPTH" )
   done

   local -i max="${sub_levels[0]}"
   for n in "${sub_levels[@]}" ; do
      (( max = (n > max)? n : max ))
   done

   declare -g DEPTH="$max"
}


function dependency_sort {
   local -i  i=0  depth=0

   while (( ${#DEPTH_MAP[@]} )) ; do
      for ast_node in "${!DEPTH_MAP[@]}" ; do
         depth="${DEPTH_MAP[$ast_node]}"
         if (( depth == i )) ; then
            unset 'DEPTH_MAP[$ast_node]'
            ORDERED_DEPS+=( "$ast_node" )
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


# Can only hit this as the LHS of a member expression.
#> _: Section.key;   ->   index(Section, key)
function semantics_decl_section {
   local -n node_r="$NODE"
   local -n name_r="${node_r[name]}"

   symtab:get "${name_r[value]}"

   # Need to "return" the resulting
   local -n symbol_r="$SYMBOL"
   declare -g TYPE="${symbol_r[type]}"
}


function semantics_decl_variable {
   local -n node_r="$NODE"
   local -n name_r="${node_r[name]}"
   local name="${name_r[value]}"

   symtab:from "$NODE"
   symtab:get "$name"

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

   if ! type:equality  "$target"  "$actual" ; then
      local -n type_r="${node_r[type]}"
      local -n expr_r="${node_r[expr]}"
      e=( --anchor "${type_r[location]}"
          --caught "${expr_r[location]}"
          'expression does not match the declared type'
      ); raise type_error "${e[@]}"
   fi

   local -n symbol_r="$SYMBOL"
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
   # Types themselves are defined as such:
   #> int = Type('TYPE', subtype: Type('INTEGER'))
   #> str = Type('TYPE', subtype: Type('STRING'))

   local -n outer_type_r="$outer_type"
   type:copy "${outer_type_r[subtype]}"
   local type="$TYPE"
   local -n type_r="$type"

   if [[ ${node_r[subtype]} ]] ; then
      walk:semantics ${node_r[subtype]}
      type_r[subtype]=$TYPE
   fi

   declare -g TYPE="$type"
   declare -g NODE="$node"
}


function semantics_typecast {
   local -n node_r="$NODE"
   walk:semantics ${node_r[type]}
}


function semantics_member {
   local symtab="$SYMTAB"
   local -n node_r="$NODE"

   # node.left is either
   #  - AST(member)
   #  - AST(identifier)
   # Both must set $SYMTAB to point to either the result of the member
   # subscription, or the target symtab of the identifier respectively. it must
   # also set $TYPE to its resulting type.
   walk:semantics "${node_r[left]}"

   local -n right_r="${node_r[right]}"

   #  ┌── doesn't know about dynamically created $_SECTION var.
   # shellcheck disable=SC2154
   if ! type:equality  "$_SECTION"  "$TYPE" ; then
      e=( --anchor "${node_r[location]}"
          --caught "${right_r[location]}"
          'the left hand side must evaluate to a section'
      ); raise type_error "${e[@]}"
   fi

   # Descend to section's scope (from above `walk:semantics`).
   local -n symbol_r="$SYMBOL"
   symtab:from "${symbol_r[node]}"

   local index="${right_r[value]}"
   if ! symtab:strict "$index" ; then
      e=( --anchor "${node_r[location]}"
          --caught "${right_r[location]}"
          "$index"
      ); raise missing_var "${e[@]}"
   fi

   local -n section_r="$SYMBOL"

   # Necessary for an expression using both member & index subscription. E.g.,
   #> _: a.b[0];
   #
   # Need to "return" the result of (a.b) so it can be subscripted by [0]. The
   # symbol holds a reference to the declaration. Need the expression itself.
   local -n result_r="${section_r[node]}"
   declare -g NODE="${result_r[expr]}"

   declare -g TYPE="${section_r[type]}"
   declare -g SYMTAB="$symtab"
}


function semantics_index {
   local -n node_r="$NODE"

   walk:semantics "${node_r[left]}"
   local -n lhs_r="$NODE"

   #  ┌── doesn't know about dynamically created $_LIST var.
   # shellcheck disable=SC2154
   if ! type:shallow_eq  "$_LIST"  "$TYPE" ; then
      e=( --anchor "${node_r[location]}"
          --caught "${lhs_r[location]}"
          'the left hand side must evaluate to a list'
      ); raise type_error "${e[@]}"
   fi

   walk:semantics "${node_r[right]}"
   local -n rhs_r="$NODE"

   #  ┌── doesn't know about dynamically created $_INTEGER var.
   # shellcheck disable=SC2154
   if ! type:equality "$_INTEGER"  "$TYPE" ; then
      e=( --anchor "${node_r[location]}"
          --caught "${rhs_r[location]}"
          'list indexes must evaluate to an integer'
      ); raise type_error "${e[@]}"
   fi

   local index="${rhs_r[value]}"
   local -n items_r="${lhs_r[items]}"
   local rv="${items_r[$index]}"

   if [[ ! "$rv" ]] ; then
      e=( --anchor "${node_r[location]}"
          --caught "${rhs_r[location]}"
          "$rv"
      ); raise index_error "${e[@]}"
   fi

   walk:semantics "$rv"
   declare -g NODE="$rv"
}


function semantics_unary {
   local -n node_r="$NODE"
   walk:semantics ${node_r[right]}

   #  ┌── doesn't know about dynamically created $_INTEGER var.
   # shellcheck disable=SC2154
   if ! type:equality  "$_INTEGER"  "$TYPE" ; then
      local -n right_r="${node_r[right]}"
      e=( --anchor "${node_r[location]}"
          --caught "${right_r[location]}"
          'may only negate integers'
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

   type:copy "$_NONE"
   local prev_type="$TYPE"
   local prev_node
   local cur_node

   for cur_node in "${items_r[@]}" ; do
      walk:semantics "$cur_node"

      if [[ $prev_node ]] && ! type:shallow_eq "$prev_type" "$TYPE" ; then
         local -n current_r="$cur_node"
         local -n previous_r="$prev_node"
         e=( --anchor "${previous_r[location]}"
             --caught "${current_r[location]}"
             'lists must be of the same type'
         ); raise type_error "${e[@]}"
      fi

      local prev_node="$cur_node"
      local prev_type="$TYPE"
   done

   type_r['subtype']="$prev_type"
   declare -g TYPE="$type"
}


function semantics_identifier {
   # Before this stage, we've flattened the AST to an array, and sorted by
   # dependency order. Can safely look up the .type of the target Symbol without
   # worry that it may be uninitialized.

   # Get identifier name.
   local -n node_r="$NODE"
   local name="${node_r[value]}"

   symtab:from "$NODE"
   symtab:get "$name"
   local -n symbol_r="$SYMBOL"

   # Need to set the $NODE to "return" the expression referenced by this
   # variable. Necessary in index/member subscription expressions.
   local -n target_r="${symbol_r[node]}"
   declare -g NODE="${target_r[expr]}"
   declare -g TYPE="${symbol_r[type]}"
}

# shellcheck disable=SC2154
function semantics_path    { declare -g TYPE="$_PATH"    ;}

# shellcheck disable=SC2154
function semantics_boolean { declare -g TYPE="$_BOOLEAN" ;}

# shellcheck disable=SC2154
function semantics_integer { declare -g TYPE="$_INTEGER" ;}

# shellcheck disable=SC2154
function semantics_string  { declare -g TYPE="$_STRING"  ;}

# shellcheck disable=SC2154
function semantics_env_var { declare -g TYPE="$_ANY"     ;}
