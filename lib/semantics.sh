#!/bin/bash

function mk_metatype {
   local name="$1"
   local kind="$2"
   local complex="$3"

   mk_type
   local -- type="$TYPE"
   local -n type_r="$TYPE"
   type_r['kind']="$kind"

   # The presence of a set `.subtype` property defines a "complex" type.
   if [[ "$complex" ]] ; then
      type_r['subtype']=''
   fi

   # Example: _BOOLEAN=_TYPE_12. Useful in the `semantics_*` functions as a
   # copy_type() target, e.g.,  `copy_type $_BOOLEAN`.
   declare -g "_${kind}"="$TYPE"

   # Create Type representing Types.
   mk_type
   local -- metatype="$TYPE"
   local -n metatype_r="$TYPE"
   metatype_r['kind']='TYPE'
   metatype_r['subtype']="$type"

   mk_symbol
   local -n symbol_r="$SYMBOL"
   symbol_r['type']="$metatype"
   symbol_r['name']="$name"

   declare -g TYPE="$metatype"
}


function populate_globals {
   local -A primitive=(
      [any]='ANY'
      #[fn]='FUNCTION'
      [int]='INTEGER'
      [str]='STRING'
      [bool]='BOOLEAN'
      [path]='PATH'
      [section]='SECTION'
   )

   local -A complex=(
      [type]='TYPE'
      [array]='ARRAY'
   )

   # Create symbols for primitive types.
   for name in "${!primitive[@]}" ; do
      mk_metatype "$name"  "${primitive[$name]}"
      symtab set "$SYMBOL"
   done

   # Create symbols for complex types.
   for name in "${!complex[@]}" ; do
      mk_metatype "$name"  "${complex[$name]}"  'complex'
      symtab set "$SYMBOL"
   done
}


#───────────────────────────────( symbol table )────────────────────────────────
declare -- SYMTAB=
declare -i SYMTAB_NUM=0

declare -A SYMTAB_PARENT=()
# Rather than the traditional stack of symbol tables that we push & pop from,
# a map of each symtab to its parent is easier to implement in Bash. Less
# nonsense.

# Symbol table API. Directly calls sub-commands:
#  new()       :: creates new symtab, assigns previous one as its parent.
#  get(key)    :: recursively searches upward for Symbol identified by $key.
#  strict(key) :: searches only current symtab for Symbol identified by $key.
#  set(symbol) :: sets ${symbol[name]} -> $symbol in current symtab
#  from(node)  :: sets global $SYMTAB pointer to that referenced in $node
#
function symtab {
   local cmd="$1" ; shift
   _symtab_"$cmd" "$@"
}

# new()  :: creates new symtab, assigns previous one as its parent.
function _symtab_new {
   (( ++SYMTAB_NUM ))
   local symtab="SYMTAB_${SYMTAB_NUM}"
   local old_symtab="$SYMTAB"

   declare -gA "$symtab"
   declare -g  SYMTAB="$symtab"
   SYMTAB_PARENT[$symtab]="$old_symtab"

   # Without a value, this isn't glob matched by a ${!_SYMTAB_*}
   local -n s="$symtab" ; s=()
}


# get(key)  :: recursively searches upward for Symbol identified by $key.
function _symtab_get {
   local name="$1"

   local symtab="$SYMTAB" ; local -n symtab_r="$symtab"
   local parent="${SYMTAB_PARENT[$symtab]}"

   local symbol="${symtab_r[$name]}"
   declare -g SYMBOL="$symbol"

   if [[ ! "$SYMBOL" && "$parent" ]] ; then
      declare -g SYMTAB="$parent"
      _symtab_get "$name"
   fi

   # Return to the original symbol table.
   declare -g SYMTAB="$symtab"
   [[ "$SYMBOL" ]]
}


# strict(key)  :: searches only current symtab for Symbol identified by $key.
function _symtab_strict {
   local -- name="$1"
   local -- symtab="$SYMTAB"
   local -n symtab_r="$symtab"

   declare -g SYMBOL="${symtab_r[$name]}"
   [[ "$SYMBOL" ]]
}


# set(symbol)  :: sets ${symbol[name]} -> $symbol in current symtab
function _symtab_set {
   local -- symbol="$1"
   local -n symbol_r="$symbol"
   local -- name="${symbol_r[name]}"

   local -n symtab_r="$SYMTAB"
   symtab_r[$name]="$symbol"
}


# from(node)  :: sets global $SYMTAB pointer to that referenced in $node
function _symtab_from {
   local -n node_r="$1"
   declare -g SYMTAB="${node_r[symtab]}"
}


