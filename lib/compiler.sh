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
      local dst="${EXPR_MAP[$ast_node]}"
      _walk_expr_compiler  "$ast_node"  "$dst"
   done

   # Fold around all the temporary SKELLY nodes. Leaves only data.
   undead_yoga '_SKELLY_1'
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
   local -n _s="$skelly"
   _s=()
}


function mk_skelly {
   # Creates a generic skeleton placeholder. This is overwritten in the
   # expression evaluation phase by the actual value & type.
   (( ++SKELLY_NUM ))
   local skelly="_SKELLY_${SKELLY_NUM}"
   declare -g "$skelly"
   declare -g SKELLY="$skelly"

   # Without a value, this isn't glob matched by a ${!_SKELLY_*}
   local -n _s="$skelly"
   _s=''
}


function walk_ref_compiler {
   declare -g NODE="$1"
   compile_ref_"${TYPEOF[$NODE]}"
}


function compile_ref_decl_section {
   # Save reference to current NODE. Restored at the end.
   local -- save=$NODE
   local -n node=$save

   # Create data dictionary object.
   mk_compile_dict
   local -- sname="$SKELLY"
   local -n skelly="$sname"

   local -n items="${node[items]}" 
   for decl_name in "${items[@]}"; do
      local -n var_decl="$decl_name"
      local -n _name="${var_decl[name]}"
      local -- name="${_name[value]}"

      # Variable declarations will create a placeholder skelly, whilst sections
      # will generate an associate array with sub-skellies.
      walk_ref_compiler "$decl_name"
      skelly[$name]="$SKELLY"
   done

   # Add mapping from _NODE_$n -> _SKELLY_$n.
   EXPR_MAP["$save"]="$sname"

   declare -g SKELLY="$skelly"
   declare -g NODE="$save"
}


function compile_ref_decl_variable {
   local -- save="$NODE"
   local -n node="$save"

   # Create skeleton node to be inserted into the parent section, and add
   # mapping from the AST node to the output skeleton node.
   mk_skelly
   EXPR_MAP["$save"]="$SKELLY"

   # Create global "${SKELLY}_DEPS" array holding all the dependencies we run
   # into downstream.
   mk_dependency "$save"

   # TODO: Need to think this through a little more. Don't know if I love the
   # concept of having a "global" scope that's distinct from the `%inline`
   # scope.
   declare -g SYMTAB="$INLINE"
   if [[ -n ${node[expr]} ]] ; then
      walk_ref_compiler "${node[expr]}"
   fi

   declare -g NODE="$save"
}


function compile_ref_typecast {
   local -n node="$NODE"
   walk_ref_compiler "${node[expr]}" 
}


function compile_ref_index {
   local -n node=$NODE
   walk_ref_compiler "${node[left]}"
   walk_ref_compiler "${node[right]}"
}


function compile_ref_unary {
   local -n node=$NODE
   walk_ref_compiler "${node[right]}"
}


function compile_ref_array {
   local -n node=$NODE
   for ast_node in "${node[@]}"; do
      walk_ref_compiler "$ast_node"
   done
}


function compile_ref_identifier {
   local -- symtab="$SYMTAB"
   local -- save="$NODE"

   # Get identifier name.
   local -n node="$NODE"
   local -- name="${node[value]}"

   # Descend to new symbol table.
   local -n symtab="$SYMTAB"
   local -n symbol="${symtab[$name]}"

   if [[ "${symbol[symtab]}" ]] ; then
      declare -g SYMTAB="${symbol[symtab]}"
   fi

   # Add self as dependency.
   local -n dep="$DEPENDENCY"
   dep+=( "${symbol[node]}" )
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

      local -- ast_node="${dep_node/DEP_/}"
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
   local   --  dname="_DATA_${DATA_NUM}"
   declare -ga $dname
   declare -g  DATA=$dname

   # Without a value, this isn't glob matched by a ${!_SKELLY_*}
   local -n _d="$dname"
   _d=()
}


# This is the function that's actually called to initiate the expression
# evaluation. To simplify things, all compilation steps are wrapped by the
# `walk_compiler` function.
function _walk_expr_compiler {
   local -- src="$1"
   local -n dst="$2"

   # XXX: Gotta come up with a better way of doing this. Currently need to
   #      reset the symbol table between each time we're calling this phase of
   #      the compiler, as indices leaves us in an inner scope.
   declare -g SYMTAB="$INLINE"

   walk_expr_compiler "$src"
   dst="$DATA"
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


function compile_expr_index {
   # An 'index' is a combination of...
   #    .left   subscriptable expression (section, array)
   #    .right  index expression (identifier, integer)
   local -n node="$NODE"

   walk_expr_compiler "${node[left]}" 
   local -n left="$DATA"

   walk_expr_compiler "${node[right]}"
   local -- right="$DATA"

   declare -g DATA="${left[$right]}"
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
   local -n node="$NODE"
   local -- name="${node[value]}"

   # Look up the AST node referred to by this identifier. Given:
   #
   #> a: 1;
   #> b: a;
   #
   # This function would be called on line 2 for the reference to `a`.
   #
   local -n symtab="$SYMTAB"
   local -n symbol="${symtab[$name]}"
   local -- ast_node="${symbol[node]}"

   # Resolve the reference in the EXPR_MAP. Given:
   #
   #> EXPR_MAP=(
   #>    [NODE_1]="SKELLY_1"
   #> )
   #> SKELLY_1="1"
   #
   # Resolves `a` -> SKELLY_1 -> "1".
   #
   local -n data="${EXPR_MAP[$ast_node]}"
   declare -g DATA="$data"
}

#─────────────────────────────( skeleton to data )──────────────────────────────
# Folds around the intermediate SKELLY nodes, resulting in the raw data. 

function undead_yoga {
   local -n src="$1"

   for key in "${!src[@]}" ; do
      local skelly="${src[$key]}"

      if [[ ${IS_SECTION[$skelly]} ]] ; then
         undead_yoga "$skelly"
      else
         local -n val="$skelly"
         src[$key]="$val"
         unset $skelly
      fi
   done
}
