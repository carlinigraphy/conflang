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

declare -A EXPR_MAP=()
# ^-- maps the _NODE_$n name to its compiled _DATA_$n name. Used for resolving
# references (variables) to other expressions/sections. The first pass, we add
# an entry for any symbol node (sections, variable declarations). Picked up in
# the `compile_ref` phase. N-order references are resolved during pass-N.
#
# compile_expr:   ADD entries for sections, variable declarations
# compile_ref:    RESOLVE entries in order of level of indirection from the
#                 terminal expression.

declare -A REF_MAP=()
# ^-- accounts for open references that have NOT yet been resolved. Unset once
# resolved to their _DATA_$n value.


#───────────────────────────────( expressions )─────────────────────────────────
# TODO: documentation
declare -g  KEY=
declare -g  DATA=
declare -gi DATA_NUM=0

function mk_compile_dict {
   (( ++DATA_NUM ))
   local   --  dname="_DATA_${DATA_NUM}"
   declare -gA $dname
   declare -g  DATA=$dname
   local   -n  data=$dname
   data=()
}


function mk_compile_array {
   (( ++DATA_NUM ))
   local   --  dname="_DATA_${DATA_NUM}"
   declare -ga $dname
   declare -g  DATA=$dname
   local   -n  data=$dname
   data=()
}


function walk_exp_compiler {
   declare -g NODE="$1"
   compile_exp_"${TYPEOF[$NODE]}"
}


function compile_exp_decl_section {
   # Save reference to current NODE. Restored at the end.
   local -- save=$NODE
   local -n node=$save
   local -n name="${node[name]}"

   # Create data dictionary object.
   mk_compile_dict
   local -- dname=$DATA
   local -n data=$DATA

   walk_exp_compiler "${node[name]}"
   local -- key="$DATA"

   local -n items="${node[items]}" 
   for nname in "${items[@]}"; do
      walk_exp_compiler "$nname"
      data[$KEY]="$DATA"
   done

   # Add mapping from _NODE_$n -> _DATA_$n.
   EXPR_MAP["$save"]="$dname"

   declare -g KEY="$key"
   declare -g DATA="$dname"
   declare -g NODE="$save"
}


function compile_exp_decl_variable {
   local -- save_symtab=$SYMTAB
   local -- save_node=$NODE
   local -n node=$save

   walk_exp_compiler "${node[name]}"
   local -- key="$DATA"

   if [[ -n ${node[expr]} ]] ; then
      walk_exp_compiler "${node[expr]}"
   else
      declare -g DATA=''
   fi

   # Add mapping from _NODE_$n -> _DATA_$n.
   EXPR_MAP["$save_node"]="$DATA"

   declare -g KEY="$key"
   declare -g NODE="$save_node"
   declare -g SYMTAB="$save_symtab"
}


function compile_exp_typecast {
   local -n node="$NODE"
   walk_exp_compiler "${node[expr]}" 
}


function compile_exp_index {
   ## An 'index' is a combination of...
   ##    .left   subscriptable expression (section, array)
   ##    .right  index expression (identifier, integer)

   # TODO:THINKIES:
   # Need to re-think how this is done. Should be walking the left expression?
   # What if it's a reference which isn't resolved yet. Need to then delay
   # compiling the index until after resolving all the references.
   #
   # As I'm thinking about this more, I think we actually need to do this as a
   # pre-compilation pass. Create some sort of new REFERENCEE node that we can
   # store in a table. Lets us pull the values from the reference table to
   # resolve them earlier.
   #
   # Then when we get to an index expression, if the LHS is an identifier, it
   # will be looked up in the table, ... hmm. Feels like that falls into the
   # same problem as we have here. Either it would need to compile the
   # expression twice, or we'd need to have another pass after references are
   # resolved to finish the RHS of the index.
   #
   ## Given the following:
   #> one   : "one";
   #> two   : "two";
   #> array : [one, two];
   #> first : array> 0;
   #
   # Hmmmmmmmmmmmmmmmmmm.

   #local -n node="$NODE"

   #walk_exp_compiler "${node[left]}" 
   #local -n left="$DATA"

   #walk_exp_compiler "${node[right]}"
   #local -- right="$DATA"

   #DATA="${left[$right]}"
   #EXPR_MAP["$NODE"]="$DATA"
}


function compile_exp_unary {
   local -- save=$NODE
   local -n node=$save

   walk_exp_compiler "${node[right]}"
   local -i rhs=$DATA

   ## TODO: This should be moved to the semantic analysis section. Not here.
   #
   #case "${node[op]}" in
   #   'MINUS')
   #         (( DATA = -1 * rhs ))
   #         ;;
   #   *)    raise parse_error "${node[op],,} is not a unary operator."
   #         ;;
   #esac

   declare -g NODE=$save
   EXPR_MAP["$NODE"]="$DATA"
}


function compile_exp_array {
   local -- save=$NODE
   local -n node=$save

   mk_compile_array
   local -- dname=$DATA
   local -n data=$DATA

   for nname in "${node[@]}"; do
      walk_exp_compiler "$nname"
      data+=( "$DATA" )
   done

   declare -g DATA=$dname
   declare -g NODE=$save
   EXPR_MAP["$NODE"]="$DATA"
}


