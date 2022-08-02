#!/bin/bash
#
# Requires from environment:
#  ROOT
#  TYPEOF{}
#  NODE_*


declare -- NODE=

#───────────────────────────────( symbol table )────────────────────────────────
declare -A DEFAULT_TYPES=(
   [int]='INTEGER'
   [str]='STRING'
   [bool]='BOOLEAN'
   [path]='PATH'
   [array]='ARRAY'
)


# Dict(s) of name -> Type mappings... and other information.
declare -- SYMTAB=
declare -i SYMTAB_NUM=${SYMTAB_NUM:-0}

function mk_symtab {
   (( SYMTAB_NUM++ ))
   # A symtab maps the string identifier names to a Symbol, containing Type
   # information, as well as references to the current node, and nested (?)
   # symtab.

   local   --  sname="SYMTAB_${SYMTAB_NUM}"
   declare -gA $sname
   declare -g  SYMTAB=$sname
   local   -n  symtab=$sname
   symtab=()
}


declare -- TYPE=
declare -i TYPE_NUM=${TYPE_NUM:-0}

function mk_type {
   (( TYPE_NUM++ ))
   local   --  tname="TYPE_${TYPE_NUM}"
   declare -gA $tname
   declare -g  TYPE=$tname
   local   --  type=$tname

   type[kind]=
   type[subtype]=
}


declare -- SYMBOL=
declare -i SYMBOL_NUM=${TYPE_NUM:-0}

function mk_symbol {
   (( SYMBOL_NUM++ ))
   local   --  sname="SYMBOL_${SYMBOL_NUM}"
   declare -gA $sname
   declare -g  SYMBOL=$sname
   local   --  symbol=$sname

   symbol[type]=
   symbol[node]=
   symbol[symtab]=
}


function walk_symtab {
   declare -g NODE="$1"
   symtab_${TYPEOF[$NODE]}
}


function symtab_decl_section {
   # Save references: current SYMTAB & NODE
   local -- symtab_name=$SYMTAB
   local -- node_name=$NODE
   local -n node=$NODE
   local -n symtab=$SYMTAB

   # Create symbol referring to this section.
   mk_symbol
   local -- symbol_name=$SYMBOL
   local -n symbol=$SYMBOL

   # Save reference to this declaration NODE in the symbol. Needed when merging
   # a child tree into the parent's. Any identifiers that are present in a
   # child's symtab but not a parents are directly appended into the parent's
   # tree. The only way that's possible is with a reference to the node itself.
   symbol[node]=$node_name

   # Get string value of identifier node.
   local -- identifier_node=${node[name]}
   local -n identifier=$identifier_node
   local -- name="${identifier[value]}"

   # Add reference to current symbol in parent's SYMTAB. First check if the user
   # has already defined a variable with the same name in this symtab.
   if [[ ${symtab[$name]} ]] ; then
      raise name_error "$name"
   else
      symtab[$name]=$symbol_name
   fi

   # Create Type(kind: 'Section') for this node. Used in semantic analysis to
   # validate the config files.
   mk_type
   local -- type_name=$TYPE
   local -n type=$TYPE
   type[kind]='SECTION'
   symbol[type]=$type_name

   # Create new symtab for children of this section. Populate parent's symtab
   # with a reference to this one.
   mk_symtab
   symbol[symtab]=$SYMTAB

   local -n items="${node[items]}" 
   for nname in "${items[@]}"; do
      walk_symtab $nname
   done

   # Restore saved refs to the parent SYMTAB, and current NODE.
   declare -g NODE=$node_name
   declare -g SYMTAB=$symtab_name
}


