#!/bin/bash


function mk_metatype {
   local name="$1"
   local kind="$2"
   local complex="$3"

   mk_type
   local -- type="$TYPE"
   local -n type_r="$type"
   type_r['kind']="$kind"

   if [[ "$complex" ]] ; then
      type_r['subtype']=''
      # This is what makes it a `complex' type. If the type.subtype is
      # *UNSET* (note, not "set but empty"--unset), then it may not have a
      # subtype.
   fi

   # Example: _BOOLEAN=_TYPE_12. Useful in the `semantics_$LITERAL` functions
   # as a copy_type() target:  copy_type $_BOOLEAN
   declare -g "_${kind}"="$TYPE"

   # Create a type representing Types themselves.
   mk_type
   local -- parent_type="$TYPE"
   local -n parent_type_r="$TYPE"
   parent_type_r['kind']='TYPE'
   parent_type_r['subtype']="$type"

   mk_symbol
   local -n symbol_r="$SYMBOL"
   symbol_r['type']="$parent_type"
   symbol_r['name']="$name"
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
# Dict(s) of name -> Type mappings... and other information.
declare -- SYMTAB=
declare -i SYMTAB_NUM=0

declare -A SYMTAB_PARENT=()
# Points to each symbol table's parent symtab. Saves us from needing to make the
# symbol tables an associative array to hold metadata, and a pointer to a second
# associative array for the actual key:Type pairs.

# Convenience function to more easily call the associated symbol table commands.
function symtab {
   local cmd="$1" ; shift
   _symtab_"$cmd" "$@"
}

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


function _symtab_strict {
   local -- name="$1"
   local -- symtab="$SYMTAB"
   local -n symtab_r="$symtab"

   declare -g SYMBOL="${symtab_r[$name]}"
   [[ "$SYMBOL" ]]
}


function _symtab_set {
   local -- symbol="$1"
   local -n symbol_r="$symbol"
   local -- name="${symbol_r[name]}"
   symtab_r[$name]="$symbol"
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
   # Save references: current SYMTAB & NODE
   local -- node="$NODE"
   local -n node_r="$NODE"

   # Create symbol referring to this section.
   mk_symbol
   local -- symbol="$SYMBOL"
   local -n symbol_r="$SYMBOL"

   # Save reference to this declaration NODE in the symbol. Needed when merging
   # a child tree into the parent's. Any identifiers that are present in a
   # child's symtab but not a parents are directly appended into the parent's
   # tree. The only way that's possible is with a reference to the node itself.
   symbol_r['node']="$node"

   # Get string value of identifier node.
   local -- ident="${node_r[name]}"
   local -n ident_r="$ident"
   local -- name="${ident_r[value]}"
   symbol_r['name']="$name"

   if symtab strict "$name" ; then
      raise name_collision "$name"
   else
      symtab set "$symbol"
   fi

   # Create Type(kind: 'Section') for this node. Used in semantic analysis to
   # validate the config files.
   copy_type "$_SECTION"
   symbol_r['type']="$TYPE"

   # Create new symtab for children of this section. Populate parent's symtab
   # with a reference to this one.
   symtab new
   symbol_r['symtab']="$SYMTAB"

   local -n items_r="${node_r[items]}" 
   for ast_node in "${items_r[@]}"; do
      walk_symtab "$ast_node"
   done

   # Check if this section is `required'. If any of its children are required,
   # it must be present in a child file.
   local -n child_symtab_r="${symbol_r[symtab]}"
   for sym in "${child_symtab_r[@]}" ; do
      local -n sym_r="$sym"
      if [[ "${sym_r[required]}" ]] ; then
         symbol_r['required']='yes'
         break
      fi
   done

   declare -g NODE="$node"
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
   symbol['node']=$node_name

   # Get string value of identifier node.
   local -- identifier_node=${node[name]}
   local -n identifier=$identifier_node
   local -- name="${identifier[value]}"
   symbol['name']="$name"

   # Add reference to current symbol in parent's SYMTAB. First check if the user
   # has already defined a variable with the same name in this symtab.
   if [[ ${symtab[$name]} ]] ; then
      raise name_collision "$name"
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
      local -n type_r="$TYPE"
      type_r['kind']='PATH'
      symbol['type']="$TYPE"
   fi

   # Variables are `required' when they do not contain an expression. A child
   # must fill in the value.
   if [[ ! ${node['expr']} ]] ; then
      symbol[required]='yes'
   fi

   declare -g NODE=$node_name
}


function symtab_typedef {
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

   if [[ ! "$outer_type" ]] ; then
      raise undefined_type "${node_r[kind]}"  "$name"
   fi

   if ! type_equality  "$_TYPE"  "$outer_type" ; then
      raise not_a_type "${node_r[kind]}" "$name"
   fi

   local -n outer_type_r="$outer_type"
   copy_type "${outer_type_r[subtype]}"
   local -- type="$TYPE"
   local -n type_r="$type"

   if [[ "${node_r[subtype]}" ]] ; then
      # See ./doc/truth.sh for an explanation on the test below. Tests if the
      # type either has a populated .subtype field, or the field is SET, but
      # empty.
      if [[ ! "${type[subtype]+_}" ]] ; then
         local loc="${node_r[subtype]}"  
         local msg="primitive types are not subscriptable."
         raise type_error "$loc" "$msg"
      fi

      walk_symtab "${node_r[subtype]}"
      type_r['subtype']=$TYPE
   fi

   declare -g TYPE="$type"
   declare -g NODE="$node"
}


function symtab_identifier {
   # Identifiers in this context are only used in typecasts.
   local -n node=$NODE
   local -- value="${node[value]}"
   copy_type "$NODE"  "$value"
}

#───────────────────────────────( merge trees )─────────────────────────────────
# After generating the symbol tables for the parent & child, iterate over the
# parent's, merging in nodes. I'm not 100% sure if this should be in the
# compiler.
#
# Merging is only necessary if the parent has %constrain statements.

# Gives friendly means of reporting to the user where an error has occurred.
# As we descend into each symtab, push its name to the stack. Print by doing a
# FQ_LOCATION.join('.')
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

   local -- p_sym_name="$1"
   local -- c_sym_name="$2"

   # We know the parent symbol exists. Can safely nameref it.
   local -n p_sym="$p_sym_name"

   # case 1.
   # Child section is missing, but was required in the parent.
   if [[ ! "$c_sym_name" ]] ; then
      if [[ "${p_sym[required]}" ]] ; then
         raise missing_required "$FQ_NAME"
      else
         # If child section was missing, but not required... nothing to do. We
         # gucci & scoochie.
         return 0
      fi
   fi

   local -n c_sym="$c_sym_name"
   local -n c_type="${c_sym[type]}"

   # case 2.
   # Found child node under the same identifier, but not a Section.
   if [[ ${c_type[kind]} != 'SECTION' ]] ; then
      raise symbol_mismatch "${FQ_NAME}"
   fi

   merge_symtab "${p_sym[node]}"  "${p_sym[symtab]}"  "${c_sym[symtab]}"
   #               ^-- parent node   ^-- parent symtab   ^-- child symtab
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
         raise missing_required
      else
         return 0
      fi
   fi

   local -n c_sym="$c_sym_name"

   # case 2a.
   # Expecting a variable declaration, child is actually a Section.
   local -n c_type="${c_sym[type]}" 
   if [[ "${c_type[kind]}" == 'SECTION' ]] ; then
      raise symbol_mismatch
   fi

   # case 2b.
   # The type of the child must defer to the type of the parent.
   if ! merge_type "${p_sym[type]}" "${c_sym[type]}" ; then
      raise symbol_mismatch
   fi

   # If we haven't hit any errors, can safely copy over the child's value to the
   # parent.
   local -n p_node="${p_sym[node]}" 
   local -n c_node="${c_sym[node]}" 
   if [[ "${c_node[expr]}" ]] ; then
      #  ┌── does not understand namerefs
      # shellcheck disable=SC2034
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
   # First match base types.
   [[ ${t1['kind']} != "${t2[kind]}" ]] && return 1

   # Then match subtypes.
   if [[ ${t1['subtype']} ]] ; then
      merge_type "${t1[subtype]}" "${t2[subtype]}"
      return $?
   fi

   return 0
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
   local -n symbol="${symtab[${name[value]}]}"
   SYMTAB="${symbol[symtab]}"

   local -n items="${node[items]}" 
   for each in "${items[@]}"; do
      walk_semantics $each
   done

   SYMTAB="$symtab_name"
   NODE=$save
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
   local -- symtab="$SYMTAB"
   local -n node_r="$NODE"

   walk_semantics "${node_r[left]}"
   local left_t="$TYPE"

   if ! type_equality  "$_SECTION"  "$left_t" ; then
      local msg=(
         "indexing with the \`>' operator requires"
         'the left hand side evaluate to a section.'
      )
      raise type_error "${node_r[left]}"  "${msg[@]}"
   fi

   walk_semantics "${node_r[right]}"

   declare -g SYMTAB="$symtab"
}


