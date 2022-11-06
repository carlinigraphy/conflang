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
   
   #declare -p ${!_SKELLY_*}
   #declare -p EXPR_MAP

   for ast_node in "${ORDERED_DEPS[@]}" ; do
      local -n dst="${EXPR_MAP[$ast_node]}"
      walk_expr_compiler "$ast_node"
      dst="$DATA"
   done

   # Fold around all the temporary SKELLY nodes. Leaves only data.
   declare -g _SKELLY_ROOT="$_SKELLY_1"
   undead_yoga "$_SKELLY_ROOT"

   # Clean up the generated output. The nodes _SKELLY_{1,2} are uselessly
   # referring to the '%inline' implicit section. Can't unset during
   # `undead_yoga`, as two references may point to the same intermediate node.
   # Clean up my skeleton army afterwards.
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
declare -gA DEPTH_MAP=()
declare -ga ORDERED_DEPS=()
# ^-- This is where dependencies go during the reference phase of the compiler.
# Each variable declaration also creates an array to hold everything it depends
# upon. Before the 2nd phase, they're sorted into ORDERED_DEPS[].
#
# Order is DEPENDENCY -> UNORDERED_DEPS[] -> DEPTH_MAP{} -> ORDERED_DEPS[]

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

   # Without a value, this isn't glob matched by a ${!_SKELLY_*}. Can't assign
   # in the initial `declare -g` as you can with strings values.
   local -n s="$skelly" ; s=()
}


function mk_skelly {
   (( ++SKELLY_NUM ))
   local skelly="_SKELLY_${SKELLY_NUM}"
   declare -g "$skelly"=''
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
   #> Section { key; }      # Compiles to...
   #
   #> _ROOT=(
   #>    [Section]="_SKELLY_1"
   #> )
   #> _SKELLY_1="_SKELLY_2"
   #> _SKELLY_2=(
   #>    [key]=''
   #> )
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

   local symtab="$SYMTAB"
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
   declare -g SYMTAB="$symtab"
}


function compile_ref_decl_variable {
   local -n node_r="$NODE"

   # Create skeleton node to be inserted into the parent section, and add
   # mapping from the AST node to the output skeleton node.
   mk_skelly
   EXPR_MAP["$NODE"]="$SKELLY"

   # Create global "${SKELLY}_DEPS" array holding all the dependencies we run
   # into downstream.
   mk_dependency "$NODE"

   if [[ -n ${node_r[expr]} ]] ; then
      walk_ref_compiler "${node_r[expr]}"
   fi
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
   # Get identifier name.
   local -n node_r="$NODE"
   local -- name="${node_r[value]}"

   symtab get "$name"
   local -n symbol_r="$SYMBOL"

   # Add variable target as a dependency.
   local -- target="${symbol_r[node]}" 
   local -n dep="$DEPENDENCY"
   dep+=( "$target" )

   symtab from "$target"
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
      DEPTH_MAP[$ast_node]="$DEPTH"
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

   while (( ${#DEPTH_MAP[@]} )) ; do
      for ast_node in "${!DEPTH_MAP[@]}" ; do
         depth="${DEPTH_MAP[$ast_node]}"
         if (( depth == i )) ; then
            unset 'DEPTH_MAP[$ast_node]'
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
   local -n node_r="$NODE"
   local -n items_r="${node_r[items]}" 
   for ast_node in "${items_r[@]}"; do
      walk_expr_compiler "$ast_node"
   done
}


function compile_expr_decl_variable {
   local -n node_r="$NODE"
   if [[ -n ${node_r[expr]} ]] ; then
      walk_expr_compiler "${node_r[expr]}"
   fi
}


function compile_expr_typecast {
   local -n node_r="$NODE"
   walk_expr_compiler "${node_r[expr]}" 
}


function compile_expr_member {
   # A 'member' is a combination of...
   #    .left   section
   #    .right  identifier
   local -n node_r="$NODE"

   walk_expr_compiler "${node_r[left]}" 
   local -n left_r="$DATA"

   local -n right_r="${node_r[right]}"
   local name="${right_r[value]}"

   # left[name] points to the intermediate skelly node. Need to go one
   # additional level of indirection past that.
   local -n rv="${left_r[$name]}"
   declare -g DATA="$rv"
}


function compile_expr_index {
   # An 'index' is a combination of...
   #    .left   array
   #    .right  integer
   local -n node_r="$NODE"

   walk_expr_compiler "${node_r[left]}" 
   local -n left_r="$DATA"

   local -n right_r="${node_r[right]}"
   local integer="${right_r[value]}"

   declare -g DATA="${left_r[$integer]}"
}


function compile_expr_unary {
   local -n node_r="$NODE"
   walk_expr_compiler "${node_r[right]}"
   (( DATA = DATA * -1 ))
}


function compile_expr_array {
   local -n node_r="$NODE"

   mk_compile_array
   local -- array="$DATA"
   local -n array_r="$DATA"

   for ast_node in "${node_r[@]}"; do
      walk_expr_compiler "$ast_node"
      array_r+=( "$DATA" )
   done

   declare -g DATA="$array"
}


function compile_expr_boolean {
   local -n node_r="$NODE"
   declare -g DATA="${node_r[value]}"
}


function compile_expr_integer {
   local -n node_r="$NODE"
   declare -g DATA="${node_r[value]}"
}


function compile_expr_string {
   local -n node_r="$NODE"
   local -- string="${node_r[value]}"

   while [[ "${node_r[concat]}" ]] ; do
      walk_expr_compiler "${node_r[concat]}"
      string+="$DATA"
      local -n node="${node_r[concat]}"
   done

   declare -g DATA="$string"
}


function compile_expr_path {
   local -n node_r=$NODE
   local -- path="${node_r[value]}"

   while [[ "${node_r[concat]}" ]] ; do
      walk_expr_compiler "${node_r[concat]}"
      path+="$DATA"
      local -n node="${node_r[concat]}"
   done

   declare -g DATA="$path"
}


function compile_expr_env_var {
   local -n node_r="$NODE"
   local -- ident="${node_r[value]}" 

   if [[ ! "${SNAPSHOT[$ident]+_}" ]] ; then
      raise missing_env_var "$ident"
   fi

   declare -g DATA="${SNAPSHOT[$ident]}"
}


function compile_expr_identifier {
   # Pull identifier's name out of the AST node.
   local -n node_r="$NODE"
   local -- name="${node_r[value]}"

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
      local skelly="${src_r[$key]}"
      local -n skelly_r="$skelly"

      if [[ ${IS_SECTION[$skelly_r]} ]] ; then
         undead_yoga "$skelly_r"
      fi

      src_r[$key]="$skelly_r"
   done
}
