#!/bin/bash
#===============================================================================
# @section                        Symbol table trees
# @description
#  Rather than the traditional stack of symbol tables that we push & pop from,
#  a map of each symtab to its parent is easier to implement in Bash. Less
#  nonsense.
#-------------------------------------------------------------------------------

# symtab()
# @description
#  Symbol table API. Directly calls sub-commands:
#  - `new()`       :: create new symtab, assigns previous one as its parent
#  - `get(key)`    :: recursively search upward for Symbol identified by `$key`
#  - `strict(key)` :: search only current symtab for Symbol identified by `$key`
#  - `set(symbol)` :: set `${symbol[name]}` -> `$symbol` in current symtab
#  - `from(node)`  :: set global `$SYMTAB` pointer to that referenced in $node
#
#  The first argument is the sub-command to call. Additional arguments are
#  passed to that command.
#
#  Example:
#  ```bash
#  symtab get "key"
#  #--^ calls `_symtab_get key`
#  ```
#
# @arg   $1    :str     Sub-command to call
function symtab {
   local cmd="$1" ; shift
   _symtab_"$cmd" "$@"
}

# new()  :: creates new symtab
function _symtab_new {
   (( ++_SYMTAB_NUM ))
   local symtab="SYMTAB_${_SYMTAB_NUM}"
   declare -gA "$symtab"
   declare -g  SYMTAB="$symtab"

   if [[ "$1" == --parent ]] ; then
      SYMTAB_PARENT[$symtab]="$2"
   fi

   # Without a value, this isn't glob matched by ${!_SYMTAB_*} expansion
   local -n s="$symtab" ; s=()
}


# @set   SYMBOL
# @set   SYMTAB
# @set   SYMTAB_PARENT{}
# @set   TYPE
# @noargs
function _symtab_init_globals {
   (( ++_SYMTAB_NUM ))
   local symtab="SYMTAB_${_SYMTAB_NUM}"
   declare -gA "$symtab"
   declare -g SYMTAB="$symtab"

   local -A primitive=(
      [any]='ANY'
      [int]='INTEGER'
      [str]='STRING'
      [bool]='BOOLEAN'
      [path]='PATH'
      [%section]='SECTION'
      # User isn't allowed to declare a section. They're a logical grouping,
      # not an expression.
   )

   local -A complex=(
      [type]='TYPE'
      [list]='LIST'
      [rec]='RECORD'
   )

   # Create symbols for primitive types.
   for short in "${!primitive[@]}" ; do
      local long="${primitive[$short]}"
      type:new_meta "$short"  "$long"
      symtab set "$SYMBOL"
      declare -g "_${long}"="$TYPE"
   done

   # Create symbols for complex types.
   for short in "${!complex[@]}" ; do
      local long="${complex[$short]}"
      type:new_meta "$short"  "$long"  'complex'
      symtab set "$SYMBOL"
      declare -g "_${long}"="$TYPE"
   done
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
   local name="$1"
   local symtab="$SYMTAB"
   local -n symtab_r="$symtab"

   declare -g SYMBOL="${symtab_r[$name]}"
   [[ "$SYMBOL" ]]
}


# set(symbol)  :: sets ${symbol[name]} -> $symbol in current symtab
function _symtab_set {
   local symbol="$1"
   local -n symbol_r="$symbol"
   local name="${symbol_r[name]}"

   local -n symtab_r="$SYMTAB"
   symtab_r[$name]="$symbol"
}


# from(node)  :: sets global $SYMTAB pointer to that referenced in $node
function _symtab_from {
   local -n node_r="$1"
   declare -g SYMTAB="${node_r[symtab]}"
}


function mk_symbol {
   (( ++_SYMBOL_NUM ))
   local symbol="SYMBOL_${_SYMBOL_NUM}"
   declare -gA "$symbol"
   declare -g SYMBOL="$symbol"

   local -n symbol_r="$symbol"
   symbol_r['type']=    #> TYPE
   symbol_r['node']=    #> NODE
   symbol_r['name']=    #> str
   # While it isn't really required, it's substantially easier if we have a
   # string name, rather than needing to pull it from the symbol.node.name.value
}


#===============================================================================
# @section                       Type functions
#-------------------------------------------------------------------------------

function type:new {
   local complex="$1"

   (( ++_TYPE_NUM ))
   local type="TYPE_${_TYPE_NUM}"
   declare -gA "$type"
   declare -g  TYPE="$type"

   local -n t_r="$type"
   t_r['kind']=''          #< :str
   t_r['params']=''        #< :TYPE, initial node of a paramlist
   t_r['next']=''          #< :TYPE, subsequent node of a paramlist

   if [[ "$complex" ]] ; then
      t_r['complex']='yes'
   fi
}


