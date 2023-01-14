#!/bin/bash
#===============================================================================
# @section                        Symbol table trees
# @description
#  Rather than the traditional stack of symbol tables that we push & pop from,
#  a map of each symtab to its parent is easier to implement in Bash. Less
#  nonsense.
#-------------------------------------------------------------------------------

function symtab:new {
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
function symtab:init_globals {
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
      [%none]='NONE'
      [%section]='SECTION'
      # User isn't allowed to declare a section. They're a logical grouping,
      # not an expression.
   )

   local -A complex=(
      [type]='TYPE,1'
      [list]='LIST,1'
      [rec]='RECORD,-1'
   )

   # Create symbols for primitive types.
   for short in "${!primitive[@]}" ; do
      local long="${primitive[$short]}"
      type:new_meta "$short"  "$long"
      symtab:set "$SYMBOL"
   done

   # Create symbols for complex types.
   for short in "${!complex[@]}" ; do
      local long="${complex[$short]%,*}"
      local slots="${complex[$short]#*,}"
      type:new_meta "$short"  "$long"  "$slots"
      symtab:set "$SYMBOL"
   done
}


# @description
#  Recursively searches upward for Symbol identified by $1.
function symtab:get {
   local name="$1"

   local symtab="$SYMTAB" ; local -n symtab_r="$symtab"
   local parent="${SYMTAB_PARENT[$symtab]}"

   local symbol="${symtab_r[$name]}"
   declare -g SYMBOL="$symbol"

   if [[ ! "$SYMBOL" && "$parent" ]] ; then
      declare -g SYMTAB="$parent"
      symtab:get "$name"
   fi

   # Return to the original symbol table.
   declare -g SYMTAB="$symtab"
   [[ "$SYMBOL" ]]
}


# @description
#  Searches only current symtab for Symbol identified by $1.
function symtab:strict {
   local name="$1"
   local -n symtab_r="$SYMTAB"
   declare -g SYMBOL="${symtab_r[$name]}"
   [[ "$SYMBOL" ]]
}


# @description
#  Sets ${symbol[name]} -> $symbol in current symtab
function symtab:set {
   local symbol="$1"
   local -n symbol_r="$symbol"
   local name="${symbol_r[name]}"

   local -n symtab_r="$SYMTAB"
   symtab_r[$name]="$symbol"
}


# @description
#  Sets global $SYMTAB pointer to that referenced in $node
function symtab:from {
   local -n node_r="$1"
   declare -g SYMTAB="${node_r[symtab]}"
}


# @description
#  Assuming $1 is a Section, sets $SYMTAB to $1.node.symtab.
#
# @set   SYMTAB
# @arg   $1    :str     Identifier name to search in current scope
function symtab:descend {
   local -n symtab_r="$SYMTAB"
   local -n symbol_r="${symtab_r[$1]}"
   symtab:from "${symbol_r[node]}"
}