declare -- SYMBOL=
declare -i SYMBOL_NUM=${TYPE_NUM:-0}

function mk_symbol {
   (( ++SYMBOL_NUM ))
   local   --  sname="SYMBOL_${SYMBOL_NUM}"
   declare -gA $sname
   declare -g  SYMBOL=$sname
   local   -n  symbol=$sname

   symbol['type']=    #> TYPE
   symbol['node']=    #> NODE
   symbol['symtab']=  #> SYMTAB

   symbol['name']=    #> str
   # While it isn't really required, it's substantially easier if we have a
   # string name, rather than needing to pull it from the symbol.node.name.value

   symbol['required']=
   # Variable declaration symbols are `required' if its NODE has no expression.
   # A Section is considered to be `required' if *any* of its children are
   # required. This is only needed when enforcing constraints upon a child file.
}


declare -- TYPE=
declare -i TYPE_NUM=${TYPE_NUM:-0}

function mk_type {
   (( ++TYPE_NUM ))

   local type="TYPE_${TYPE_NUM}"
   declare -gA $type
   declare -g  TYPE="$type"

   local -n t="$type"
   t['kind']=         #-> str
   #type['subtype']=  #-> Type
   # .subtype is only present in complex types. It is unset in primitive types,
   # which allows for throwing errors in semantic analysis for invalid subtypes.
}


function copy_type {
   local -n t0_r="$1"

   mk_type
   local -- t1="$TYPE"
   local -n t1_r="$TYPE"
   t1_r['kind']="${t0_r[kind]}"

   if [[ "${t0_r['subtype']}" ]] ; then
      copy_type "${t0_r['subtype']}"
      t1_r['subtype']="$TYPE"
   elif [[ "${t0_r['subtype']+_}" ]] ; then
      # For complex types with a not-yet-set subtype.
      t1_r['subtype']=''
   fi

   declare -g TYPE="$t1"
}


function walk_symtab {
   declare -g NODE="$1"
   symtab_"${TYPEOF[$NODE]}"
}


function symtab_decl_section {
   local -n node_r="$NODE"

   mk_symbol
   local -- symbol="$SYMBOL"
   local -n symbol_r="$SYMBOL"

   # Save node name in symbol.
   symbol_r['node']="$NODE"

   # Save section name in symbol.
   local -n ident_r="${node_r[name]}"
   symbol_r['name']="${ident_r[value]}"

   if symtab strict "$name" ; then
      raise name_collision "$name"
   else
      symtab set "$symbol"
   fi

   #  ┌── doesn't know about dynamically created $_SECTION var.
   # shellcheck disable=SC2154
   copy_type "$_SECTION"
   symbol_r['type']="$TYPE"

   local symtab="$SYMTAB"
   symtab new

   # Save reference to the symbol table at the current scope. Needed in the
   # linear evaluation phase.
   node_r['symtab']="$SYMTAB"

   local -n items_r="${node_r[items]}"
   for ast_node in "${items_r[@]}"; do
      walk_symtab "$ast_node"
   done

   # Check if this section is `required'. If any of its children are required,
   # it too must be present in a child file.
   local -n symtab_r="$symtab"
   for sym in "${symtab_r[@]}" ; do
      local -n sym_r="$sym"

      if [[ "${sym_r[required]}" ]] ; then
         symbol_r['required']='yes'
         break
      fi
   done

   declare -g SYMTAB="$symtab"
}


function symtab_decl_variable {
   local -n node_r="$NODE"

   # Save reference to the symbol table at the current scope. Needed in the
   # linear compilation phase.
   node_r['symtab']="$SYMTAB"

   mk_symbol
   local -- symbol="$SYMBOL"
   local -n symbol_r="$symbol"

   # Save node name in symbol.
   symbol_r['node']="$NODE"

   # Save variable name in symbol.
   local -- identifier="${node_r[name]}"
   local -n identifier_r="$identifier"
   local -- name="${identifier_r[value]}"
   symbol_r['name']="$name"

   if symtab strict "$name" ; then
      raise name_collision "$name"
   else
      symtab set "$symbol"
   fi

   # Set Type('ANY') if unspecified.
   if [[ ${node_r['type']} ]] ; then
      walk_symtab "${node_r['type']}"
      symbol_r['type']="$TYPE"
   else
      # shellcheck disable=SC2154
      copy_type "$_ANY"
      symbol_r['type']="$TYPE"
   fi

   if [[ ${node_r['expr']} ]] ; then
      # Still must descend into expression, as to make references to the symtab
      # in identifier nodes.
      walk_symtab "${node_r['expr']}"
   else
      # Variables are `required' when they do not contain an expression. A
      # child must fill in the value.
      symbol_r[required]='yes'
   fi
}


