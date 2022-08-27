#!/bin/bash #
# Requires from environment:
#  ROOT
#  TYPEOF{}
#  NODE_*
#  SECTION
#  ^-- Name of the section we're currently in. After we've iterated through a
#    pair of symtabs, any keys remaining in the child should be copied over to
#   the parent. We must both copy the key:value from the symtab (for semantic
#    analysis in the next phase), but also need to append the nodes themselves
#    to the parent section's .items array.

declare -- NODE=


function mk_metatype {
   local -- kind="$1"
   local -- complex="$2"

   mk_type
   local -- type_name="$TYPE"
   local -n type="$TYPE"
   type['kind']="$kind"

   if [[ "$complex" ]] ; then
      type['subtype']=''
      # This is what makes it a `complex' type. If the type.subtype is
      # *UNSET* (note, not "set but empty"--unset), then it may not have a
      # subtype. Complex types have a .subtype prop.
   fi

   # Create a type representing Types themselves.
   mk_type
   local -- parent_type_name="$TYPE"
   local -n parent_type="$TYPE"
   parent_type['kind']='TYPE'
   parent_type['subtype']="$type_name"

   mk_symbol
   local -n symbol="$SYMBOL"
   symbol['type']="$parent_type_name"
}


function populate_globals {
   local -n symtab="$SYMTAB"

   local -A primitive=(
      [int]='INTEGER'
      [str]='STRING'
      [bool]='BOOLEAN'
   )

   local -A complex=(
      [path]='PATH'
      [array]='ARRAY'
   )

   # Create symbols for primitive types.
   for short_name in "${!primitive[@]}" ; do
      mk_metatype "${primitive[$short_name]}"
      symtab[$short_name]="$SYMBOL"
   done

   # Create symbols for complex types.
   for short_name in "${!complex[@]}" ; do
      mk_metatype "${primitive[$short_name]}"  'complex'
      symtab[$short_name]="$SYMBOL"
   done
}


#───────────────────────────────( symbol table )────────────────────────────────
# Dict(s) of name -> Type mappings... and other information.
declare -- SYMTAB=
declare -i SYMTAB_NUM=0

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

   type['kind']=      #-> str
   #type['subtype']=  #-> Type
   # .subtype is only present in complex types. It is unset in primitive types,
   # which allows for throwing errors in semantic analysis for invalid subtypes.
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


function extract_type {
   : 'Pulls the underlying Type from a meta type declaration in the GLOBALS
      symbol table. Gotta query  symbol.type.subtype:

      Symbol {
         Type {
            kind: "TYPE"
            subtype: Type {
               kind: "(ARRAY|INTEGER|...)"
            }
         }
      }'

   local str_name="$1"

   local -n symbol="${GLOBALS[$str_name]}"
   local -n type="${symbol[type]}"
   copy_type "${type[subtype]}"
}


function copy_type {
   local -n t0="$1"

   mk_type
   local -- t1_name="$TYPE"
   local -n t1="$TYPE"
   t1['kind']="${t0[kind]}"

   if [[ "${t0['subtype']}" ]] ; then
      copy_type "${t0['subtype']}" 
      t1['subtype']="$TYPE"
   fi

   declare -g TYPE="$t1_name"
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
      extract_type 'any'
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
      # A subtype is only valid if the parent type has a .subtype property.
      # Primitive types are created with this unset. Complex types it is set,
      # but empty.
      local -n _parent_type="$tname"

      # See ./doc/truth.sh for an explanation on the test below.
      if [[ ! "${_parent_type['subtype']+_}" ]] ; then
         raise type_error        \
            "${node[subtype]}"   \
            "primitive types are not subscriptable."
      fi

      walk_symtab "${node[subtype]}"
      type['subtype']=$TYPE
   fi

   declare -g TYPE=$tname
   declare -g NODE=$save
}


