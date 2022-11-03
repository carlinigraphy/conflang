#!/bin/bash
#
# Requires from environment:
#  TYPEOF{}
#  NODE_*
#  SECTION
#  ^-- Name of the section we're currently in. After we've iterated through a
#    pair of symtabs, any keys remaining in the child should be copied over to
#   the parent. We must both copy the key:value from the symtab (for semantic
#    analysis in the next phase), but also need to append the nodes themselves
#    to the parent section's .items array.

# Abstract away all the stuff below.
function walk_compiler {
   walk_ref_compiler "$1"

   dependency_to_map
   dependency_sort

   for ast_node in "${ORDERED_DEPS[@]}" ; do
      local -n dst="${EXPR_MAP[$ast_node]}"
      walk_expr_compiler "$ast_node"
      dst="$DATA"
   done

   # Clean up the generated output. The nodes _SKELLY_{1,2} are uselessly
   # referring to the '%inline' implicit section.
   declare -g _SKELLY_ROOT="$_SKELLY_1"
   unset '$_SKELLY_1'

   # Fold around all the temporary SKELLY nodes. Leaves only data.
   undead_yoga "$_SKELLY_ROOT"

   # Can't unset during `undead_yoga`, as two references may point to the same
   # intermediate node. Clean up my skeleton army afterwards.
   for skelly in "${DISPOSABLE_SKELETONS[@]}" ; do
      unset "$skelly"
   done
}


#─────────────────────────( make skeleton, log refs )───────────────────────────
# 1. Builds the "skeleton" of the tree.
#    a. Associative array node for all sections
#    b. Key in the section w/ node assigned
#    c. Placeholder assigned node is empty, to be filled next pass
# 2. Create EXPR_MAP{ AST_NODE -> DATA_NODE }
# 3. Create dependency tree

declare -g  SKELLY=
declare -gi SKELLY_NUM=0
declare -ga DISPOSABLE_SKELETONS=()

declare -gA IS_SECTION=()
# To determine if a disposable skelly is referencing a Section. Necessary when
# walking the result in `undead_yoga`.

declare -gA EXPR_MAP=()
# Mapping from NODE_$n -> _SKELLY_$n

declare -g  DEPENDENCY=
declare -ga UNORDERED_DEPS=()
declare -gA DEPS_MAP=()
declare -ga ORDERED_DEPS=()
# ^-- This is where dependencies go during the reference phase of the compiler.
# Each variable declaration also creates an array to hold everything it depends
# upon. Before the 2nd phase, they're sorted into ORDERED_DEPS[].
#
# Order is DEPEND -> UNORDERED_DEPS[] -> DEPS_MAP{} -> ORDERED_DEPS[]

function mk_dependency {
   local dep="DEP_${1}"
   declare -ga "$dep"
   declare -g  DEPENDENCY="$dep"
   UNORDERED_DEPS+=( "$dep" )
}


function mk_compile_dict {
   (( ++SKELLY_NUM ))
   local skelly="_SKELLY_${SKELLY_NUM}"
   declare -gA "$skelly"
   declare -g  SKELLY="$skelly"

   # Without a value, this isn't glob matched by a ${!_SKELLY_*}
   local -n s="$skelly" ; s=()
}


function mk_skelly {
   (( ++SKELLY_NUM ))
   local skelly="_SKELLY_${SKELLY_NUM}"
   declare -g "$skelly"
   declare -g SKELLY="$skelly"

   # Allows us to clean up after ourselves. After evaluating everything, these
   # will be dead references, pointing to nothing.
   DISPOSABLE_SKELETONS+=( "$skelly" ) 
}


function walk_ref_compiler {
   declare -g NODE="$1"
   compile_ref_"${TYPEOF[$NODE]}"
}