function symtab_typedef {
   local -n node_r="$NODE"

   local -n name_r="${node_r[kind]}"
   local -- name="${name_r[value]}"
   symtab get "$name"

   local -n symbol_r="$SYMBOL"
   local -- outer_type="${symbol_r[type]}"
   # Types themselves are defined as such:
   #> int = Type('TYPE', subtype: Type('INTEGER'))
   #> str = Type('TYPE', subtype: Type('STRING'))

   if [[ ! "$outer_type" ]] ; then
      raise undefined_type "${node_r[kind]}"  "$name"
   fi

   #  ┌── doesn't know about dynamically created $_TYPE (confused with $TYPE).
   # shellcheck disable=SC2153,SC2154
   if ! type_equality  "$_TYPE"  "$outer_type" ; then
      raise not_a_type "${node_r[kind]}" "$name"
   fi

   local -n outer_type_r="$outer_type"
   copy_type "${outer_type_r[subtype]}"
   local type="$TYPE"
   local -n type_r="$type"

   if [[ "${node_r[subtype]}" ]] ; then
      # See ./doc/truth.sh for an explanation on the test below. Checks if the
      # type has an unset .subtype field (indicating non-complex type).
      if [[ ! "${type[subtype]+_}" ]] ; then
         local loc="${node_r[subtype]}"
         local msg="primitive types are not subscriptable."
         raise type_error "$loc" "$msg"
      fi

      walk_symtab "${node_r[subtype]}"
      type_r['subtype']="$TYPE"
   fi

   declare -g TYPE="$type"
}


function symtab_member {
   local -n node_r="$NODE"
   walk_symtab "${node_r[left]}"
   walk_symtab "${node_r[right]}"
}


function symtab_index {
   local -n node_r="$NODE"
   walk_symtab "${node_r[left]}"
   walk_symtab "${node_r[right]}"
}


function symtab_unary {
   local -n node_r="$NODE"
   walk_symtab "${node_r[right]}"
}


function symtab_array {
   local -n node_r="$NODE"
   for ast_node in "${node_r[@]}" ; do
      walk_symtab "$ast_node"
   done
}


function symtab_identifier {
   local -n node_r="$NODE"
   node_r['symtab']="$SYMTAB"
}

function symtab_boolean { :; }
function symtab_integer { :; }
function symtab_string  { :; }
function symtab_path    { :; }
function symtab_env_var { :; }

#───────────────────────────────( merge trees )─────────────────────────────────
# After generating the symbol tables for the parent & child, iterate over the
# parent's, merging in nodes. I'm not 100% sure if this should be in the
# compiler.
#
# Merging is only necessary if the parent has %constrain statements.

# Gives friendly means of reporting to the user where an error has occurred.
# As we descend into each symtab, push its name to the stack. Print by doing a
# FQ_LOCATION.join('.'). Used in lib/errors.sh
declare -a FQ_LOCATION=()


function merge_symtab {
   local -n parent=$1
   local -n parent_symtab=$2
   local -n child_symtab=$3

   # We iterate over the parent symtab. So we're guaranteed to hit every key
   # there. The child symtab may contain *extra* keys that we need to merge in.
   # Every time we match a key from the parent->child, we can pop it from this
   # copy. Anything left is a duplicate that must be merged.
   local -A overflow=()
   for k in "${!child_symtab[@]}" ; do
      overflow["$k"]=
   done

   for p_key in "${!parent_symtab[@]}" ; do
      if [[ "$p_key" != '%inline' ]] ; then
         FQ_LOCATION+=( "$p_key" )
      fi

      # Parent Symbol.
      local -- p_sym_name="${parent_symtab[$p_key]}"
      local -n p_sym=$p_sym_name
      local -- p_node=${p_sym[node]}

      # Parent type information.
      local -- p_type_name="${p_sym[type]}"
      local -n p_type=$p_type_name

      # Child Symbol.
      # The child symbol may not necessarily exist. These cases, and the error
      # reporting, are both handled in their respective functions:
      # `merge_variable`, `merge_section`.
      local -- c_sym_name="${child_symtab[$p_key]}"

      # shellcheck disable=SC2184
      unset overflow["$p_key"]
      # Pop reference to child symbol from the `overflow[]` copy. Will allow
      # us to check at the end if there are leftover keys that are defined in
      # the child, but not in the parent.

      if [[ "${p_type[kind]}" == 'SECTION' ]] ; then
         merge_section  "$p_sym_name" "$c_sym_name"
      else
         merge_variable "$p_sym_name" "$c_sym_name"
      fi

      FQ_LOCATION=( "${FQ_LOCATION[@]::${#FQ_LOCATION[@]}-1}" )
   done

   # Any additional keys from the child need to be copied into both...
   #  1. the parent's .items[] array
   #  2. the parent's symbol table
   for c_key in "${!overflow[@]}" ; do
      # Add to symtab.
      parent_symtab[$c_key]="${child_symtab[$c_key]}"

      local -n c_sym="${child_symtab[$c_key]}"
      local -n items="${parent[items]}"

      # Add to items.
      items+=( "${c_sym[node]}" )
   done
}