function symtab_identifier {
   # Identifiers in this context are only used in typecasts.
   local -n node=$NODE
   local -- value="${node[value]}"

   local -- type="${GLOBALS[$value]}"
   if [[ ! "$type" ]] ; then
      raise invalid_type_error "$value"
   fi

   extract_type "$value"
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


#─────────────────────────────( semantic analysis )─────────────────────────────
function type_equality {
   local -n t1="$1"

   if [[ ${t1[kind]} == 'ANY' ]] ; then
      return 0
   fi

   # In the case of...
   #  t1(type: array, subtype: any)
   #  t2(type: array, subtype: None)
   # ...the first type_equality() on their .type will match, but the second must
   # not throw an exception. It is valid to have a missing (or different) type,
   # if the principal type is ANY.
   [[ "$2" ]] || return 1
   local -n t2="$2"

   if [[ ${t1[kind]} != ${t2[kind]} ]] ; then
      return 1
   fi

   if [[ ${t1[subtype]} ]] ; then
      type_equality "${t1[subtype]}" "${t2[subtype]}" 
      return $?
   fi

   return 0
}


function walk_semantics {
   declare -g NODE="$1"
   semantics_${TYPEOF[$NODE]}
}


function semantics_decl_section {
   local -- symtab_name="$SYMTAB"
   local -n symtab="$symtab_name"

   local -- save=$NODE
   local -n node=$save
   local -n name="${node[name]}"

   # Set symtab to point to the newly descended scope.
   local   -n symbol="${symtab[${name[value]}]}"
   declare -g SYMTAB="${symbol[symtab]}"

   declare -n items="${node[items]}" 
   for each in "${items[@]}"; do
      walk_semantics $each
   done

   declare -g SYMTAB="$symtab_name"
   declare -g NODE=$save
}


function semantics_decl_variable {
   local -- save=$NODE
   local -n node=$save
   local -n name="${node[name]}"

   # If there's no type declaration, or expression, there's nothing to do in
   # this phase.
   [[ ! ${node[type]} || ! ${node[expr]} ]] && return

   # Sets target type. The type of the expression should match the type of
   # the typedef in the symbol table.
   local -n symtab="$SYMTAB"
   local -n symbol="${symtab[${name[value]}]}"
   local -- target="${symbol[type]}"

   # Sets TYPE
   walk_semantics "${node[expr]}"

   if ! type_equality  "$target"  "$TYPE" ; then
      raise type_error "${node[expr]}"
   fi

   declare -g NODE=$save
}


function semantics_typedef {
   local -- save=$NODE
   local -n node=$save

   walk_semantics ${node[kind]}
   local -- tname=$TYPE
   local -n type=$TYPE

   if [[ ${node[subtype]} ]] ; then
      walk_semantics ${node[subtype]}
      type[subtype]=$TYPE
   fi

   declare -g NODE=$save
}


function semantics_typecast {
   local -n node="$NODE"
   walk_semantics ${node[typedef]}
}


function semantics_unary {
   local -- save=$NODE
   local -n node=$save

   # Right now the only unary nodes are negation, e.g., `-1`. The type of the
   # unary may only be the type of the expression. Realistically the type may
   # only be an integer.
   walk_semantics ${node[right]}
   local -- type="$TYPE"

   if [[ ${node[op]} == 'MINUS' ]] ; then
      if ! type_equality  '_INTEGER'  "$type" ; then
         raise type_error "${node[right]}" "unary minus only supports integers."
      fi
   else
      raise parse_error "unary expressions aside from \`minus' are unsupported."
   fi

   declare -g TYPE="$type"
   declare -g NODE="$save"
}


function semantics_array {
   local -- save=$NODE
   local -n node=$save

   # Top-level array.
   extract_type 'array'
   local array_name=$TYPE

   # The user *can* have an array of differing types, but not if the type is
   # declared with a subtype. E.g, `array:str`.
   local -A types_found=()

   for item in "${node[@]}" ; do
      walk_semantics "$item"
      local -n type=$TYPE
      local -- kind="${type[kind]}"
      types_found[$kind]=''
   done

   local type_string=''
   for type in "${!types_found[@]}" ; do
      type_string+="${type_string:+|}${type_string}"
   done

   if [[ $type_string ]] ; then
      # TODO: probably created a 'hidden' type called MIXED. Would allow more
      # more elegantly handling this problem.
      #
      # Cannot use `extract_type` here, as there's the chance for a mixed-type
      # array.
      mk_type
      local -- subtype_name=$TYPE
      local -n subtype=$TYPE
      subtype['kind']="$type_string"
      type['subtype']="$subtype_name"
   fi

   declare -g TYPE=$array_name
   declare -g NODE=$save
}


# In semantic analysis, we'll only hit this in typecasts.
function semantics_identifier {
   local -n node=$NODE
   local -- value="${node[value]}"

   extract_type "$value"
}


# Paths aren't yet complex types, but they will be in the future. For now, we
# can copy a base Type('PATH'). They will eventually have a :file, :dir, and
# perhaps others (:fifo, :symlink, etc.).
function semantics_path {
   extract_type "path"
}


function semantics_boolean { extract_type 'bool'; }
function semantics_integer { extract_type 'int';  }
function semantics_string  { extract_type 'str';  }


#─────────────────────────────────( compiler )──────────────────────────────────
# TODO: documentation
# shellcheck disable=SC1007
# ^-- thinks I'm trying to assign a var, rather than declare empty variables.
declare -- KEY= DATA=
declare -i DATA_NUM=0

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
   local -- symtab_name="$SYMTAB"
   local -n symtab="$symtab_name"

   # Save reference to current NODE. Restored at the end.
   local -- save=$NODE
   local -n node=$save
   local -n name="${node[name]}"

   # Set symtab to point to the newly descended scope.
   local   -n symbol="${symtab[${name[value]}]}"
   declare -g SYMTAB="${symbol[symtab]}"

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
   declare -g SYMTAB="$symtab_name"
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


function compile_typecast {
   local -n node="$NODE"
   walk_compiler "${node[expr]}" 
}


function compile_unary {
   local -- save=$NODE
   local -n node=$save

   walk_compiler "${node[right]}"
   local -i rhs=$DATA

   case "${node[op]}" in
      'MINUS')    (( DATA = -1 * rhs )) ;;
      *) raise parse_error "${node[op],,} is not a unary operator."
   esac

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
   local -- string="${node[value]}"

   while [[ "${node[concat]}" ]] ; do
      walk_compiler "${node[concat]}"
      string+="$DATA"
      local -n node="${node[concat]}"
   done

   declare -g DATA="$string"
}


