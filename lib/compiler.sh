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

#─────────────────────────( make skeleton, log refs )───────────────────────────
# 1. Builds the "skeleton" of the tree.
#    a. Associative array node for all sections
#    b. Key in the section w/ node assigned
#    c. Placeholder assigned node is empty, to be filled next pass
# 2. Create EXPR_MAP{ AST_NODE -> DATA_NODE }
# 3. Create dependency tree
declare -g  SKELLY=
declare -gi SKELLY_NUM=0

declare -g  DEP=
declare -ga DEPENDENCIES=()
declare -ga UNORDERED_DEPS=()
# ^-- This is where dependencies go during the reference phase of the compiler.
# Each variable declaration also creates an array to hold everything it depends
# upon. Before the 2nd phase, they're sorted into DEPENDENCIES[].

function mk_dep {
   local dep="DEP_${1}"
   declare -ga "$dep"
   declare -g  DEP="$dep"
   UNORDERED_DEPS+=( "$dep" )
}


function mk_compile_dict {
   (( ++SKELLY_NUM ))
   local skelly="_SKELLY_${SKELLY_NUM}"
   declare -gA "$skelly"
   declare -g  SKELLY="$skelly"
}


function mk_skelly {
   # Creates a generic skeleton placeholder. This is overwritten in the
   # expression evaluation phase by the actual value & type.
   (( ++SKELLY_NUM ))
   local skelly="_SKELLY_${SKELLY_NUM}"
   declare -g "$skelly"
   declare -g SKELLY="$skelly"
}


function walk_ref_compiler {
   declare -g NODE="$1"
   compile_ref_"${TYPEOF[$NODE]}"
}


function compile_ref_decl_section {
   # Save reference to current NODE. Restored at the end.
   local -- save=$NODE
   local -n node=$save
   local -n name="${node[name]}"

   # Create data dictionary object.
   mk_compile_dict
   local -- skelly=$SKELLY
   local -n skeleton=$SKELLY

   local -n items="${node[items]}" 
   for var_decl in "${items[@]}"; do
      local -n _name="${var_decl[name]}"
      local -- name="${_name[value]}"

      # Variable declarations will create a placeholder skelly, whilst sections
      # will generate an associate array with sub-skellies.
      walk_ref_compiler
      data[name]="$SKELLY"
   done

   # Add mapping from _NODE_$n -> _SKELLY_$n.
   EXPR_MAP["$save"]="$skelly"

   declare -g SKELLY="$skelly"
   declare -g NODE="$save"
}


function compile_ref_decl_variable {
   local -- symtab="$SYMTAB"
   local -- save=$NODE
   local -n node=$save

   # Create skeleton node to be inserted into the parent section, and add
   # mapping from the AST node to the output skeleton node.
   mk_skelly
   EXPR_MAP["$save_node"]="$SKELLY"

   # Create global "${SKELLY}_DEPS" array holding all the dependencies we run
   # into downstream.
   mk_dep "$save"

   if [[ -n ${node[expr]} ]] ; then
      walk_ref_compiler "${node[expr]}"
   fi

   declare -g SYMTAB="$symtab"
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

   # Add self as dependency.
   local -n dep="$DEP"
   dep+=( "$save" )

   # Get identifier name.
   local -n node="$NODE"
   local -- _name="${node[name]}"
   local -n name="${_name[value]}"
   
   # Descend to new symbol table.
   local -n symtab="${SYMTAB}"
   local -n symbol="${symtab[$name]}"
   local -n new_scope="${symbol[symtab]}"
   declare -g SYMTAB="$new_scope"
}


function compile_ref_boolean { :; }
function compile_ref_integer { :; }
function compile_ref_string  { :; }
function compile_ref_path    { :; }
function compile_ref_env_var { :; }


#───────────────────────────( evaluate expressions )────────────────────────────
# Now we can largely evaluate linearly over the ordered

# THINKIES:
# I think we're going to need to have the skeleton nodes always point to the
# data node. Don't repurpose them, or assign actual expressions to them. They
# only serve as a useless sentinel that allows us to globally reference them.
# Probably should rename them to "middle management". They don't deserve to be
# my skelly army.


function mk_compile_array {
   (( ++SKELLY_NUM ))
   local   --  dname="_SKELLY_${SKELLY_NUM}"
   declare -ga $dname
   declare -g  SKELLY=$dname
}


function walk_expr_compiler { :; }


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
   local -n left="$SKELLY"

   walk_expr_compiler "${node[right]}"
   local -- right="$SKELLY"

   SKELLY="${left[$right]}"
   EXPR_MAP["$NODE"]="$SKELLY"
}


function compile_expr_unary {
   local -- save=$NODE
   local -n node=$save

   walk_expr_compiler "${node[right]}"
   local -i rhs=$SKELLY

   declare -g NODE=$save
   EXPR_MAP["$NODE"]="$SKELLY"
}


