#!/bin/bash
#
# IMPORTS:
#  ROOT
#  TYPEOF{}
#  NODE_*


declare -- NODE=

#────────────────────────────────( build data )─────────────────────────────────
# TODO: documentation
declare -- KEY= DATA=

declare -i DATA_NUM=0
declare -- _DATA_ROOT='_DATA_1'

function mk_data_dict {
   (( DATA_NUM++ ))
   local   --  dname="_DATA_${DATA_NUM}"
   declare -gA $dname
   declare -g  DATA=$dname
   local   -n  data=$dname
   data=()
}


function mk_data_array {
   (( DATA_NUM++ ))
   local   --  dname="_DATA_${DATA_NUM}"
   declare -ga $dname
   declare -g  DATA=$dname
   local   -n  data=$dname
   data=()
}


function walk_data {
   declare -g NODE="$1"
   data_${TYPEOF[$NODE]}
}


function data_decl_section {
   # Save reference to current NODE. Restored at the end.
   local -- save=$NODE
   local -n node=$save

   # Create data dictionary object.
   mk_data_dict
   local -- dname=$DATA
   local -n data=$DATA

   walk_data ${node[name]}
   local -- key="$DATA"

   local -n items="${node[items]}" 
   for nname in "${items[@]}"; do
      walk_data $nname
      data[$KEY]="$DATA"
   done

   declare -g KEY="$key"
   declare -g DATA="$dname"
   declare -g NODE="$save"
}


function data_decl_variable {
   local -- save=$NODE
   local -n node=$save

   walk_data ${node[name]}
   local -- key="$DATA"

   if [[ -n ${node[expr]} ]] ; then
      walk_data ${node[expr]}
   else
      declare -g DATA=''
   fi

   declare -g KEY="$key"
   declare -g NODE=$save
}


# TODO: This is necessary currently for negative numbers.
#function data_unary { :; }


function data_array {
   local -- save=$NODE
   local -n node=$save

   mk_data_array
   local -- dname=$DATA
   local -n data=$DATA

   for nname in "${node[@]}"; do
      walk_data $nname
      data+=( "$DATA" )
   done

   declare -g DATA=$dname
   declare -g NODE=$save
}


