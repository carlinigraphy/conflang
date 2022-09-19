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
#  ┌── thinks I'm trying to assign a var, rather than declare empty variables.
# shellcheck disable=SC1007
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


# Nothing to do with the %use statement itself here.
function compile_use { :; }


function compile_decl_section {
   local -- symtab_name="$SYMTAB"
   local -n symtab="$symtab_name"

   # Save reference to current NODE. Restored at the end.
   local -- save=$NODE
   local -n node=$save
   local -n name="${node[name]}"

   # Set symtab to point to the newly descended scope.
   local -n symbol="${symtab[${name[value]}]}"
   SYMTAB="${symbol[symtab]}"

   # Create data dictionary object.
   mk_compile_dict
   local -- dname=$DATA
   local -n data=$DATA

   walk_compiler "${node[name]}"
   local -- key="$DATA"

   local -n items="${node[items]}" 
   for nname in "${items[@]}"; do
      walk_compiler "$nname"

      # %use statements do not have a KEY, skip. I guess this would also be the
      # case for any future non-data statements.
      if [[ $KEY ]] ; then
         data[$KEY]="$DATA"
      fi
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

   local -- val="${SNAPSHOT[$var_name]}"
   if [[ ! "${val+_}" ]] ; then
      raise missing_env_var "$var_name"
   fi

   declare -g DATA="$val"
}


function compile_int_var {
   local -n node="$NODE"
   local -- var="${node[value]}"

   # Internal vars are absolute paths, always beginning at the root of the
   # symbol table.
   local -n inline="${GLOBALS[%inline]}"
   local -n symtab="${inline[symtab]}"

   local symbol_name="${symtab[$var]}"
   if [[ ! "$symbol_name" ]] ; then
      raise missing_int_var "$var"
   fi

   local -n symbol="$symbol_name"
   walk_compiler "${symbol[node]}"
}


function compile_index {
   # An 'index' is a combination of...
   #    .left   subscriptable expression (section, array)
   #    .right  index expression (identifier, integer)

   local -n node="$NODE"

   walk_compiler "${node[left]}" 
   local -n left="$DATA"

   walk_compiler "${node[right]}"
   local -- right="$DATA"

   DATA="${left[$right]}"
}