function type:new_meta {
   local name="$1"
   local kind="$2"
   local complex="$1"

   type:new "$complex"
   local type="$TYPE"
   local -n type_r="$TYPE"
   type_r['kind']="$kind"

   # Create Type representing Types.
   type:new 'complex'
   local metatype="$TYPE"
   local -n metatype_r="$TYPE"
   metatype_r['kind']='TYPE'
   metatype_r['params']="$type"

   mk_symbol
   local -n symbol_r="$SYMBOL"
   symbol_r['type']="$metatype"
   symbol_r['name']="$name"

   declare -g TYPE="$metatype"
}


function type:copy {
   local -n t0_r="$1"

   type:new
   local t1="$TYPE"
   local -n t1_r="$TYPE"
   t1_r['kind']="${t0_r[kind]}"

   local -n t0_items_r="${t0_r[subtype]}"
   local -n t1_items_r="${t1_r[subtype]}"

   for t in "${t0_items_r[@]}" ; do
      type:copy "$t"
      t1_items_r+=( "$TYPE" )
   done

   declare -g TYPE="$t1"
}


function type:equality {
   local -n t1_r="$1"

   if [[ ${t1_r[kind]} == 'ANY' ]] ; then
      return 0
   fi

   # In the case of...
   #  t1(type: list, subtype: any)
   #  t2(type: list, subtype: None)
   # ...the first type:equality() on their .type will match, but the second must
   # not throw an exception. It is valid to have a missing (or different) type,
   # if the principal type is ANY.
   [[ "$2" ]] || return 1
   local -n t2_r="$2"

   if [[ ${t1_r[kind]} != "${t2_r[kind]}" ]] ; then
      return 1
   fi

   local -n t1_items_r="${t1_r['subtype']}"
   local -n t2_items_r="${t2_r['subtype']}"

   # Number of subtypes must match in number. Allows for easy iterating with a
   # single index.
   (( ${#t1_items_r[@]} == ${#t2_items_r[@]} )) || return 1

   local -i idx
   for idx in "${!t1_items_r[@]}" ; do
      if ! merge_type "${t1_items_r[$idx]}" "${t2_items_r[$idx]}" ; then
         return 1
      fi
   done

   return 0
}


#===============================================================================
# @section                       Create scopes
# @description
#  1. Creates .symtab references in nodes of...
#     * Section declarations
#     * Variable declarations
#     * Identifiers
#  2. Explodes if...
#     * Variable already declared in that scope
#     * Type isn't found in symbol table
#     * Type isn't a valid type
#-------------------------------------------------------------------------------

# walk:symtab()
# @description
#  Calls the appropriate `symtab_`-prefixed function depending on the node
#  type.
#
# @arg   $1    :NODE
function walk:symtab {
   declare -g NODE="$1"
   symtab_"${TYPEOF[$NODE]}"
}


function symtab_program {
   symtab new --parent "$SYMTAB"
   local symtab="$SYMTAB"

   local node="$NODE"
   local -n node_r="$node"

   walk:symtab "${node_r[header]}"
   walk:symtab "${node_r[container]}"

   declare -g SYMTAB="$symtab"
   declare -g NODE="$node"
}


function symtab_header {
   local -n node_r="$NODE"
   local -n items_r="${node_r[items]}"
   for ast_node in "${items_r[@]}" ; do
      walk:symtab "$ast_node"
   done
}


function symtab_typedef {
   mk_symbol
   local symbol="$SYMBOL"
   local -n symbol_r="$symbol"

   # Save node name in symbol.
   symbol_r['node']="$NODE"

   local -n node_r="$NODE"
   local -n name_r="${node_r[name]}"
   symbol_r['name']="${name_r[value]}"

   walk:symtab "${node_r[type]}"
   local type="$TYPE"

   ## TODO: uncomment when typedefs are list-based
   #
   #local -n items_r"${metatype_r[subtype]}"
   #if (( ! ${#items_r[@]} == 1 )) ; then
   #   e=( --anchor "${name_r[location]}"
   #       --caught "${subtype_r[location]}"
   #       "${metatype_r[kind]}"
   #   ); raise too_many_subtypes "${e[@]}"
   #fi

   # Create Type representing Types.
   type:new
   local metatype="$TYPE"
   local -n metatype_r="$TYPE"
   metatype_r['kind']='TYPE'
   
   local -n items_r="${metatype_r[subtype]}"
   metatype_r['subtype']="$type"

   symbol_r['type']="$metatype"
   symtab set "$symbol"
}


function symtab_decl_section {
   local -n node_r="$NODE"

   mk_symbol
   local symbol="$SYMBOL"
   local -n symbol_r="$SYMBOL"

   # Save node name in symbol.
   symbol_r['node']="$NODE"

   # Save section name in symbol.
   local -n ident_r="${node_r[name]}"
   local name="${ident_r[value]}"
   symbol_r['name']="${ident_r[value]}"

   if symtab strict "$name" ; then
      e=( --anchor "${node_r[location]}"
          --caught "${node_r[location]}"
          "$name"
      ); raise name_collision "${e[@]}"
   else
      symtab set "$symbol"
   fi

   #  ┌── doesn't know about dynamically created $_SECTION var.
   # shellcheck disable=SC2154
   type:copy "$_SECTION"
   symbol_r['type']="$TYPE"

   local symtab="$SYMTAB"
   symtab new --parent "$SYMTAB"

   # Save reference to the symbol table at the current scope. Needed in the
   # linear evaluation phase.
   node_r['symtab']="$SYMTAB"

   local -n items_r="${node_r[items]}"
   for ast_node in "${items_r[@]}"; do
      walk:symtab "$ast_node"
   done

   declare -g SYMTAB="$symtab"
}


function symtab_decl_variable {
   local -n node_r="$NODE"

   # Save reference to the symbol table at the current scope. Needed in the
   # linear compilation phase(s).
   node_r['symtab']="$SYMTAB"

   mk_symbol
   local symbol="$SYMBOL"
   local -n symbol_r="$symbol"

   # Save node name in symbol.
   symbol_r['node']="$NODE"

   # Save variable name in symbol.
   local identifier="${node_r[name]}"
   local -n identifier_r="$identifier"
   local name="${identifier_r[value]}"
   symbol_r['name']="$name"

   if symtab strict "$name" ; then
      e=( --anchor "${node_r[location]}"
          --caught "${node_r[location]}"
          "$name"
      ); raise name_collision "${e[@]}"
   else
      symtab set "$symbol"
   fi

   # Set the symbol's type to the declared type (if exists), else implicitly
   # takes a Type('ANY').
   if [[ "${node_r[type]}" ]] ; then
      walk:symtab "${node_r[type]}"
   else
      # shellcheck disable=SC2154
      type:copy "$_ANY"
   fi
   symbol_r['type']="$TYPE"

   if [[ "${node_r[expr]}" ]] ; then
      # Still must descend into expression, as to make references to the symtab
      # in identifier nodes.
      walk:symtab "${node_r[expr]}"
   fi
}


function symtab_type {
   local -n node_r="$NODE"
   local -n name_r="${node_r[kind]}"
   local name="${name_r[value]}"

   if ! symtab get "$name" ; then
      e=( --anchor "${name_r[location]}"
          --caught "${name_r[location]}"
          "$name"
      ); raise undefined_type "${e[@]}"
   fi

   local -n symbol_r="$SYMBOL"
   local metatype="${symbol_r[type]}"
   local -n metatype_r="$metatype"

   #  ┌── doesn't know about dynamically created $_TYPE (confused with $TYPE).
   # shellcheck disable=SC2153,SC2154
   if [[ ! "${metatype_r[kind]}" == TYPE ]] ; then
      e=( --anchor "${name_r[location]}"
          --caught "${name_r[location]}"
          "$name"
      ); raise not_a_type "${e[@]}"
   fi

   #local -n items_r"${metatype_r[subtype]}"
   #if (( ! ${#items_r[@]} == 1 )) ; then
   #   e=( --anchor "${name_r[location]}"
   #       --caught "${subtype_r[location]}"
   #       "${metatype_r[kind]}"
   #   ); raise too_many_subtypes "${e[@]}"
   #fi

   #type:copy
   #local type="$TYPE"
   #local -n type_r="$type"

   #if [[ "${node_r[subtype]}" ]] ; then
   #   if [[ ! "${type_r[complex]}" ]] ; then
   #      local -n subtype_r="${node_r[subtype]}"
   #      e=( --anchor "${name_r[location]}"
   #          --caught "${subtype_r[location]}"
   #          "primitive types are not subscriptable"
   #      ); raise type_error "${e[@]}"
   #   fi

   #   walk:symtab "${node_r[subtype]}"
   #   type_r['subtype']="$TYPE"
   #fi

   declare -g TYPE="$type"
}


function symtab_typecast {
   local -n node_r="$NODE"
   walk:symtab "${node_r[expr]}"
}


function symtab_member {
   local -n node_r="$NODE"
   walk:symtab "${node_r[left]}"
   walk:symtab "${node_r[right]}"
}


function symtab_index {
   local -n node_r="$NODE"
   walk:symtab "${node_r[left]}"
   walk:symtab "${node_r[right]}"
}


function symtab_unary {
   local -n node_r="$NODE"
   walk:symtab "${node_r[right]}"
}


function symtab_list {
   local -n node_r="$NODE"
   local -n items_r="${node_r[items]}"
   for ast_node in "${items_r[@]}" ; do
      walk:symtab "$ast_node"
   done
}


function symtab_identifier {
   local -n node_r="$NODE"
   node_r['symtab']="$SYMTAB"

   # TODO: may need to throw name_error's here.
}

function symtab_import  { :; }
function symtab_boolean { :; }
function symtab_integer { :; }
function symtab_string  { :; }
function symtab_path    { :; }
function symtab_env_var { :; }
