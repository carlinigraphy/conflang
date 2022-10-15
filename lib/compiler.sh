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


function walk_compiler {
   declare -g NODE="$1"
   compile_"${TYPEOF[$NODE]}"
}


function compile_decl_section {
   # Save reference to current NODE. Restored at the end.
   local -- save=$NODE
   local -n node=$save
   local -n name="${node[name]}"

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
   local -- save_symtab=$SYMTAB
   local -- save_node=$NODE
   local -n node=$save

   walk_compiler "${node[name]}"
   local -- key="$DATA"

   if [[ -n ${node[expr]} ]] ; then
      walk_compiler "${node[expr]}"
   else
      declare -g DATA=''
   fi

   declare -g KEY="$key"
   declare -g NODE="$save_node"
   declare -g SYMTAB="$save_symtab"
}


function compile_typecast {
   local -n node="$NODE"
   walk_compiler "${node[expr]}" 
}


function compile_index {
   # An 'index' is a combination of...
   #    .left   subscriptable expression (section, array)
   #    .right  index expression (identifier, integer)
   #
   # THINKIES:
   # Importantly, we don't want to duplicate value of the node, rather point
   # to the compiled result. If it's a simple value, we can set it directly.
   # If it's a reference to a section or array, this should resolve to the name
   # of that _DATA_$n node. This is likely something we're going to need to get
   # from the symbol table...?
   #
   # CURRENT:
   # Added some test functionality to the identifier lookup. If we have
   # something like...
   #
   #> one: [ "one" ]> 0;
   #
   # ...we call walk(node.left) which creates the array, then subscripts on
   # node.right. But for something like...
   #
   #> things: [ "one", "two" ];
   #> one: things> 0;
   #
   # ...walking node.left (things) returns a reference to things's symbol. Hmm.
   # Though we probably need for it to have a prop pointing to the _DATA_$n.
   # Gotta attach that. Maybe there's a separate phase just to resolve the
   # indices?
   #
   # IDEAS:
   # Phase I)    Create _DATA_$n node for each section/array, add refs to this
   #             in the symbol table
   # Phase II)   Resolve refs from the symbol table
   #
   # What if it results in a raw value, rather than a sect/array. Hmm.
   #
   # Can also do something in N passes, in which...
   # The first pass does all "normal" expressions. Anything that resolves to a
   # _DATA_$n node, or the value within that node. A dict points from the NODE
   # to the result:
   #
   #> NODE_1 -> DATA_1
   #> NODE_2 -> "one"
   #> NODE_3 -> "two"
   #> NODE_4 -> DATA_2
   #
   # The next set of passes resolves references. If C=1 and A>B, B>C, it would
   # be resolved like...
   #
   # p1.    A ->
   #        B ->
   #        C -> 1
   #
   # p2.    A -> 
   #        B -> 1
   #        C -> 1
   #        
   # p3.    A -> 1
   #        B -> 1
   #        C -> 1
   #
   # All 1st tier references would be resolved to their values in pass1, all
   # 2nd tier in pass2, etc.
   #
   # This is only something that would matter with references to references.
   # Which I'm hoping is kinda an edge case. 

   local -n node="$NODE"

   walk_compiler "${node[left]}" 
   local -n left="$DATA"

   walk_compiler "${node[right]}"
   local -- right="$DATA"

   DATA="${left[$right]}"
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


function compile_env_var {
   local -n node=$NODE
   local -- var_name="${node[value]}" 

   if [[ ! "${SNAPSHOT[$var_name]+_}" ]] ; then
      raise missing_env_var "$var_name"
   fi

   declare -g DATA="${SNAPSHOT[$var_name]}"
}


function compile_identifier {
   local -n node=$NODE
   local -n symtab=$SYMTAB

   local key="${node[value]}"
   declare -g DATA="${symtab[$key]}"
}