function compile_path {
   local -n node=$NODE
   local -- path="${node[value]}"

   while [[ "${node[concat]}" ]] ; do
      walk_compiler "${node[concat]}"
      path+="$DATA"
      local -n node="${node[concat]}"
   done

   declare -g DATA="$path"
}


function compile_identifier {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


function compile_env_var {
   local -n node=$NODE
   local -- var_name="${node[value]}" 

   if [[ "${ENV_DIFF[$var_name]}" ]] ; then
      raise stomped_env_var "$var_name"
   fi

   if [[ ! "$var_name" ]] ; then
      raise missing_env_var "$var_name"
   fi

   local -n var="$var_name"
   declare -g DATA="$var"
}


function compile_int_var {
   local -n node="$NODE"
   local -- var="${node[value]}"

   local -n symtab="$SYMTAB"
   local -- symbol_name="${symtab[$var]}"

   if [[ ! "$symbol_name" ]] ; then
      raise missing_int_var "$var"
   fi

   local -n symbol="$symbol_name"
   walk_compiler "${symbol[node]}"
}


function compile_index {
   : "An 'index' is a combination of...
         .left   subscriptable expression (section, array)
         .right  index expression (identifier, integer)"

   local -n node="$NODE"

   walk_compiler "${node[left]}" 
   local -n left="$DATA"

   walk_compiler "${node[right]}"
   local -- right="$DATA"

   DATA="${left[$right]}"
}