function merge_section {
   # It's easier to think about the conditions in which a merge *fails*. A
   # section merge fails when:
   #  1. It is required in the parent, and missing in the child
   #  2. It is of a non-Section type in the child

   local -n p_sym_r="$1"
   local -- c_sym="$2"

   # case 1.
   # Child section is missing, but was required in the parent.
   if [[ ! "$c_sym" ]] ; then
      if [[ "${p_sym_r[required]}" ]] ; then
         raise missing_required
      else
         return 0  # if not required, can ignore.
      fi
   fi

   local -n c_sym_r="$c_sym"
   local -n c_type_r="${c_sym_r[type]}"

   # case 2.
   # Found child node under the same identifier, but not a Section.
   if [[ ${c_type_r[kind]} != 'SECTION' ]] ; then
      raise symbol_mismatch
   fi

   merge_symtab "${p_sym_r[node]}"  "${p_sym_r[symtab]}"  "${c_sym_r[symtab]}"
   #               ^-- parent node     ^-- parent symtab     ^-- child symtab
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
   local -- c_sym="$2"

   # case 1a.
   if [[ ! "$c_sym" ]] ; then
      if [[ "${p_sym_r[required]}" ]] ; then
         raise missing_required
      else
         return 0  # if not required, can ignore.
      fi
   fi

   local -n c_sym_r="$c_sym"

   # case 2a.
   # Expecting a variable declaration, child is actually a Section.
   local -n c_type_r="${c_sym_r[type]}"
   if [[ "${c_type_r[kind]}" == 'SECTION' ]] ; then
      raise symbol_mismatch
   fi

   # case 2b.
   # The type of the child must defer to the type of the parent.
   if ! merge_type "${p_sym_r[type]}" "${c_sym_r[type]}" ; then
      raise symbol_mismatch
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

   # TODO: feature
   # This is where we would also append the directive/test context information
   # over. But it doesn't exist yet.
}


