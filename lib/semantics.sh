#!/bin/bash

function mk_metatype {
   local name="$1"
   local kind="$2"
   local complex="$3"

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
   symbol['name']="$name"
}


function populate_globals {
   local -n symtab="$SYMTAB"

   local -A primitive=(
      [any]='ANY'
      [fn]='FUNCTION'
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
      mk_metatype "$short_name"  "${primitive[$short_name]}"
      symtab[$short_name]="$SYMBOL"
   done

   # Create symbols for complex types.
   for short_name in "${!complex[@]}" ; do
      mk_metatype "$short_name"  "${complex[$short_name]}"  'complex'
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


function extract_type {
   # Pulls the underlying Type from a meta type declaration in the GLOBALS
   # symbol table. Gotta query  symbol.type.subtype:
   #
   #> Symbol {
   #>    Type {
   #>       kind: "TYPE"
   #>       subtype: Type {
   #>          kind: "(ARRAY|INTEGER|...)"
   #>       }
   #>    }
   #> }

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


function create_ffi_symbol {
   local -n path="$1"
   local -- fn_name="$2"

   local file_idx="${path[file]}"
   local dir="${FILES[$file_idx]%/*}"

   local loc="${dir}/${path[value]}"      # Full path to the .sh file itself
   local exe="${loc##*/}"                 # The `basename`, also the prefix of
                                          # the -test/directive function names
   if [[ ! -d "$loc" ]] ; then
      echo "Package [$loc] not found."
      exit 1
   fi

   test_file="${loc}/${exe}"-test.sh
   directive_file="${loc}/${exe}"-directive.sh

   if [[ -e "$test_file" ]] ; then
      #  ┌── ignore non-source file.
      # shellcheck disable=SC1090
      source "$test_file" || {
         raise source_failure  "$test_file"
      }
      hash_t=$( md5sum "$test_file" )
      hash_t="_${hash_t%% *}"
   fi

   if [[ -e "$directive_file" ]] ; then
      #  ┌── ignore non-source file.
      # shellcheck disable=SC1090
      source "$directive_file" || {
         raise source_failure  "$directive_file"
      }
      hash_d=$( md5sum "$directive_file" )
      hash_d="_${hash_t%% *}"
   fi

   fn=$( declare -f ${exe}-test )
   eval "${fn/${exe}-test/$hash_t}"

   fn=$( declare -f ${exe}-directive )
   eval "${fn/${exe}-directive/$hash_d}"

   mk_symbol
   local -- symbol_name="$SYMBOL"
   local -n symbol="$symbol_name"

   extract_type 'fn'
   symbol['name']="$fn_name"
   symbol['type']="$TYPE"
   symbol['test']="$hash_t"
   symbol['directive']="$hash_d"
   symbol['signature']=
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
   symbol['node']=$node_name

   # Get string value of identifier node.
   local -- identifier_node=${node[name]}
   local -n identifier=$identifier_node
   local -- name="${identifier[value]}"
   symbol['name']="$name"

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
   symbol['name']="$name"

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

      # See ./doc/truth.sh for an explanation on the test below. Tests if the
      # type either has a populated .subtype field, or the field is SET, but
      # empty.
      if [[ ! "${node['subtype']+_}" ]] && \
         [[ ! "${node['subtype']}"   ]]
      then
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
      echo "t1[subtype]=${t1[subtype]}  t2[subtype]=${t2[subtype]}"
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

   # If there's no type declaration, or expression, there's nothing to do in
   # this phase.
   [[ ! ${node[type]} || ! ${node[expr]} ]] && return

   # Sets target type. The type of the expression should match the type of
   # the typedef in the symbol table.
   walk_semantics "${node[type]}"
   local target="$TYPE"

   # Sets TYPE
   walk_semantics "${node[expr]}"
   local actual="$TYPE"

   if ! type_equality  "$target"  "$actual" ; then
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

   declare -g TYPE="$tname"
   declare -g NODE="$save"
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
   local -- array_name=$TYPE
   local -n array="$array_name"

   # The user *can* have an array of differing types, but not if the type is
   # declared with a subtype. E.g, `array:str`.
   local -A types_found=()

   for item in "${node[@]}" ; do
      walk_semantics "$item"
      local -n type=$TYPE
      local -- kind="${type[kind]}"

      array['subtype']="$TYPE"
      # For now we assume the array will have matching types throughout. If it
      # does, we don't have touch this. If we're wrong, we append each found
      # distinct type to `types_found[]`. If >1, set the subtype to ANY instead.

      types_found[$kind]='yes'
   done

   if [[ ${#types_found[@]} -gt 1 ]] ; then
      # Maybe bad case. User has a mixed-type array. Give `any` type.
      extract_type 'any'
      array['subtype']="$TYPE"
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
   extract_type 'path'
}

function semantics_boolean {
   extract_type 'bool'
}

function semantics_integer {
   extract_type 'int'
}

function semantics_string {
   extract_type 'str'
}