function symbol:new {
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

# @set   TYPE
# @noargs
function type:new {
   local -i slots="${1:-0}"

   (( ++_TYPE_NUM ))
   local type="TYPE_${_TYPE_NUM}"
   declare -gA "$type"
   declare -g  TYPE="$type"

   local -n t_r="$type"
   t_r['kind']=''          #< :str
   t_r['slots']="$slots"   #< :int,  available slots in paramlist
   t_r['subtype']=''       #< :TYPE, initial node of a paramlist
   t_r['next']=''          #< :TYPE, subsequent node of a paramlist
}


# @set   TYPE
# @arg   $1    :str     Short name of the Symbol ("str", "int", etc.)
# @arg   $1    :str     Kind of type (STRING, INTEGER, RECORD)
function type:new_meta {
   local name="$1"
   local kind="$2"
   local -i slots="${3:-0}"

   type:new "$slots"
   local type="$TYPE"
   local -n type_r="$TYPE"
   type_r['kind']="$kind"

   # Create Type representing Types.
   type:new 1
   local metatype="$TYPE"
   local -n metatype_r="$TYPE"
   metatype_r['kind']='TYPE'
   metatype_r['subtype']="$type"

   symbol:new
   local -n symbol_r="$SYMBOL"
   symbol_r['type']="$metatype"
   symbol_r['name']="$name"

   declare -g "_${kind}"="$type"
   declare -g TYPE="$metatype"
}


# @arg   $1    TYPE
function type:copy {
   local -n t0_r="$1"

   type:new
   local t1="$TYPE"
   local -n t1_r="$TYPE"
   t1_r['kind']="${t0_r[kind]}"
   t1_r['slots']="${t0_r[slots]}"

   if [[ "${t0_r[next]}" ]] ; then
      type:copy "${t0_r[next]}"
      t1_r['next']="$TYPE"
   fi

   if [[ "${t0_r[subtype]}" ]] ; then
      type:copy "${t0_r[subtype]}"
      t1_r['subtype']="$TYPE"
   fi

   declare -g TYPE="$t1"
}


function type:eq {
   local t1="$1" t2="$2"
   local strict="$3"

   # Neither type exists. All good.
   if [[ ! $t1 && ! $t2 ]] ; then
      return 0
   fi

   # Either RHS or LHS did not exist. Not good.
   if ! [[ $t1 && $t2 ]] ; then
      return 1
   fi

   local -n t1_r="$t1"
   local -n t2_r="$t2"

   # Lhs 'ANY' or rhs 'NONE' good if not a strict equality comparison.
   if [[ ! $strict ]] ; then
      if [[ ${t1_r[kind]} == ANY  ]] ||
         [[ ${t2_r[kind]} == NONE ]]
      then
         return 0
      fi
   fi

   # Kinds must match.
   if [[ ! ${t1_r[kind]} == "${t2_r[kind]}" ]] ; then
      return 1
   fi

   # Nexts must match.
   if ! type:eq "${t1_r[next]}" "${t2_r[next]}" ; then
      return 1
   fi

   # Subtypes must match.
   if ! type:eq "${t1_r[subtype]}" "${t2_r[subtype]}" ; then
      return 1
   fi

   return 0
}


function type:shallow_eq {
   local -n t1_r="$1"
   local -n t2_r="$2"
   [[ ${t1_r[kind]} == "${t2_r[kind]}" ]]
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
declare -g  TYPE_ANCHOR=''
declare -gi SLOTS=0

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
   symtab:new --parent "$SYMTAB"
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
   symbol:new
   local symbol="$SYMBOL"
   local -n symbol_r="$symbol"

   # Save node name in symbol.
   symbol_r['node']="$NODE"

   local -n node_r="$NODE"
   local -n name_r="${node_r[name]}"
   symbol_r['name']="${name_r[value]}"

   walk:symtab "${node_r[type]}"
   local type="$TYPE"
   local -n type_r="$type"
   type_r['slots']=0
   # Disallow subtypes on user-defined types.

   # Create Type representing Types.
   type:copy "$_TYPE"
   local metatype="$TYPE"
   local -n metatype_r="$TYPE"
   metatype_r['subtype']="$type"

   symbol_r['type']="$metatype"
   symtab:set "$symbol"
}


function symtab_decl_section {
   local -n node_r="$NODE"

   symbol:new
   local symbol="$SYMBOL"
   local -n symbol_r="$SYMBOL"

   # Save node name in symbol.
   symbol_r['node']="$NODE"

   # Save section name in symbol.
   local -n ident_r="${node_r[name]}"
   local name="${ident_r[value]}"
   symbol_r['name']="${ident_r[value]}"

   if symtab:strict "$name" ; then
      e=( --anchor "${node_r[location]}"
          --caught "${node_r[location]}"
          "$name"
      ); raise name_collision "${e[@]}"
   else
      symtab:set "$symbol"
   fi

   #  ┌── doesn't know about dynamically created $_SECTION var.
   # shellcheck disable=SC2154
   type:copy "$_SECTION"
   symbol_r['type']="$TYPE"

   local symtab="$SYMTAB"
   symtab:new --parent "$SYMTAB"

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

   symbol:new
   local symbol="$SYMBOL"
   local -n symbol_r="$symbol"

   # Save node name in symbol.
   symbol_r['node']="$NODE"

   # Save variable name in symbol.
   local -n ident_r="${node_r[name]}"
   local name="${ident_r[value]}"
   symbol_r['name']="$name"

   if symtab:strict "$name" ; then
      e=( --anchor "${node_r[location]}"
          --caught "${node_r[location]}"
          "$name"
      ); raise name_collision "${e[@]}"
   else
      symtab:set "$symbol"
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


# symtab_type()
# @description
#  Walks the current AST(type) node, and any possible .subtype or .next nodes.
#  Need to make sure types do not exceed their available subtype param "slots"
#  here, rather than in the semantic analysis phase.
#
#  As merging is done prior to semantics, don't want to worry about merging
#  invalid types. E.g., how does one merge int[str] <- int[int]?
#
#  ```
#  In the case of...
#  rec[rec[list[str], rec[int, str], int], str]
# 
#  rec
#    \    (a)
#     `-> rec  ->>-  str
#           \    (a)         (a)
#            `-> list  ->>-  rec  ->>-  int
#                  \           \    (a)
#                   `-> str     `-> rec
#                                     \ 
#                                      `-> int  ->>-  str
#  ```
#
#  May throw either:
#  1. `not_a_type`, when the user supplies an identifier that isn't a type, or
#  2. `slot_error`, if the slots do not match the expected value
#
# @set   TYPE_ANCHOR
# @env   TYPE_ANCHOR
# @set   TYPE
# @env   TYPE
# @env   NODE
# @noargs
function symtab_type {
   local -n node_r="$NODE"
   local -n name_r="${node_r[kind]}"
   local name="${name_r[value]}"

   if ! symtab:get "$name" ; then
      e=( --anchor "${name_r[location]}"
          --caught "${name_r[location]}"
          "$name"
      ); raise missing_var "${e[@]}"
   fi

   local -n symbol_r="$SYMBOL"
   local metatype="${symbol_r[type]}"
   local -n metatype_r="$metatype"

   #1. not_a_type :: identifier does not refer to a Type.
   if [[ ! "${metatype_r[kind]}" == TYPE ]] ; then
      e=( --anchor "${name_r[location]}"
          --caught "${name_r[location]}"
          "$name"
      ); raise not_a_type "${e[@]}"
   fi

   #2. slot_error :: exceeded available slots (e.g., list[str, int], int[str]).
   if [[ "$TYPE_ANCHOR" ]] ; then
      local -n ta_r="$TYPE_ANCHOR"
      if ! (( ta_r[slots] - SLOTS )) ; then
         e=( --anchor "$ANCHOR"
             --caught "${name_r[location]}"
             "${ta_r[slots]}"
         ); raise slot_error "${e[@]}"
      fi
   fi

   # If haven't exceeded allowed slots, can incr. and continue.
   (( ++SLOTS ))

   type:copy "${metatype_r[subtype]}"
   local type="$TYPE"
   local -n type_r="$type"

   if [[ "${node_r[subtype]}" ]] ; then
      # Save previous values.
      local type_anchor="$TYPE_ANCHOR"
      local anchor="$ANCHOR"
      local -i slots="$SLOTS"

      declare -g  ANCHOR="${node_r[location]}"
      declare -g  TYPE_ANCHOR="$type"
      declare -gi SLOTS=0

      walk:symtab "${node_r[subtype]}"
      type_r['subtype']="$TYPE"

      # Restore previous values.
      declare -gi SLOTS="$SLOTS"
      declare -g  TYPE_ANCHOR="$type_anchor"
      declare -g  ANCHOR="$anchor"
   fi

   if [[ "${node_r[next]}" ]] ; then
      walk:symtab "${node_r[next]}"
      type_r['next']="$TYPE"
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

   # TODO: may need to throw name_error's here.
}

function symtab_import  { :; }
function symtab_boolean { :; }
function symtab_integer { :; }
function symtab_string  { :; }
function symtab_path    { :; }
function symtab_env_var { :; }