function merge_type {
   # This it's not a semantic typecheck. It only enforces the deference in a
   # child's typedef. The child must either...
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


#─────────────────────────────( semantic analysis )─────────────────────────────
function type_equality {
   local -n t1_r="$1"

   if [[ ${t1_r[kind]} == 'ANY' ]] ; then
      return 0
   fi

   # In the case of...
   #  t1(type: array, subtype: any)
   #  t2(type: array, subtype: None)
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


function walk_semantics {
   declare -g NODE="$1"
   semantics_${TYPEOF[$NODE]}
}


function semantics_decl_section {
   local -n node_r="$NODE"

   local symtab="$SYMTAB"
   symtab from "$NODE"

   local -n items_r="${node_r[items]}"
   for ast_node in "${items_r[@]}"; do
      walk_semantics "$ast_node"
   done

   declare -g SYMTAB="$symtab"
}


function semantics_decl_variable {
   local -- save=$NODE
   local -n node=$save
   local -n name="${node[name]}"

   if [[ "${node[type]}" ]] ; then
      # Sets target type. The type of the expression should match the type of
      # the typedef in the symbol table.
      walk_semantics "${node[type]}"
      local target="$TYPE"
   fi

   if [[ "${node[expr]}" ]] ; then
      walk_semantics "${node[expr]}"
      local actual="$TYPE"
   fi

   # Only able to test if the declared type matches the actual type... if an
   # intended type was declared.
   if [[ "$target" ]] && ! type_equality  "$target"  "$actual" ; then
      raise type_error "${node[expr]}"
   fi

   declare -g NODE=$save
}


function semantics_typedef {
   local -- node="$NODE"
   local -n node_r="$node"

   local -n name_r="${node_r[kind]}"
   local -- name="${name_r[value]}"
   symtab get "$name"

   local -n symbol_r="$SYMBOL"
   local -- outer_type="${symbol_r[type]}"
   # Types themselves are defined as such:
   #> int = Type('TYPE', subtype: Type('INTEGER'))
   #> str = Type('TYPE', subtype: Type('STRING'))

   local -n outer_type_r="$outer_type"
   copy_type "${outer_type_r[subtype]}"
   local -- type="$TYPE"
   local -n type_r="$type"

   if [[ ${node_r[subtype]} ]] ; then
      walk_semantics ${node_r[subtype]}
      type_r[subtype]=$TYPE
   fi

   declare -g TYPE="$type"
   declare -g NODE="$node"
}


function semantics_typecast {
   local -n node="$NODE"
   walk_semantics ${node[typedef]}
}


function semantics_member {
   local -n node_r="$NODE"

   # TODO: node.left may be another member expression and not have a symtab.
   #       Need to rethink this section. Draft it out on paper.
   local symtab="$SYMTAB"
   symtab from "${node_r[left]}"
   walk_semantics "${node_r[left]}"

   #  ┌── doesn't know about dynamically created $_SECTION var.
   # shellcheck disable=SC2154
   if ! type_equality  "$_SECTION"  "$TYPE" ; then
      local msg='the left hand side must evaluate to a section.'
      raise type_error "${node_r[left]}"  "$msg"
   fi

   # Descend to section's symtab (from above `walk_semantics`).
   local -n symbol_r="$SYMBOL"
   symtab from "${symbol_r[node]}"

   local -n right_r="${node_r[right]}"
   local -- index="${right_r[value]}"

   if symtab strict "$index" ; then
      local -n section_r="$SYMBOL"
   else
      raise missing_var "$index"
   fi

   local rv="${section_r[node]}"
   walk_semantics "$rv"

   declare -g SYMTAB="$symtab"
   declare -g NODE="$rv"
}


function semantics_index {
   local -n node_r="$NODE"

   walk_semantics "${node_r[left]}"
   local -n lhs_r="$NODE"

   #  ┌── doesn't know about dynamically created $_ARRAY var.
   # shellcheck disable=SC2154
   if ! type_equality  "$_ARRAY"  "$TYPE" ; then
      local msg='the left hand side must evaluate to an section.'
      raise type_error "${node_r[left]}"  "$msg"
   fi

   walk_semantics "${node_r[right]}"
   local -n rhs_r="$NODE"

   #  ┌── doesn't know about dynamically created $_INTEGER var.
   # shellcheck disable=SC2154
   if ! type_equality "$_INTEGER"  "$TYPE" ; then
      local loc="${node_r[right]}"
      local msg="array indexes must evaluate to an integer."
      raise type_error  "$loc"  "$msg"
   fi

   local -- index="${rhs_r[value]}"
   local -- rv="${lhs_r[$index]}"

   if [[ ! "$rv" ]] ; then
      raise index_error "$index"
   fi

   walk_semantics "$rv"
   declare -g NODE="$rv"
}


function semantics_unary {
   local -n node_r="$NODE"
   walk_semantics ${node_r[right]}

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


function semantics_array {
   local -n node_r="$NODE"

   # shellcheck disable=SC2154
   copy_type "$_ARRAY"
   local -- type="$TYPE"
   local -n type_r="$TYPE"

   # If the target type is specific (e.g., array:str), the actual type must
   # conform to that.
   local -A types_found=()
   for ast_node in "${node_r[@]}" ; do
      walk_semantics "$ast_node"
      local -n subtype_r=$TYPE
      local -- subtype="${subtype_r[kind]}"

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
   # Get identifier name.
   local -n node_r="$NODE"
   local -- name="${node_r[value]}"

   symtab from "$NODE"
   if ! symtab get "$name" ; then
      raise missing_var "$name"
   fi

   local -n symbol_r="$SYMBOL"
   copy_type "${symbol_r[type]}"

   # Need to set the $NODE to "return" the expression referenced by this
   # variable. Necessary in index/member subscription expressions.
   local -n target_r="${symbol_r[node]}"
   declare -g NODE="${target_r[expr]}"
}


# shellcheck disable=SC2154
function semantics_path    { copy_type "$_PATH"    ;}

# shellcheck disable=SC2154
function semantics_boolean { copy_type "$_BOOLEAN" ;}

# shellcheck disable=SC2154
function semantics_integer { copy_type "$_INTEGER" ;}

# shellcheck disable=SC2154
function semantics_string  { copy_type "$_STRING"  ;}
