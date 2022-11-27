#!/bin/bash

function mk_metatype() {
   local name="$1"
   local kind="$2"
   local complex="$3"

   mk_type
   local type="$TYPE"
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
   local metatype="$TYPE"
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
      [int]='INTEGER'
      [str]='STRING'
      [bool]='BOOLEAN'
      [path]='PATH'
      [section]='SECTION'
   )

   local -A complex=(
      [type]='TYPE'
      [list]='LIST'
      [rec]='RECORD'
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

   # Without a value, this isn't glob matched by ${!_SYMTAB_*} expansion
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
   symbol['name']=    #> str
   # While it isn't really required, it's substantially easier if we have a
   # string name, rather than needing to pull it from the symbol.node.name.value
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
   local t1="$TYPE"
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

#──────────────────────────────( create scopes )────────────────────────────────
function walk:symtab {
   declare -g NODE="$1"
   symtab_"${TYPEOF[$NODE]}"
}


function symtab_program {
   symtab new
   populate_globals
   local symtab="$SYMTAB"

   local -n node_r="$NODE"
   walk:symtab "${node_r[header]}"
   walk:symtab "${node_r[container]}"

   declare -g SYMTAB="$symtab"
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

   local -n node_r="$NODE"
   walk:symtab "${node_r[type]}"
   symbol_r['type']="$TYPE"

   local -n name_r="${node_r[name]}"
   symbol_r['name']="${name_r[value]}"

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
      e=( name_collision 
         --anchor "${node_r[location]}"
         --caught "${node_r[location]}"
         "$name"
      ); raise "${e[@]}"
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
      e=( name_collision 
         --anchor "${node_r[location]}"
         --caught "${node_r[location]}"
         "$name"
      ); raise "${e[@]}"
   else
      symtab set "$symbol"
   fi

   # Set the symbol's type to the declared type (if exists), else implicitly
   # takes a Type('ANY').
   if [[ "${node_r[type]}" ]] ; then
      walk:symtab "${node_r[type]}"
   else
      # shellcheck disable=SC2154
      copy_type "$_ANY"
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
      e=( undefined_type
         --anchor "${name_r[location]}"
         --caught "${name_r[location]}"
         "$name"
      ); raise "${e[@]}"
   fi

   local -n symbol_r="$SYMBOL"
   local outer_type="${symbol_r[type]}"
   # Types themselves are defined as such:
   #> int = Type('TYPE', subtype: Type('INTEGER'))
   #> str = Type('TYPE', subtype: Type('STRING'))

   #  ┌── doesn't know about dynamically created $_TYPE (confused with $TYPE).
   # shellcheck disable=SC2153,SC2154
   if ! type_equality  "$_TYPE"  "$outer_type" ; then
      e=( not_a_type
         --anchor "${name_r[location]}"
         --caught "${name_r[location]}"
         "$name"
      ); raise "${e[@]}"
   fi

   local -n outer_type_r="$outer_type"
   copy_type "${outer_type_r[subtype]}"
   local type="$TYPE"
   local -n type_r="$type"

   if [[ "${node_r[subtype]}" ]] ; then
      # See ./doc/truth.sh for an explanation on the test below. Checks if the
      # type has an unset .subtype field (indicating non-complex type).
      if [[ ! "${type_r[subtype]+_}" ]] ; then
         local -n subtype_r="${node_r[subtype]}"
         e=( type_error
            --anchor "${name_r[location]}"
            --caught "${subtype_r[location]}"
            "primitive types are not subscriptable"
         ); raise "${e[@]}"
      fi

      walk:symtab "${node_r[subtype]}"
      type_r['subtype']="$TYPE"
   fi

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
}

function symtab_import  { :; }
function symtab_boolean { :; }
function symtab_integer { :; }
function symtab_string  { :; }
function symtab_path    { :; }
function symtab_env_var { :; }