function symtab_decl_variable {
   # Save references: current SYMTAB & NODE
   local -- symtab_name=$SYMTAB
   local -- node_name=$NODE
   local -n node=$NODE
   local -n symtab=$SYMTAB

   # Create symbol referring to this section.
   mk_symbol
   local -- symbol_name=$SYMBOL
   local -n symbol=$SYMBOL

   # Save reference to this declaration NODE in the symbol. Needed when merging
   # a child tree into the parent's. Any identifiers that are present in a
   # child's symtab but not a parents are directly appended into the parent's
   # tree. The only way that's possible is with a reference to the node itself.
   symbol[node]=$node_name

   # Get string value of identifier node.
   local -- identifier_node=${node[name]}
   local -n identifier=$identifier_node
   local -- name="${identifier[value]}"

   # Add reference to current symbol in parent's SYMTAB. First check if the user
   # has already defined a variable with the same name in this symtab.
   if [[ ${symtab[$name]} ]] ; then
      raise name_error "$name"
   else
      symtab[$name]=$symbol_name
   fi

   if [[ ${node[type]} ]] ; then
      walk_symtab ${node[type]}
      symbol[type]=$TYPE
   else
      # If user does not specify a type declaration, it gets an implicit ANY
      # type that matches anything.
      mk_type
      local -n type=$TYPE
      type[kind]='ANY'
      symbol[type]=$TYPE
   fi

   declare -g NODE=$node_name
}


function symtab_typedef {
   local -- save=$NODE
   local -n node=$save

   walk_symtab ${node[kind]}
   local -- tname=$TYPE

   if [[ ${node[subtype]} ]] ; then
      walk_symtab ${node[subtype]}
      type[subtype]=$TYPE
   fi

   declare -g TYPE=$tname
   declare -g NODE=$save
}


# Identifiers in this context are used only as type names.
function symtab_identifier {
   local -- nname=$NODE
   local -n node=$NODE

   local -- kind=${DEFAULT_TYPES[${node[value]}]}
   if [[ ! $kind ]] ; then
      raise invalid_type_error "${node[value]}"
   fi

   mk_type
   local -- tname=$TYPE
   local -n type=$TYPE
   type[kind]="$kind"
}

#───────────────────────────────( merge trees )─────────────────────────────────
# After generating the symbol tables for the parent & child, iterate over the
# parent's, merging in nodes. I'm not 100% sure if this should be in the
# compiler.
#
# Merging is only necessary if the parent has %constrain statements.

# Gives friendly means of reporting to the user where an error has occurred.
# As we descend into each symtab, push its name to the stack. Print by doing a
# FQ_LOCATION.join('.'). Example:
#
#> FQ_LOCATION=([0]='global' [1]='subsection')
#> identifier=${node[name]}
#>
#> for s in "${FQ_LOCATION[@]}" ; do
#>    echo -n "${s}."
#> done
#> echo "${identifier}"       # "global.subsection.$identifier"
declare -a FQ_LOCATION=()

# Don't want to exit instantly on the first missing key. Collect them all,
# report and fail at the end.
declare -a MISSING_KEYS=()

# Currently just logs the `path' to the identifier whose type was incorrect.
# Need to also display file/line/column/expected type information.
declare -a TYPE_MISMATCH=()

# Cannot re-declare a typedef that's already been defined.
declare -a TYPE_REDECLARE=()


function merge_type {
   # Needed to rethink the merge_type() function. It's not a semantic typecheck.
   # It needs to fail if the child has attempted to re-declare a typedef. Thus,
   # the child's type must always EITHER:
   #  1. Match exactly
   #  2. Be 'ANY'
   #  3. Not exist (in the case of a parent subtype, and the child's is empty)

   # case 3.
   # If there's a defined parent type, but no child.
   # This is acceptable.
   [[ $1 || ! $2 ]] && return 0

   local -- t1_name="$1" t2_name="$2"
   local -n t1="$1"      t2="$2"

   # case 2.
   # Doesn't matter what the parent's type was. The child is not declaring it,
   # thus respecting the imposed type.
   [[ "${t2[kind]}" == 'ANY' ]] && return 0

   # case 1.
   # Parent and child's types match exactly.
   if [[ ${t1[kind]} == ${t2[kind]} ]] ; then
      return 0
   fi

   # Same as above, but for any subtypes.
   if [[ ${t1[subtype]} ]] ; then
      merge_type "${t1[subtype]}" "${t2[subtype]}"
      return $?
   fi

   return 1
}