function data_boolean {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


function data_integer {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


function data_string {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


function data_path {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


function data_identifier {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


#───────────────────────────────( symbol table )────────────────────────────────
# CURRENT:
# I think merging the trees is going to require 3-phases:
#  1. Generate symbol table for parent tree
#  2. Generate symbol table for child tree
#  3. Iterate parent symbol table stack
#     - Each name in that scope should have a matching name in the corresponding
#       child scope
#     - If a parent type is specified, the child value should match
#       - The child cannot overwrite a parent's type declaration
#     - If the child has a value, it *overwrites* the parent's value
#     - (Later) If the child has directives, they're *append* to the parent's
#       - Should probably compare if the directive/test does not currently
#         exist, so we're not duplicating.
#     - Any *additional* names in the child's scope are merged to the parent
#       - It may actually be easier to generate a completely separate resulting
#         tree, rather than moving from one to the other
#
# The third phase of this will clearly be the most difficult, and will likely
# take the place of the current semantic analysis, as we will need to do type
# checking to merge the two trees. Though maybe we fully ignore types here, and
# do a completely separate typechecking pass.
#
# 2022-07-28
# I don't actually think symbol tables are the right approach for this. We don't
# have the same sort of lexical scoping that a programming language does. There
# is not any way of referring to declared identifiers.
# It would also be nice if we could strip things down to dicts of the raw
# values:
#
# ## Top parent scope
# SCOPE_01=(
#     [global] = Type(Section, subtype: None, next: SCOPE_02),
#     [dirs]   = Type(Array, subtype: Type(String), next: None)
# )
#
# But how to handle the child's ADDITIONAL nodes that must be appended. Would
# need more information.
#  - Type
#    - kind
#    - subtype
#  - node         # name of that variable/section declaration node (e.g. NODE_1)
#  - next         # name of nested scope to descend into (for section decls)

# Dict(s) of name -> Type mappings... and other information.
declare -- SCOPE=
declare -i SCOPE_NUM=0

function pop_scope {
   SCOPES=( ${SCOPES[@]::${#SCOPES[@]}-1} )
}


function mk_symtab {
   (( SCOPE_NUM++ ))
   local   --  sname="SCOPE_${SCOPE_NUM}"
   declare -gA sname
   declare -g  SCOPE=$sname
   local   -n  scope=$sname
}


#─────────────────────────────( semantic analysis )─────────────────────────────
# Easy way of doing semantic analysis is actually similar to how we did the node
# traversal in the `conf()` function. Globally point to a Type() node.
# Everything at that level should match the Type.kind property. Descend into
# node, set global Type to previous Type.subtype (if exists). Continue semantic
# analysis.
 
# Pointer to the Type object of the currently selected Node. This will be
# compared to the $TARGET_TYPE.
declare -- TYPE=
declare -i TYPE_NUM=0

# Holds the intended target from a typedef. Compared to sub-expression's Types.
declare -- TARGET_TYPE=

declare -A BUILT_INS=(
   [int]='INTEGER'
   [str]='STRING'
   [bool]='BOOLEAN'
   [path]='PATH'
   [array]='ARRAY'
)


function mk_type {
   (( TYPE_NUM++ ))
   local   --  tname="TYPE_${TYPE_NUM}"
   declare -gA $tname
   declare -g  TYPE=$tname
   local   --  type=$tname

   type[kind]=
   type[subtype]=
}


function walk_semantics {
   declare -g NODE="$1"
   semantics_${TYPEOF[$NODE]}
}


function semantics_decl_section {
   local -- save=$NODE
   local -n node=$save

   declare -n items="${node[items]}" 
   for each in "${items[@]}"; do
      walk_semantics $each
   done

   declare -g NODE=$save
}


function semantics_decl_variable {
   local -- save=$NODE
   local -n node=$save

   # Type declarations cannot be nested. Thus this must be a "top level". Clear
   # any previously set TARGET_TYPE, and start anew.
   declare -g TARGET_TYPE=

   # If there's no type declaration, or expression, there's nothing to do in
   # this phase.
   [[ -z ${node[type]} || -z ${node[expr]} ]] && return

   walk_semantics ${node[type]}
   local -n target=$TARGET_TYPE

   walk_semantics ${node[expr]}
   local -n expr_type=$TYPE

   if [[ "${target[kind]}" != "${expr_type[kind]}" ]] ; then
      #raise 'type_error' "${target[kind]}" "${expr_type[kind]}"
      echo "Type Error. Wants(${target[kind]}), got(${expr_type[kind]})" 1>&2
      exit -1
   fi

   declare -g NODE=$save
}


function semantics_typedef {
   local -- save=$NODE
   local -n node=$save

   walk_semantics ${node[kind]}
   local -- tname=$TYPE
   local -n type=$TYPE

   if [[ -n ${node[subtype]} ]] ; then
      walk_semantics ${node[subtype]}
      type[subtype]=$TYPE
   fi

   declare -g TARGET_TYPE=$tname
   declare -g NODE=$save
}


# This can only occur within a validation section. Validation expressions must
# return a boolean.
#function semantics_unary {
#   local -- save=$NODE
#   local -n node=$save
#
#   walk_semantics ${node[right]}
#
#   declare -g NODE=$save
#}


function semantics_array {
   local -- save=$NODE
   local -n node=$save

   # Save reference to the type that's expected of us.
   local -- target_save=$TARGET_TYPE
   local -n target=$TARGET_TYPE

   # If we're not enforcing some constraints on the subtypes, then don't check
   # them.
   [[ -z ${target[subtype]} ]] && return

   declare -g TARGET_TYPE=${target[subtype]}
   local   -n subtype=${target[subtype]}

   for nname in "${node[@]}"; do
      walk_semantics $nname
      local -n child=$TYPE

      if [[ ${subtype[kind]} != ${child[kind]} ]] ; then
         #raise 'type_error' "${subtype[kind]}" "${child[kind]}"
         echo "Type Error. Wants(${subtype[kind]}), got(${child[kind]})" 1>&2
         exit -1
      fi
   done

   mk_type
   local -n type=$TYPE
   type[kind]='ARRAY'

   declare -g TARGET_TYPE=$target_save
   declare -g NODE=$save
}


function semantics_boolean {
   mk_type
   local -- tname=$TYPE
   local -n type=$TYPE
   type[kind]='BOOLEAN'
}


function semantics_integer {
   mk_type
   local -- tname=$TYPE
   local -n type=$TYPE
   type[kind]='INTEGER'
}


function semantics_string {
   mk_type
   local -- tname=$TYPE
   local -n type=$TYPE
   type[kind]='STRING'
}


function semantics_path {
   mk_type
   local -- tname=$TYPE
   local -n type=$TYPE
   type[kind]='PATH'
}


function semantics_identifier {
   mk_type
   local -- tname=$TYPE
   local -n type=$TYPE

   local -n node=$NODE
   local -- kind=${BUILT_INS[${node[value]}]}
   if [[ -z $kind ]] ; then
      echo "Invalid type \`${node[value]}\`" 1>&2
      exit -1
   fi

   type[kind]=$kind
}
# pass.
# No semantics to be checked here. Identifiers can only occur as names to
# elements, or function calls.


#──────────────────────────────────( engage )───────────────────────────────────
walk_data $ROOT
walk_semantics $ROOT