function compile_exp_boolean {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
   EXPR_MAP["$NODE"]="$DATA"
}


function compile_exp_integer {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
   EXPR_MAP["$NODE"]="$DATA"
}


function compile_exp_string {
   local -n node=$NODE
   local -- string="${node[value]}"

   while [[ "${node[concat]}" ]] ; do
      walk_exp_compiler "${node[concat]}"
      string+="$DATA"
      local -n node="${node[concat]}"
   done

   declare -g DATA="$string"
   EXPR_MAP["$NODE"]="$DATA"
}


function compile_exp_path {
   local -n node=$NODE
   local -- path="${node[value]}"

   while [[ "${node[concat]}" ]] ; do
      walk_exp_compiler "${node[concat]}"
      path+="$DATA"
      local -n node="${node[concat]}"
   done

   declare -g DATA="$path"
   EXPR_MAP["$NODE"]="$DATA"
}


function compile_exp_env_var {
   local -n node=$NODE
   local -- var_name="${node[value]}" 

   if [[ ! "${SNAPSHOT[$var_name]+_}" ]] ; then
      raise missing_env_var "$var_name"
   fi

   declare -g DATA="${SNAPSHOT[$var_name]}"
   EXPR_MAP["$NODE"]="$DATA"
}


function compile_exp_identifier {
   # Add this node to the reference map. Unset once resolved in the next stage
   # of the compiler.
   REF_MAP[$NODE]=''

   # Also needed in the expression map, in case one reference points to another.
   EXPR_MAP[$NODE]=''
}

#────────────────────────────────( references )─────────────────────────────────

# THINKIES:
# I think in this section of the compiler we're going to have to walk the
# resulting data itself.
# For each name, pull the NODE from the symbol table, check if it's something to
# resolve. Skip if no.
# Upon hitting a section, set the symtab scope to the descended level to resolve
# variables. If hitting a variable declaration, save a pointer to the symtab,
# and reset it to the GLOBAL level. In index expressions, descend if an expr
# takes us into a new level?

# For determining if we have a circular reference. Each pass, any time a
# reference is resolved in the REF_MAP, switch $RESOLVED to true. If there are
# holes in the REF_MAP, but $RESOLVED is false at the end of a run, there's some
# circular shit going on.
RESOLVED=false

function walk_ref_compiler {
   declare -g NODE="$1"
   compile_exp_"${TYPEOF[$NODE]}"
}


function compile_ref_decl_section {
   # Save reference to current NODE. Restored at the end.
   local -- save=$NODE
   local -n node=$save

   local -n items="${node[items]}" 
   for nname in "${items[@]}"; do
      walk_ref_compiler "$nname"
   done

   declare -g NODE="$save"
}


function compile_ref_decl_variable {
   local -- save=$NODE
   local -n node=$save

   if [[ -n ${node[expr]} ]] ; then
      walk_ref_compiler "${node[expr]}"
   fi

   declare -g NODE="$node"
}


function compile_ref_typecast {
   #local -n node="$NODE"
   #walk_ref_compiler "${node[expr]}" 
}


function compile_ref_index {
   ## An 'index' is a combination of...
   ##    .left   subscriptable expression (section, array)
   ##    .right  index expression (identifier, integer)
   #local -n node="$NODE"

   #walk_ref_compiler "${node[left]}" 
   #local -n left="$DATA"

   #walk_ref_compiler "${node[right]}"
   #local -- right="$DATA"

   #DATA="${left[$right]}"
}


function compile_ref_unary {
   #local -- save=$NODE
   #local -n node=$save

   #local -i rhs=$DATA

   #declare -g NODE=$save

   walk_ref_compiler "${node[right]}"
}


function compile_ref_identifier {
   # This is only used when resolving references. This will be the name of a
   # reference to another variable in whatever the current SYMTAB happens to be.
   #
   # Example:
   # age: 30;           # `age` <- _NODE_1
   # var: age;          # `age` <- _NODE_2
   #      ^^^
   # This function is dealing with the referece `age` (_NODE_2), referring to
   # variable `age` (_NODE_1).
   local -n node=$NODE

   # Pull the _NODE_$n name of the identifier expr. E.g., we're looking to
   # resolve the name "age" to the node '_NODE_2'.
   local -n symtab="$SYMTAB"
   local -n name="${node[name]}"
   local -n symbol="${symtab[${name[value]}]}"
   local -- ref_name="${symbol[node]}"

   local expr="${EXPR_MAP[$ref_name]}"
   if [[ $expr ]] ; then
      RESOLVED=true 
      unset 'REF_MAP[$NODE]'

      # Add to the expression map in case other refs point to this one.
      EXPR_MAP="$expr"

      # To "return" the reference to its parent expression.
      DATA="$expr"
   fi
}


function compile_ref_array {
   local -- save=$NODE
   local -n node=$save

   for nname in "${node[@]}"; do
      walk_ref_compiler "$nname"
   done

   declare -g NODE="$save"
}

function compile_ref_boolean { :; }
function compile_ref_integer { :; }
function compile_ref_string  { :; }
function compile_ref_path    { :; }
function compile_ref_env_var { :; }