function merge_symtab {
   local -- parent_symtab_root=$1
   local -n parent_symtab=$1

   local -- child_symtab_root=$2
   local -n child_symtab=$2

   # We iterate over the parent symtab. So we're guaranteed to hit every key
   # there. The child symtab may contain *extra* keys that we need to merge in.
   # Every time we match a key from the parent->child, we can pop it from this
   # copy. Anything left is a duplicate that must be merged.
   local -a child_keys=( "${!child_symtab[@]}" )

   for p_key in "${!parent_symtab[@]}" ; do
      # Parent Symbol.
      local -- p_sym_name="${parent_symtab[$p_key]}"
      local -n p_sym=$p_sym_name
      local -n p_node=${p_sym[node]}

      # For error reporting, build a "fully qualified" path to this node.
      local fq_name=''
      for s in "${FQ_LOCATION[@]}" ; do
         fq_name+="${s}."
      done
      fq_name+="${p_key}"

      # Parent type information.
      local p_type_name="${p_sym[type]}"

      # Child Symbol.
      local -- c_sym_name="${child_symtab[$p_key]}"

      # If child exists, declare type information and namerefs.
      if [[ $c_sym_name ]] ; then
         local child_exists='yes'
         # Just little helper var to make it a little more clear in tests what
         # we're actually checking for.
         local -n c_sym=$c_sym_name
         local -- c_type_name=${c_sym[type]}
         local -- c_node_name=${c_sym[node]}
         local -n c_node=$c_node_name
      fi

      # Section declarations are fairly straightforward: Any section defined in
      # the parent must also exist in the child.
      if [[ ${TYPEOF[${p_sym[node]}]} == 'decl_section' ]] ; then
         if [[ ! $child_exists ]] ; then
            MISSING_KEYS+=( "$fq_name" )
            continue
            # TODO:
            # Instead of skipping we may honestly want to just create an empty
            # symtab for the child. If the parent has nested sections, but the
            # child is missing the top-most of them, this would allow us to
            # continue checking the sub-sections.
         fi

         if [[ ${TYPEOF[${c_sym[node]}]} == 'SECTION' ]] ; then
            TYPE_MISMATCH+=( "$fq_name" )
            continue
         fi

         merge_symtab "${p_sym[symtab]}" "${c_sym[symtab]}"
         continue
      else
         # The only types of symbols are section or variable declarations. If
         # the current node is not a section, it must be a variable.

         # Helper var for more clarification in tests.
         if [[ ${p_node[expr]} ]] ; then
            local has_default='yes'
         fi

         if [[ ! $child_exists ]] ; then
            # If the parent has not defined a default value for the variable,
            # then the key is missing.
            if [[ ! $has_default ]] ; then
               MISSING_KEYS+=( "$fq_name" )
            fi

            continue
         fi

         if ! merge_type "$p_type_name" "$c_type_name" ; then
            TYPE_REDECLARE+=( "$fq_name" )
         fi

         # Always overwrite a parent's expression with the child's. Even if the
         # child has an empty declaration.
         p_node[expr]=${c_node[expr]}
      fi
   done
}


#────────────────────────────────( build data )─────────────────────────────────
# TODO: documentation
declare -- KEY= DATA=
declare -i DATA_NUM=${TYPE_NUM:-0}

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


function data_unary {
   local -- save=$NODE
   local -n node=$save

   # The only unary expression right now is negation.
   walk_data ${node[rhs]}
   local -i rhs=$DATA

   declare -g DATA=$(( -1 * $rhs ))
   declare -g NODE=$save
}


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


##─────────────────────────────( semantic analysis )─────────────────────────────
## Easy way of doing semantic analysis is actually similar to how we did the node
## traversal in the `conf()` function. Globally point to a Type() node.
## Everything at that level should match the Type.kind property. Descend into
## node, set global Type to previous Type.subtype (if exists). Continue semantic
## analysis.
# 
## Holds the intended target from a typedef. Compared to sub-expression's Types.
#declare -- TARGET_TYPE=



#function type_equality {
#   [[ "$1" ]] || return 1
#   local -- t1_name="$1"
#   local -n t1="$1"
#
#   [[ "$2" ]] || return 1
#   local -- t2_name="$2"
#   local -n t2="$2"
#
#   if [[ ${t1[kind]} != ${t2[kind]} ]] ; then
#      return 1
#   fi
#
#   if [[ ${t1[subtype]} ]] ; then
#      type_equality "${t1[subtype]}" "${t2[subtype]}" 
#      return $?
#   fi
#
#   return 0
#}