function compile_expr_array {
   local -- save=$NODE
   local -n node=$save

   mk_compile_array
   local -- dname=$SKELLY
   local -n data=$SKELLY

   for nname in "${node[@]}"; do
      walk_expr_compiler "$nname"
      data+=( "$SKELLY" )
   done

   declare -g SKELLY=$dname
   declare -g NODE=$save
   EXPR_MAP["$NODE"]="$SKELLY"
}


function compile_expr_boolean {
   local -n node=$NODE
   declare -g SKELLY="${node[value]}"
   EXPR_MAP["$NODE"]="$SKELLY"
}


function compile_expr_integer {
   local -n node=$NODE
   declare -g SKELLY="${node[value]}"
   EXPR_MAP["$NODE"]="$SKELLY"
}


function compile_expr_string {
   local -n node=$NODE
   local -- string="${node[value]}"

   while [[ "${node[concat]}" ]] ; do
      walk_expr_compiler "${node[concat]}"
      string+="$SKELLY"
      local -n node="${node[concat]}"
   done

   declare -g SKELLY="$string"
   EXPR_MAP["$NODE"]="$SKELLY"
}


function compile_expr_path {
   local -n node=$NODE
   local -- path="${node[value]}"

   while [[ "${node[concat]}" ]] ; do
      walk_expr_compiler "${node[concat]}"
      path+="$SKELLY"
      local -n node="${node[concat]}"
   done

   declare -g SKELLY="$path"
   EXPR_MAP["$NODE"]="$SKELLY"
}


function compile_expr_env_var {
   local -n node=$NODE
   local -- var_name="${node[value]}" 

   if [[ ! "${SNAPSHOT[$var_name]+_}" ]] ; then
      raise missing_env_var "$var_name"
   fi

   declare -g SKELLY="${SNAPSHOT[$var_name]}"
   EXPR_MAP["$NODE"]="$SKELLY"
}


function compile_expr_identifier {
   # Add this node to the reference map. Unset once resolved in the next stage
   # of the compiler.
   REF_MAP[$NODE]=''

   # Also needed in the expression map, in case one reference points to another.
   EXPR_MAP[$NODE]=''
}

#─────────────────────────────( skeleton to data )──────────────────────────────
# Need to walk the resulting skelly-tree, and convert to a data-tree. Really
# it's just reducing all the intermediate/placeholder nodes with their actual
# values.
#
#> S {
#>    key;
#>    key2: [1, 2];
#> }
#
#
#> declare -A _ROOT=(
#>    [S]=SKELLY_1
#> )
#> declare -A SKELLY_1=(
#>    [key]=SKELLY_2
#>    [key2]=SKELLY_3
#> )
#> declare -- SKELLY_2=
#> declare -a SKELLY_3=(
#>    SKELLY_4
#>    SKELLY_5
#> )
#> declare -- SKELLY_4=1
#> declare -- SKELLY_5=2
#
#
#> declare -A _ROOT=(
#>    [S]=DATA_1
#> )
#> declare -A DATA_1=(
#>    [key]=''
#>    [key2]=DATA_2
#> )
#> declare -a DATA_2=( 1 2 )
#
# For this we may actually need a SKELLY_TYPE{} map.
#> SKELLY_TYPE = {
#>    _ROOT    : '-gA'
#>    SKELLY_1 : '-gA'
#>    SKELLY_2 : '-g'
#>    SKELLY_3 : '-ga'
#>    SKELLY_4 : '-g'
#>    SKELLY_5 : '-g'
#> }
#
# Can then easily create the new data nodes.
#> declare -gA _DATA_ROOT=()
#> declare -gn src=_ROOT
#> declare -gn dst=_DATA_ROOT
#> 
#> for key in "${src[@]}" ; do
#>    val="${src[$key]}"
#>    type="${SKELLY_TYPE[$val]}"
#> 
#>    (( ++DATA_NUM ))
#>    declare DATA="_DATA_${DATA_NUM}"
#>    declare $type "_DATA_${DATA_NUM}"
#> 
#>    # Hmmmmmm.
#> done
#
#
# May honestly just instead want to "move" the values in by one. Replace the
# pointer to the leaf node with the value of the leaf node itself. Though this
# still does leave a ton of dangling unused variables. Could go through and
# unset them based on the map. Anything that only has a value, rather than a
# pointer, can be unset?
#
# Nah, probably a better idea to try to walk the tree and create a parallel one.
# Wonder if it would be quicker in this case to use some `exec` tomfoolery?
# Probably not. Should just walk the trees like a normal boy.
#
# Should draft out a min product of what that looks like.
#
#
# Thought more about this, think I actually can just "fold" around the
# placeholder skelly.
#
#> function fold {
#>    local -n src="$1"
#> 
#>    for key in "${src[@]}" ; do
#>       local skelly="${src[$key]}"
#> 
#>       if [[ "${SKELLY_TYPE[$key]}" == '-A' ]] ; then
#>          fold "$skelly"
#>       else
#>          local -n val="${skelly[$key]}"
#>          src[$key]="$val"
#>       fi
#>    done
#> }