function semantics_index {
   local -n node="$NODE"

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
      if ! type_equality  "$_INTEGER"  "$type" ; then
         raise type_error "${node[right]}" "unary minus only supports integers."
      fi
   else
      raise parse_error "unary expressions aside from \`minus' are unsupported."
   fi

   declare -g TYPE="$type"
   declare -g NODE="$save"
}


function semantics_array {
   local -- node="$NODE"
   local -n node_r="$node"

   # Top-level array.
   copy_type "$_ARRAY"
   local -- array="$TYPE"
   local -n array_r="$array"

   # If the target type is specific (array:str), the actual type must conform to
   # that.
   local -A types_found=()
   for item in "${node_r[@]}" ; do
      walk_semantics "$item"
      local -n type=$TYPE
      local -- kind="${type[kind]}"

      array_r['subtype']="$TYPE"
      # For now we assume the array will have matching types throughout. If it
      # does, we don't have touch this. If we're wrong, we append each found
      # distinct type to `types_found[]`. If >1, set the subtype to ANY instead.

      types_found[$kind]='true'
   done

   if [[ ${#types_found[@]} -gt 1 ]] ; then
      # User has a mixed-type array. Give `any` type.
      copy_type "$_ANY"
      array_r['subtype']="$TYPE"
   fi

   declare -g TYPE="$array"
   declare -g NODE="$node"
}


function semantics_identifier {
   local -n node_r="$NODE"
   local -- name="${node_r[value]}"

   if ! symtab get "$name" ; then
      raise missing_var "$name"
   fi

   local -n symbol_r="$SYMBOL"
   copy_type "${symbol_r[type]}"
}

function semantics_path    { copy_type "$_PATH"    ;}
function semantics_boolean { copy_type "$_BOOLEAN" ;}
function semantics_integer { copy_type "$_INTEGER" ;}
function semantics_string  { copy_type "$_STRING"  ;}
