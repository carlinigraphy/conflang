#!/bin/bash
#
# Requires from environment:
#  ROOT
#  TYPEOF{}
#  NODE_*
#  SECTION
#  ^-- Name of the section we're currently in. After we've iterated through a
#    pair of symtabs, any keys remaining in the child should be copied over to
#    the parent. We must both copy the key:value from the symtab (for semantic
#    analysis in the next phase), but also need to append the nodes themselves
#    to the parent section's .items array.

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
   # symtabs.

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
   local   -n  type=$tname

   type['kind']=
   type['subtype']=
}


declare -- SYMBOL=
declare -i SYMBOL_NUM=${TYPE_NUM:-0}

function mk_symbol {
   (( SYMBOL_NUM++ ))
   local   --  sname="SYMBOL_${SYMBOL_NUM}"
   declare -gA $sname
   declare -g  SYMBOL=$sname
   local   -n  symbol=$sname

   symbol['type']=
   symbol['node']=
   symbol['symtab']=
   symbol['required']=
   # Variable declaration symbols are `required' if its NODE has no expression.
   # A Section is considered to be `required' if *any* of its children are
   # required. This is only needed when enforcing constraints upon a child file.
}


function walk_symtab {
   declare -g NODE="$1"
   symtab_"${TYPEOF[$NODE]}"
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
   symbol['type']=$type_name

   # Create new symtab for children of this section. Populate parent's symtab
   # with a reference to this one.
   mk_symtab
   symbol['symtab']=$SYMTAB

   local -n items="${node[items]}" 
   for nname in "${items[@]}"; do
      walk_symtab "$nname"
   done

   # Check if this section is `required'. If any of its children are required,
   # it must be present in a child file.
   local -n child_symtab="${symbol[symtab]}"
   for c_sym_name in "${child_symtab[@]}" ; do
      local -n c_sym=$c_sym_name
      if [[ "${c_sym[required]}" ]] ; then
         symbol['required']='yes'
         break
      fi
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

   if [[ ${node['type']} ]] ; then
      walk_symtab "${node['type']}"
      symbol['type']=$TYPE
   else
      # If user does not specify a type declaration, it gets an implicit ANY
      # type that matches anything.
      mk_type
      local -n type=$TYPE
      type['kind']='ANY'
      symbol['type']=$TYPE
   fi

   # Variables are `required' when they do not contain an expression. A child
   # must fill in the value.
   if [[ ! ${node['expr']} ]] ; then
      symbol[required]='yes'
   fi

   declare -g NODE=$node_name
}