function compile_ref_decl_section {
   local -- node="$NODE"
   local -n node_r="$node"

   # Add mapping from _NODE_$n -> _SKELLY_$n. Need one level of indirection to
   # be able to refer to this node.
   #
   #> Section { key; }
   #>--
   #> _ROOT=(
   #>    [Section]=_SKELLY_1
   #> )
   #> _SKELLY_1=_SKELLY_2
   #> _SKELLY_2=(
   #>    [key]=''
   #> )
   #>--
   #
   # In which  _SKELLY_1 :: middle_skelly
   #           _SKELLY_2 :: dict_skelly
   #
   mk_skelly                                 #< _SKELLY_1
   local -- middle_skelly="$SKELLY"
   local -n middle_skelly_r="$middle_skelly"

   mk_compile_dict                           #< _SKELLY_2
   local -- dict_skelly="$SKELLY"
   local -n dict_skelly_r="$dict_skelly"

   middle_skelly_r="$dict_skelly"            #< _SKELLY_1="_SKELLY_2"
   EXPR_MAP[$node]="$middle_skelly"
   IS_SECTION[$dict_skelly]='yes'

   # Save current symtab
   local symtab="$SYMTAB"

   # Load new one from $NODE.
   symtab from "$node"

   local -n items_r="${node_r[items]}" 
   for var_decl in "${items_r[@]}"; do
      local -n var_decl_r="$var_decl"
      local -n name_r="${var_decl_r[name]}"
      local -- name="${name_r[value]}"

      walk_ref_compiler "$var_decl"
      dict_skelly_r[$name]="$SKELLY"
   done

   declare -g SKELLY="$middle_skelly"
   declare -g NODE="$node"
   declare -g SYMTAB="$symtab"
}


function compile_ref_decl_variable {
   local -- node="$NODE"
   local -n node_r="$node"

   # Create skeleton node to be inserted into the parent section, and add
   # mapping from the AST node to the output skeleton node.
   mk_skelly
   EXPR_MAP["$node"]="$SKELLY"

   # Create global "${SKELLY}_DEPS" array holding all the dependencies we run
   # into downstream.
   mk_dependency "$node"

   if [[ -n ${node_r[expr]} ]] ; then
      walk_ref_compiler "${node_r[expr]}"
   fi

   declare -g NODE="$node"
}


function compile_ref_typecast {
   local -n node_r="$NODE"
   walk_ref_compiler "${node_r[expr]}" 
}


function compile_ref_member {
   local -n node_r=$NODE
   walk_ref_compiler "${node_r[left]}"
   walk_ref_compiler "${node_r[right]}"
}


function compile_ref_index {
   local -n node_r=$NODE
   walk_ref_compiler "${node_r[left]}"
   walk_ref_compiler "${node_r[right]}"
}


function compile_ref_unary {
   local -n node_r=$NODE
   walk_ref_compiler "${node_r[right]}"
}


function compile_ref_array {
   local -n node_r=$NODE
   for ast_node in "${node_r[@]}"; do
      walk_ref_compiler "$ast_node"
   done
}


function compile_ref_identifier {
   local -n dep="$DEPENDENCY"

   # Get identifier name.
   local -n node_r="$NODE"
   local -- name="${node_r[value]}"

   symtab get "$name"
   local -n symbol_r="$SYMBOL"

   # Add self as dependency.
   dep+=( "${symbol_r[node]}" )
}


function compile_ref_boolean { :; }
function compile_ref_integer { :; }
function compile_ref_string  { :; }
function compile_ref_path    { :; }
function compile_ref_env_var { :; }


#────────────────────────────( order dependencies )─────────────────────────────
declare -gi DEPTH=0

function dependency_to_map {
   for dep_node in "${UNORDERED_DEPS[@]}" ; do
      dependency_depth "$dep_node"

      local ast_node="${dep_node/DEP_/}"
      DEPS_MAP[$ast_node]="$DEPTH"
   done
}


