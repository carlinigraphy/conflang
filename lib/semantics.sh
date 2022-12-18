#!/bin/bash

#─────────────────────────────( dependency tree )───────────────────────────────
# Can't typecheck off the AST directly, as some dependent nodes may occur
# earlier than their dependencies. Example:
#
#> item (str): arr[0];
#> arr: [0, 1];
#
# The array `arr` was declared with no type. Until we can walk its expression to
# determine the "evaluated" type, it's impossible to know if `item` is actually
# a valid assignment.
#
# Building a tree of dependencies, and flatting the AST into an ordered list
# ensures never walking a note before its dependants have been evaluated first.

declare -g DEPENDENCY=
# Current DEP_$n node we're in.

declare -gA DEPTH_MAP=()
# Mapping of {NODE_$n -> $depth}. Intermediate phase in going from unordered to
# ordered.

declare -ga UNORDERED_DEPS=()
declare -ga ORDERED_DEPS=()
# UNORDERED_DEPS[] -> DEPTH_MAP{} -> ORDERED_DEPS[]


function mk_dependency {
   local dep="DEP_${1}"
   declare -ga "$dep"
   declare -g  DEPENDENCY="$dep"
   UNORDERED_DEPS+=( "$dep" )
}


function walk:flatten {
   declare -g NODE="$1"
   flatten_"${TYPEOF[$NODE]}"
}


function flatten_decl_section {
   local node="$NODE"
   local -n node_r="$node"

   local symtab="$SYMTAB"
   symtab from "$node"

   local -n items_r="${node_r[items]}"
   for var_decl in "${items_r[@]}"; do
      walk:flatten "$var_decl"
   done

   declare -g NODE="$node"
   declare -g SYMTAB="$symtab"
}


function flatten_decl_variable {
   local -n node_r="$NODE"

   mk_dependency "$NODE"
   if [[ -n ${node_r[expr]} ]] ; then
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

   if ! symtab get "$name" ; then
      e=( missing_var
         --anchor "${node_r[location]}"
         --caught "${node_r[location]}"
         "$name"
      ); raise "${e[@]}"
   fi

   # Add variable target as a dependency.
   local -n symbol_r="$SYMBOL"
   local target="${symbol_r[node]}"
   local -n dep="$DEPENDENCY"
   dep+=( "$target" )

   symtab from "$target"
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

   symtab get "${name_r[value]}"

   # Need to "return" the resulting
   local -n symbol_r="$SYMBOL"
   declare -g TYPE="${symbol_r[type]}"
}


function semantics_decl_variable {
   # The Symbol.type will be set to the "evaluated" type. If there is a type,
   # the expression's type must evaluate to *at least* the requirements of the
   # declared type, though can be more specific.
   #
   #> arr (list): [0, 1];
   #> # declared: Type('LIST')
   #> # actual:   Type('LIST', subtype: Type(INTEGER))

   local -n node_r="$NODE"
   local -n name_r="${node_r[name]}"
   local name="${name_r[value]}"

   symtab from "$NODE"
   symtab get "$name"

   # Initially set Type(ANY). Potentially overwritten by the expr.
   declare -g TYPE="$_ANY"
   if [[ "${node_r[expr]}" ]] ; then
      walk:semantics "${node_r[expr]}"
   fi
   local actual="$TYPE"

   # As above, initial Type(ANY).
   if [[ "${node_r[type]}" ]] ; then
      walk:semantics "${node_r[type]}"
   fi
   local target="$TYPE"

   if ! type_equality  "$target"  "$actual" ; then
      local -n type_r="${node_r[type]}"
      local -n expr_r="${node_r[expr]}"

      e=( type_error
         --anchor "${type_r[location]}"
         --caught "${expr_r[location]}"
      ); raise "${e[@]}"
   fi

   local -n symbol_r="$SYMBOL"
   symbol_r['type']="$actual"
}