#
#function walk_semantics {
#   declare -g NODE="$1"
#   semantics_${TYPEOF[$NODE]}
#}
#
#
#function semantics_decl_section {
#   local -- save=$NODE
#   local -n node=$save
#
#   declare -n items="${node[items]}" 
#   for each in "${items[@]}"; do
#      walk_semantics $each
#   done
#
#   declare -g NODE=$save
#}
#
#
#function semantics_decl_variable {
#   local -- save=$NODE
#   local -n node=$save
#
#   # Type declarations cannot be nested. Thus this must be a "top level". Clear
#   # any previously set TARGET_TYPE, and start anew.
#   declare -g TARGET_TYPE=
#
#   # If there's no type declaration, or expression, there's nothing to do in
#   # this phase.
#   [[ -z ${node[type]} || -z ${node[expr]} ]] && return
#
#   walk_semantics ${node[type]}
#   local -n target=$TARGET_TYPE
#
#   walk_semantics ${node[expr]}
#   local -n expr_type=$TYPE
#
#   if [[ "${target[kind]}" != "${expr_type[kind]}" ]] ; then
#      #raise 'type_error' "${target[kind]}" "${expr_type[kind]}"
#      echo "Type Error. Wants(${target[kind]}), got(${expr_type[kind]})" 1>&2
#      exit -1
#   fi
#
#   declare -g NODE=$save
#}
#
#
#function semantics_typedef {
#   local -- save=$NODE
#   local -n node=$save
#
#   walk_semantics ${node[kind]}
#   local -- tname=$TYPE
#   local -n type=$TYPE
#
#   if [[ -n ${node[subtype]} ]] ; then
#      walk_semantics ${node[subtype]}
#      type[subtype]=$TYPE
#   fi
#
#   declare -g TARGET_TYPE=$tname
#   declare -g NODE=$save
#}
#
#
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
#
#
#function semantics_array {
#   local -- save=$NODE
#   local -n node=$save
#
#   # Save reference to the type that's expected of us.
#   local -- target_save=$TARGET_TYPE
#   local -n target=$TARGET_TYPE
#
#   # If we're not enforcing some constraints on the subtypes, then don't check
#   # them.
#   [[ -z ${target[subtype]} ]] && return
#
#   declare -g TARGET_TYPE=${target[subtype]}
#   local   -n subtype=${target[subtype]}
#
#   for nname in "${node[@]}"; do
#      walk_semantics $nname
#      local -n child=$TYPE
#
#      if [[ ${subtype[kind]} != ${child[kind]} ]] ; then
#         #raise 'type_error' "${subtype[kind]}" "${child[kind]}"
#         echo "Type Error. Wants(${subtype[kind]}), got(${child[kind]})" 1>&2
#         exit -1
#      fi
#   done
#
#   mk_type
#   local -n type=$TYPE
#   type[kind]='ARRAY'
#
#   declare -g TARGET_TYPE=$target_save
#   declare -g NODE=$save
#}
#
#
#function semantics_boolean {
#   mk_type
#   local -- tname=$TYPE
#   local -n type=$TYPE
#   type[kind]='BOOLEAN'
#}
#
#
#function semantics_integer {
#   mk_type
#   local -- tname=$TYPE
#   local -n type=$TYPE
#   type[kind]='INTEGER'
#}
#
#
#function semantics_string {
#   mk_type
#   local -- tname=$TYPE
#   local -n type=$TYPE
#   type[kind]='STRING'
#}
#
#
#function semantics_path {
#   mk_type
#   local -- tname=$TYPE
#   local -n type=$TYPE
#   type[kind]='PATH'
#}
#
#
#function semantics_identifier {
#   mk_type
#   local -- tname=$TYPE
#   local -n type=$TYPE
#
#   local -n node=$NODE
#   local -- kind=${BUILT_INS[${node[value]}]}
#   if [[ -z $kind ]] ; then
#      echo "Invalid type \`${node[value]}\`" 1>&2
#      exit -1
#   fi
#
#   type[kind]=$kind
#}
## pass.
## No semantics to be checked here. Identifiers can only occur as names to
## elements, or function calls.