function dependency_depth {
   local -n node="$1"
   local -i level="${2:-0}"

   # When we've reached the end of a dependency chain, return the accumulated
   # depth level.
   if ! (( ${#node[@]} )) ; then
      DEPTH="$level" ; return
   fi

   (( ++level ))

   local -a sub_levels=()
   for ast_node in "${node[@]}" ; do
      dependency_depth "DEP_${ast_node}"  "$level"
      sub_levels+=( "$DEPTH" )
   done

   local -i max="${sub_levels[0]}"
   for n in "${sub_levels[@]}" ; do
      (( max = (n > max)? n : max ))
   done

   declare -g DEPTH="$max"
}


function dependency_sort {
   local -i  i=0  depth=0

   while (( ${#DEPS_MAP[@]} )) ; do
      for ast_node in "${!DEPS_MAP[@]}" ; do
         depth="${DEPS_MAP[$ast_node]}"
         if (( depth == i )) ; then
            unset 'DEPS_MAP[$ast_node]'
            ORDERED_DEPS+=( "$ast_node" )
         fi
      done
      (( ++i ))
   done
}


#───────────────────────────( evaluate expressions )────────────────────────────
declare -g  DATA=
declare -gi DATA_NUM=0


function mk_compile_array {
   (( ++DATA_NUM ))
   local data="_DATA_${DATA_NUM}"

   declare -ga "$data"
   declare -g  DATA="$data"

   # Without a value, this isn't glob matched by a ${!_DATA_*}. Necessary for
   # dumping to $DATA_OUT.
   local -n d="$data" ; d=()
}


function walk_expr_compiler {
   declare -g NODE="$1"
   compile_expr_"${TYPEOF[$NODE]}"
}


function compile_expr_decl_section {
   # Save reference to current NODE. Restored at the end.
   local -- save=$NODE
   local -n node=$save

   local -n items="${node[items]}" 
   for var_decl in "${items[@]}"; do
      walk_expr_compiler "$var_decl"
   done

   declare -g NODE="$save"
}


function compile_expr_decl_variable {
   local -- save=$NODE
   local -n node=$save

   if [[ -n ${node[expr]} ]] ; then
      walk_expr_compiler "${node[expr]}"
   fi

   declare -g NODE="$save"
}


function compile_expr_typecast {
   local -n node="$NODE"
   walk_expr_compiler "${node[expr]}" 
}


function compile_expr_member {
   # A 'member' is a combination of...
   #    .left   section
   #    .right  identifier
   local -n node_r="$NODE"

   walk_expr_compiler "${node_r[left]}" 
   local -n left_r="$DATA"

   local -n right_r="${node_r[right]}"
   local -- name="${right_r[value]}"

   declare -g DATA="${left_r[$name]}"
}


function compile_expr_index {
   # An 'index' is a combination of...
   #    .left   array
   #    .right  integer
   local -n node_r="$NODE"

   walk_expr_compiler "${node_r[left]}" 
   local -n left_r="$DATA"

   local -n right_r="${node_r[right]}"
   local -- integer="${right_r[value]}"

   declare -g DATA="${left_r[$integer]}"
}


function compile_expr_unary {
   local -- save=$NODE
   local -n node=$save

   walk_expr_compiler "${node[right]}"
   (( DATA = DATA * -1 ))
}


function compile_expr_array {
   local -- save="$NODE"
   local -n node="$save"

   mk_compile_array
   local -- array_name="$DATA"
   local -n array="$DATA"

   for ast_node in "${node[@]}"; do
      walk_expr_compiler "$ast_node"
      array+=( "$DATA" )
   done

   declare -g DATA="$array_name"
   declare -g NODE="$save"
}


function compile_expr_boolean {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


function compile_expr_integer {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


function compile_expr_string {
   local -n node=$NODE
   local -- string="${node[value]}"

   while [[ "${node[concat]}" ]] ; do
      walk_expr_compiler "${node[concat]}"
      string+="$DATA"
      local -n node="${node[concat]}"
   done

   declare -g DATA="$string"
}


function compile_expr_path {
   local -n node=$NODE
   local -- path="${node[value]}"

   while [[ "${node[concat]}" ]] ; do
      walk_expr_compiler "${node[concat]}"
      path+="$DATA"
      local -n node="${node[concat]}"
   done

   declare -g DATA="$path"
}


function compile_expr_env_var {
   local -n node=$NODE
   local -- var_name="${node[value]}" 

   if [[ ! "${SNAPSHOT[$var_name]+_}" ]] ; then
      raise missing_env_var "$var_name"
   fi

   declare -g DATA="${SNAPSHOT[$var_name]}"
}


function compile_expr_identifier {
   # Pull identifier's name out of the AST node.
   local -n node_r="$NODE"
   local -- name="${node_r[value]}"

   echo "COMPILING: $name"

   # Look up the AST node referred to by this identifier. Given:
   #
   #> a: 1;
   #> b: a;
   #
   # This function would be called on line 2 for the reference to `a`.
   #
   symtab from "$NODE"
   symtab get "$name"
   local -n symbol_r="$SYMBOL"
   local -- ast_node="${symbol_r[node]}"

   # Resolve the reference in the EXPR_MAP. Given:
   #
   #> EXPR_MAP=(
   #>    [NODE_1]="DATA_1"
   #> )
   #> DATA_1="1"
   #
   # Resolves `a` -> DATA_1 -> "1".
   #
   local -n data_r="${EXPR_MAP[$ast_node]}"
   declare -g DATA="$data_r"
}

#─────────────────────────────( skeleton to data )──────────────────────────────
# Folds around the intermediate SKELLY nodes, resulting in the raw data. 

function undead_yoga {
   local -n src_r="$1"

   local key
   for key in "${!src_r[@]}" ; do
      local -- middle="${src_r[$key]}"
      local -n middle_r="$middle"

      if [[ ${IS_SECTION[$middle_r]} ]] ; then
         undead_yoga "$middle_r"
      fi

      src_r[$key]="$middle_r"
   done
}
