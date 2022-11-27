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
function walk:compiler {
   walk:skelly "$1"

   for ast_node in "${ORDERED_DEPS[@]}" ; do
      local -n dst="${EXPR_MAP[$ast_node]}"
      walk:evaluate "$ast_node"
      dst="$DATA"
   done

   # Fold around all the temporary SKELLY nodes. Leaves only data.
   declare -g _SKELLY_ROOT="$_SKELLY_1"
   undead_yoga "$_SKELLY_ROOT"

   # Clean up the generated output. The nodes _SKELLY_{1,2} are uselessly
   # referring to the '%container' implicit section. Can't unset during
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

function mk_compile_dict {
   (( ++SKELLY_NUM ))
   local skelly="_SKELLY_${SKELLY_NUM}"
   declare -gA "$skelly"
   declare -g  SKELLY="$skelly"

   # Without a value, this isn't glob matched by ${!_SKELLY_*} expansion. Can't
   # assign in the initial `declare -g` as you can with strings values.
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


function walk:skelly {
   declare -g NODE="$1"
   skelly_"${TYPEOF[$NODE]}"
}


function skelly_decl_section {
   local node="$NODE"
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
   local middle_skelly="$SKELLY"
   local -n middle_skelly_r="$middle_skelly"

   mk_compile_dict                           #< _SKELLY_2
   local dict_skelly="$SKELLY"
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
      local name="${name_r[value]}"

      walk:skelly "$var_decl"
      dict_skelly_r[$name]="$SKELLY"
   done

   declare -g SKELLY="$middle_skelly"
}


function skelly_decl_variable {
   # Create skeleton node to be inserted into the parent section, and add
   # mapping from the AST node to the output skeleton node.
   mk_skelly
   EXPR_MAP["$NODE"]="$SKELLY"
}


#───────────────────────────( evaluate expressions )────────────────────────────
declare -g  DATA=
declare -gi DATA_NUM=0


function mk_compile_array {
   (( ++DATA_NUM ))
   local data="_DATA_${DATA_NUM}"

   declare -ga "$data"
   declare -g  DATA="$data"

   # Without a value, this isn't glob matched by ${!_DATA_*} expansion.
   # Necessary for dumping to $OUTPUT.
   local -n d="$data" ; d=()
}


function walk:evaluate {
   declare -g NODE="$1"
   evaluate_"${TYPEOF[$NODE]}"
}


function evaluate_decl_section {
   local -n node_r="$NODE"
   local -n items_r="${node_r[items]}"
   for ast_node in "${items_r[@]}"; do
      walk:evaluate "$ast_node"
   done
}


function evaluate_decl_variable {
   local -n node_r="$NODE"
   if [[ -n ${node_r[expr]} ]] ; then
      walk:evaluate "${node_r[expr]}"
   fi
}


function evaluate_typecast {
   local -n node_r="$NODE"
   walk:evaluate "${node_r[expr]}"
}


function evaluate_member {
   # A 'member' is a combination of...
   #    .left   section
   #    .right  identifier
   local -n node_r="$NODE"

   walk:evaluate "${node_r[left]}"
   local -n left_r="$DATA"

   local -n right_r="${node_r[right]}"
   local name="${right_r[value]}"

   # left[name] points to the intermediate skelly node. Need to go one
   # additional level of indirection past that.
   local -n rv="${left_r[$name]}"
   declare -g DATA="$rv"
}


function evaluate_index {
   # An 'index' is a combination of...
   #    .left   array
   #    .right  integer
   local -n node_r="$NODE"

   walk:evaluate "${node_r[left]}"
   local -n left_r="$DATA"

   local -n right_r="${node_r[right]}"
   local integer="${right_r[value]}"

   declare -g DATA="${left_r[$integer]}"
}


function evaluate_unary {
   local -n node_r="$NODE"
   walk:evaluate "${node_r[right]}"
   (( DATA = DATA * -1 ))
}


function evaluate_array {
   local -n node_r="$NODE"
   local -n items_r="${node_r[items]}"

   mk_compile_array
   local array="$DATA"
   local -n array_r="$DATA"

   for ast_node in "${items_r[@]}"; do
      walk:evaluate "$ast_node"
      array_r+=( "$DATA" )
   done

   declare -g DATA="$array"
}


function evaluate_boolean {
   local -n node_r="$NODE"
   declare -g DATA="${node_r[value]}"
}


function evaluate_integer {
   local -n node_r="$NODE"
   declare -g DATA="${node_r[value]}"
}


function evaluate_string {
   local -n node_r="$NODE"
   local string="${node_r[value]}"

   while [[ "${node_r[concat]}" ]] ; do
      walk:evaluate "${node_r[concat]}"
      string+="$DATA"
      local -n node_r="${node_r[concat]}"
   done

   declare -g DATA="$string"
}


function evaluate_path {
   local -n node_r=$NODE
   local path="${node_r[value]}"

   while [[ "${node_r[concat]}" ]] ; do
      walk:evaluate "${node_r[concat]}"
      path+="$DATA"
      local -n node_r="${node_r[concat]}"
   done

   declare -g DATA="$path"
}


function evaluate_env_var {
   local -n node_r="$NODE"
   local ident="${node_r[value]}"

   if [[ ! "${SNAPSHOT[$ident]+_}" ]] ; then
      raise missing_env_var "$ident"
   fi

   declare -g DATA="${SNAPSHOT[$ident]}"
}


function evaluate_identifier {
   # Pull identifier's name out of the AST node.
   local -n node_r="$NODE"
   local name="${node_r[value]}"

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
   local ast_node="${symbol_r[node]}"

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
#
# _SKELLY_1="_SKELLY_2" ; _SKELLY_2="value"
#             o< ---snip-snip--- >o                <-- these are scissors
# _SKELLY_1=                        "value"

function undead_yoga {
   local -n src_r="$1"

   local key
   for key in "${!src_r[@]}" ; do
      local skelly="${src_r[$key]}"
      local -n skelly_r="$skelly"

      # `$skelly` may be pointing to either to an explicitly declared empty
      # string, or an empty declaration:  `a: "";`  or  `a;`. Can't subscript
      # an array with an empty string, bash explodes.
      if [[ $skelly_r && ${IS_SECTION[$skelly_r]} ]] ; then
         undead_yoga "$skelly_r"
      fi

      src_r[$key]="$skelly_r"
   done
}