function symtab_typedef {
   local -- save=$NODE
   local -n node=$save

   walk_symtab "${node[kind]}"
   local -- tname=$TYPE

   if [[ ${node['subtype']} ]] ; then
      walk_symtab "${node[subtype]}"
      type['subtype']=$TYPE
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
#> echo "${identifier}"  # -> [$section.]+$identifier -> sect1.sect2.key
declare -a FQ_LOCATION=()
declare -- FQ_NAME=

# Don't want to exit instantly on the first missing key. Collect them all,
# report and fail at the end.
declare -a MISSING_KEYS=()

# Currently just logs the `path' to the identifier whose type was incorrect.
# Need to also display file/line/column/expected type information. This is
# different from a semantic typecheck. We're checking that a parent node is a
# Section, and the child is as well. Or the parent is a variable declaration,
# and the child matches.
declare -a SYMBOL_MISMATCH=()

# Cannot re-declare a typedef that's already been defined.
declare -a TYPE_REDECLARE=()


function merge_symtab {
   local -n parent_symtab=$1
   local -n child_symtab=$2

   # We iterate over the parent symtab. So we're guaranteed to hit every key
   # there. The child symtab may contain *extra* keys that we need to merge in.
   # Every time we match a key from the parent->child, we can pop it from this
   # copy. Anything left is a duplicate that must be merged.
   local -A child_keys=()
   for k in "${!child_symtab[@]}" ; do
      child_keys["$k"]=
   done
   
   for p_key in "${!parent_symtab[@]}" ; do
      FQ_LOCATION+=( "$p_key" )

      # Parent Symbol.
      local -- p_sym_name="${parent_symtab[$p_key]}"
      local -n p_sym=$p_sym_name
      local -- p_node=${p_sym[node]}

      # For error reporting, build a "fully qualified" path to this node.
      local fq_name=''
      for s in "${FQ_LOCATION[@]}" ; do
         fq_name+="${s}."
      done
      fq_name+="${p_key}"
      FQ_NAME="$fq_name"

      # Parent type information.
      local -- p_type_name="${p_sym[type]}"
      local -n p_type=$p_type_name

      # Child Symbol.
      local -- c_sym_name="${child_symtab[$p_key]}"
      
      # shellcheck disable=SC2184
      unset child_keys["$p_key"]
      # Pop reference to child symbol from the `child_keys[]` copy. Will allow
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
   for c_key in "${child_keys[@]}" ; do
      # Add to symtab.
      parent_symtab[$c_key]="${child_symtab[$c_key]}" 

      local -n c_sym="${child_symtab[$c_key]}"
      local -n section=$SECTION
      local -n items="${section[items]}"

      # Add to items.
      items+=( "${c_sym[node]}" )
   done
}


function merge_section {
   # It's easier to think about the conditions in which a merge *fails*. A
   # section merge fails when:
   #  1. It is required in the parent, and missing in the child
   #  2. It is of a non-Section type in the child

   local -- p_sym_name="$1"
   local -- c_sym_name="$2"

   # We know the parent symbol exists. Can safely nameref it.
   local -n p_sym="$p_sym_name"

   # case 1.
   # Child section is missing, but was required in the parent.
   if [[ ! "$c_sym_name" ]] ; then
      if [[ "${p_sym[required]}" ]] ; then
         MISSING_KEYS+=( "$FQ_NAME" )
         return 1
      fi

      # If child section was missing, but not required... nothing to do. We
      # gucci & scoochie.
      return 0
   fi

   local -n c_sym="$c_sym_name"
   local -n c_type="${c_sym[type]}"
   
   # case 2.
   # Found child node under the same identifier, but not a Section.
   if [[ ${c_type[kind]} != 'SECTION' ]] ; then
      SYMBOL_MISMATCH+=( "$FQ_NAME" )
      return 1
   fi

   SECTION="${p_sym[node]}"
   merge_symtab "${p_sym[symtab]}" "${c_sym[symtab]}"
}


function merge_variable {
   # It's easier to think about the conditions in which a merge *fails*. A
   # variable merge fails when:
   #  1. If the child does not exist, and...
   #     a. the parent was required
   #  2. If the child exist, and...
   #     a. it's not also a type(var_decl)
   #     b. it's declaring a different type

   local -- p_sym_name="$1"
   local -- c_sym_name="$2"

   # We know the parent symbol exists. Can safely nameref it.
   local -n p_sym="$p_sym_name"

   # case 1a.
   if [[ ! "$c_sym_name" ]] ; then
      if [[ "${p_sym[required]}" ]] ; then
         MISSING_KEYS+=( "$FQ_NAME" )
         return 1
      fi
      return 0
   fi

   local -n c_sym="$c_sym_name"

   # case 2a.
   # Expecting a variable declaration, child is actually a Section.
   local -n c_type="${c_sym[type]}" 
   if [[ "${c_type[kind]}" == 'SECTION' ]] ; then
      SYMBOL_MISMATCH+=( "$FQ_NAME" )
      return 1
   fi

   # case 2b.
   # The type of the child must defer to the type of the parent.
   if ! merge_type "${p_sym[type]}" "${c_sym[type]}" ; then
      TYPE_REDECLARE+=( "$FQ_NAME" )
      return 1
   fi

   # If we haven't hit any errors, can safely copy over the child's value to the
   # parent.
   local -n p_node="${p_sym[node]}" 
   local -n c_node="${c_sym[node]}" 
   if [[ "${c_node[expr]}" ]] ; then
      # shellcheck disable=SC2034
      # ^-- does not understand namerefs
      p_node['expr']="${c_node[expr]}" 
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

   local -n t1="$1"
   local -n t2="$2"

   # case 2.
   # Doesn't matter what the parent's type was. The child is not declaring it,
   # thus respecting the imposed type.
   [[ "${t2[kind]}" == 'ANY' ]] && return 0

   # case 1.
   # Parent and child's types match exactly.
   if [[ ${t1['kind']} == "${t2[kind]}" ]] ; then
      return 0
   fi

   # Same as above, but for any subtypes.
   if [[ ${t1['subtype']} ]] ; then
      merge_type "${t1[subtype]}" "${t2[subtype]}"
      return $?
   fi

   return 1
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


#─────────────────────────────────( compiler )──────────────────────────────────
# TODO: documentation
# shellcheck disable=SC1007
# ^-- thinks I'm trying to assign a var, rather than declare empty variables.
declare -- KEY= DATA=
declare -i DATA_NUM=${TYPE_NUM:-0}

function mk_compile_dict {
   (( DATA_NUM++ ))
   local   --  dname="_DATA_${DATA_NUM}"
   declare -gA $dname
   declare -g  DATA=$dname
   local   -n  data=$dname
   data=()
}


function mk_compile_array {
   (( DATA_NUM++ ))
   local   --  dname="_DATA_${DATA_NUM}"
   declare -ga $dname
   declare -g  DATA=$dname
   local   -n  data=$dname
   data=()
}


function walk_compiler {
   declare -g NODE="$1"
   compile_"${TYPEOF[$NODE]}"
}


function compile_decl_section {
   # Save reference to current NODE. Restored at the end.
   local -- save=$NODE
   local -n node=$save

   # Create data dictionary object.
   mk_compile_dict
   local -- dname=$DATA
   local -n data=$DATA

   walk_compiler "${node[name]}"
   local -- key="$DATA"

   local -n items="${node[items]}" 
   for nname in "${items[@]}"; do
      walk_compiler "$nname"
      data[$KEY]="$DATA"
   done

   declare -g KEY="$key"
   declare -g DATA="$dname"
   declare -g NODE="$save"
}


function compile_decl_variable {
   local -- save=$NODE
   local -n node=$save

   walk_compiler "${node[name]}"
   local -- key="$DATA"

   if [[ -n ${node[expr]} ]] ; then
      walk_compiler "${node[expr]}"
   else
      declare -g DATA=''
   fi

   declare -g KEY="$key"
   declare -g NODE=$save
}


function compile_unary {
   local -- save=$NODE
   local -n node=$save

   # The only unary expression right now is negation.
   walk_compiler "${node[rhs]}"
   local -i rhs=$DATA

   (( DATA = -1 * rhs ))
   declare -g NODE=$save
}


function compile_array {
   local -- save=$NODE
   local -n node=$save

   mk_compile_array
   local -- dname=$DATA
   local -n data=$DATA

   for nname in "${node[@]}"; do
      walk_compiler "$nname"
      data+=( "$DATA" )
   done

   declare -g DATA=$dname
   declare -g NODE=$save
}


function compile_boolean {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


function compile_integer {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


function compile_string {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


function compile_path {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


function compile_identifier {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


function compile_variable {
   : "There's a chance we may have stomped on an environment variable from the
      user."

   local -n node=$NODE
   local -- var_name="${node[value]}" 

   if [[ "${ENV_DIFF[$var_name]}" ]] ; then
      raise stomped_env_var "$var_name"
   fi

   if [[ ! -v "$var_name" ]] ; then
      raise missing_env_var "$var_name"
   fi

   local -n var="$var_name"
   declare -g DATA="$var"
}
