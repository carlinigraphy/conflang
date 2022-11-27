#!/bin/bash

#───────────────────────────────( merge trees )─────────────────────────────────
# After generating the symbol tables for the parent & child, iterate over the
# parent's, merging in nodes. I'm not 100% sure if this should be in the
# compiler.

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
function type_equality {
   local -n t1_r="$1"

   if [[ ${t1_r[kind]} == 'ANY' ]] ; then
      return 0
   fi

   # In the case of...
   #  t1(type: list, subtype: any)
   #  t2(type: list, subtype: None)
   # ...the first type_equality() on their .type will match, but the second must
   # not throw an exception. It is valid to have a missing (or different) type,
   # if the principal type is ANY.
   [[ "$2" ]] || return 1
   local -n t2_r="$2"

   if [[ ${t1_r[kind]} != ${t2_r[kind]} ]] ; then
      return 1
   fi

   if [[ ${t1_r[subtype]} ]] ; then
      type_equality "${t1_r[subtype]}" "${t2_r[subtype]}"
      return $?
   fi

   return 0
}


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
