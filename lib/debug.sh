#!/bin/bash
#
# All the functions for debugging, or otherwise printing intermediate data as
# to check things aren't burninatored.

declare -gi INDENT_FACTOR=2
declare -gi INDENTATION=0

#───────────────────────────( pretty print symtab )─────────────────────────────
function pprint_symtab {
   local -n symtab="$1"

   (( INDENTATION++ ))

   for key in "${!symtab[@]}" ; do
      local -n symbol="${symtab[$key]}"
      local -n type="${symbol[type]}"

      if [[ "$key" == '%inline' ]] ; then
         local -n node="${symbol[node]}"
         local -n name="${node[name]}"
         printf '%s' "${FILES[${name[file]}]##*/}"
      else
         printf "%$(( INDENTATION * INDENT_FACTOR ))s%s" '' "$key"
      fi

      if [[ "${type[kind]}" == 'SECTION' ]] ; then
         printf '\n'
         pprint_symtab "${symbol[symtab]}"
      else
         echo 
      fi
   done

   (( INDENTATION-- ))
}

#───────────────────────────( pretty print NODE_* )─────────────────────────────
# For debugging, having a pretty printer is super useful. Also supes good down
# the line when we want to make a function for script-writers to dump a base
# skeleton config for users.

function walk_pprint {
   declare -g NODE="$1"
   pprint_"${TYPEOF[$NODE]}"
}


function pprint_use {
   local -n node="$NODE"
   local -n path="${node[path]}"

   printf "%$(( INDENTATION * INDENT_FACTOR ))s" ''
   printf '%%use '\''%s'\'' as %s;\n'  "${path[value]}"  "${node[name]}"
}


function pprint_decl_section {
   local -- symtab_name="$SYMTAB"
   local -n symtab="$symtab_name"

   # Save reference to current NODE. Restored at the end.
   local -- save=$NODE
   local -n node=$save
   local -n name="${node[name]}"

   # Set symtab to point to the newly descended scope.
   local   -n symbol="${symtab[${name[value]}]}"
   declare -g SYMTAB="${symbol[symtab]}"

   printf "%$(( INDENTATION * INDENT_FACTOR ))s" ''
   walk_pprint "${node[name]}"
   printf ' {\n'

   (( INDENTATION++ ))

   local -n items="${node[items]}" 
   for nname in "${items[@]}"; do
      walk_pprint "$nname"
   done

   (( INDENTATION-- ))
   printf "%$(( INDENTATION * INDENT_FACTOR ))s}\n" ''

   declare -g SYMTAB="$symtab_name"
   declare -g NODE="$save"
}


function pprint_decl_variable {
   local -- save=$NODE
   local -n node=$save

   printf "%$(( INDENTATION * INDENT_FACTOR ))s" ''
   walk_pprint "${node[name]}"

   if [[ ${node[type]} ]] ; then
      printf ' ('
      walk_pprint "${node[type]}"
      printf ')'
   fi

   if [[ ${node[expr]} ]] ; then
      printf ': '
      walk_pprint "${node[expr]}"
   fi

   printf ';\n'
   declare -g NODE=$save
}


function pprint_typedef {
   local -- save=$NODE
   local -n node=$save

   walk_pprint "${node[kind]}"

   if [[ "${node[subtype]}" ]] ; then
      printf ':'
      walk_pprint "${node[subtype]}"
   fi

   declare -g NODE=$save
}


function pprint_typecast {
   local -n node="$NODE"
   walk_pprint "${node[expr]}" 
   printf ' -> '
   walk_pprint "${node[typedef]}" 
}


function pprint_array {
   local -- save=$NODE
   local -n node=$save

   (( INDENTATION++ ))
   printf '['

   for nname in "${node[@]}"; do
      printf "\n%$(( INDENTATION * INDENT_FACTOR ))s" ''
      walk_pprint "$nname"
   done

   (( INDENTATION-- ))
   printf "\n%$(( INDENTATION * INDENT_FACTOR ))s]" ''

   declare -g NODE=$save
}


function pprint_unary {
   local -n node=$NODE
   local -- op

   case "${node[op]}" in
      'MINUS') op='-'
   esac

   printf '%s' "$op"
   walk_pprint "${node[right]}"
}


function pprint_boolean {
   local -n node=$NODE
   printf '%s' "${node[value]}"
}


function pprint_integer {
   local -n node=$NODE
   printf '%s' "${node[value]}"
}


function pprint_string {
   local -n node=$NODE
   local -- string="${node[value]}"

   while [[ "${node[concat]}" ]] ; do
      walk_compiler "${node[concat]}"
      string+="$DATA"
      local -n node="${node[concat]}"
   done

   printf '"%s"' "$string"
}


function pprint_path {
   : 'NOTE: This function must call the **walk_COMPILER** function, raerpb
      walk_pprint. Need to collate all the concat chunks, then print the
      totality as a string.'

   local -n node=$NODE
   local -- path="${node[value]}"

   while [[ "${node[concat]}" ]] ; do
      walk_compiler "${node[concat]}"
      path+="$DATA"
      local -n node="${node[concat]}"
   done

   printf "'%s'" "$path"
}


function pprint_identifier {
   local -n node=$NODE
   local -- value="${node[value]}"

   if [[ "$value" == '%inline' ]] ; then
      local index=${node['file']}
      local fname=${FILES[$index]}
      value="${fname##*/}"
   fi

   printf '%s' "$value"
}


function pprint_env_var {
   local -n node=$NODE
   local -- var_name="${node[value]}" 

   if [[ "${ENV_DIFF[$var_name]}" ]] ; then
      raise stomped_env_var "$var_name"
   fi

   if [[ ! "$var_name" ]] ; then
      raise missing_env_var "$var_name"
   fi

   local -n var="$var_name"
   printf '%s' "$var"
}


function pprint_int_var {
   local -n node=$NODE
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
   local -- nname="${symbol[node]}"
   local -n node="$nname"

   case "${TYPEOF[$nname]}" in
      'decl_variable')
            walk_pprint "${node[expr]}"
            ;;

      'decl_section')
            walk_pprint "$nname"
            ;;
   esac
}


function pprint_index {
   local -n node=$NODE

   walk_pprint "${node[left]}" 

   printf '.'
   walk_pprint "${node[right]}"
}


#───────────────────────────────( dump garbage )────────────────────────────────
# I certainly could've done this with fewer expressions, but at this point that's
# not really my main concern.

function dump_everything {
   sed_params=(
      -E
      -e 's,([[:alnum:]_])=\(,\1,'           # (strip opening paren)
      -e 's,\)$,,'                           # (strip closing paren)
      -e 's,\[,\n  [,g'                      # (puts keys on new line)
      -e 's,^declare\s-[-Aaig]+\s,\n,'       # declare -a NODE ->  NODE
      -e 's,\[([[:alpha:]%]+)\]=,\1: ,g'     # [file]="value"  ->  file: "value"
   )

   (
      # shellcheck disable=SC2086
      # ^-- thinks we don't want globbing here. We do.
      declare -p ${!NODE_*} ${!SYMTAB*} ${!SYMBOL_*} ${!TYPE_*} ${!_DATA*}
   ) | sort -V -k3 | sed "${sed_params[@]}"
}