function semantics_type {
   local node="$NODE"
   local -n node_r="$node"
   local -n name_r="${node_r[kind]}"
   local name="${name_r[value]}"

   symtab get "$name"
   local -n symbol_r="$SYMBOL"
   local outer_type="${symbol_r[type]}"
   # Types themselves are defined as such:
   #> int = Type('TYPE', subtype: Type('INTEGER'))
   #> str = Type('TYPE', subtype: Type('STRING'))

   local -n outer_type_r="$outer_type"
   copy_type "${outer_type_r[subtype]}"
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
   if ! type_equality  "$_SECTION"  "$TYPE" ; then
      e=( type_error
         --anchor "${node_r[location]}"
         --caught "${right_r[location]}"
         'the left hand side must evaluate to a section'
      ); raise "${e[@]}"
   fi

   # Descend to section's scope (from above `walk:semantics`).
   local -n symbol_r="$SYMBOL"
   symtab from "${symbol_r[node]}"

   local index="${right_r[value]}"
   if ! symtab strict "$index" ; then
      raise
      e=( missing_var
         --anchor "${node_r[location]}"
         --caught "${right_r[location]}"
         "$index"
      ); raise "${e[@]}"
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
   if ! type_equality  "$_LIST"  "$TYPE" ; then
      local msg='the left hand side must evaluate to an list.'
      raise type_error "${node_r[left]}"  "$msg"
   fi

   walk:semantics "${node_r[right]}"
   local -n rhs_r="$NODE"

   #  ┌── doesn't know about dynamically created $_INTEGER var.
   # shellcheck disable=SC2154
   if ! type_equality "$_INTEGER"  "$TYPE" ; then
      local loc="${node_r[right]}"
      local msg="list indexes must evaluate to an integer."
      raise type_error  "$loc"  "$msg"
   fi

   local index="${rhs_r[value]}"
   local -n items_r="${node_r[items]}"
   local rv="${items_r[$index]}"

   if [[ ! "$rv" ]] ; then
      raise index_error "$index"
   fi

   walk:semantics "$rv"
   declare -g NODE="$rv"
}


function semantics_unary {
   local -n node_r="$NODE"
   walk:semantics ${node_r[right]}

   #  ┌── doesn't know about dynamically created $_INTEGER var.
   # shellcheck disable=SC2154
   if ! type_equality  "$_INTEGER"  "$TYPE" ; then
      local loc="${node_r[right]}"
      local msg="may only negate integers."
      raise type_error  "$loc"  "$msg"
   fi

   # If it hasn't exploded, it's an integer.
   copy_type "$_INTEGER"
}


function semantics_list {
   local -n node_r="$NODE"
   local -n items_r="${node_r[items]}"

   # shellcheck disable=SC2154
   copy_type "$_LIST"
   local type="$TYPE"
   local -n type_r="$TYPE"

   # If the target type is specific (e.g., list[str]), the actual type must
   # conform to that.
   local -A types_found=()
   for ast_node in "${items_r[@]}" ; do
      walk:semantics "$ast_node"
      local -n subtype_r=$TYPE
      local subtype="${subtype_r[kind]}"

      type_r['subtype']="$TYPE"
      # For now we assume the array will have matching types throughout. If it
      # does, we don't have touch this. If we're wrong, we append each found
      # distinct type to `types_found[]`. If >1, set the subtype to ANY instead.

      types_found[$subtype]='true'
   done

   if [[ ${#types_found[@]} -gt 1 ]] ; then
      #  ┌── doesn't know about dynamically created $_ANY var.
      # shellcheck disable=SC2154
      copy_type "$_ANY"
      type_r['subtype']="$TYPE"
   fi

   declare -g TYPE="$type"
}


function semantics_identifier {
   # Before this stage, we've flattened the AST to an array, and sorted by
   # dependency order. Can safely look up the .type of the target Symbol without
   # worry that it may be uninitialized.

   # Get identifier name.
   local -n node_r="$NODE"
   local name="${node_r[value]}"

   symtab from "$NODE"
   symtab get "$name"
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
