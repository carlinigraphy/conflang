#!/bin/bash
#
# All the functions for debugging, or otherwise printing intermediate data as
# to check things aren't burninatored.


declare -i INDENT_FACTOR=2
declare -i INDENTATION=0

#───────────────────────────( pretty print symtab )─────────────────────────────
function pprint_symtab {
   local -n symtab="$1"

   (( INDENTATION++ ))

   for key in "${!symtab[@]}" ; do
      printf "%$(( INDENTATION * INDENT_FACTOR ))s%s" '' "$key"

      local -n symbol="${symtab[$key]}"
      local -n type="${symbol[type]}"

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
   pprint_${TYPEOF[$NODE]}
}


function pprint_decl_section {
   # Save reference to current NODE. Restored at the end.
   local -- save=$NODE
   local -n node=$save

   walk_pprint ${node[name]}
   printf ' {\n'

   (( INDENTATION++ ))

   local -n items="${node[items]}" 
   for nname in "${items[@]}"; do
      walk_pprint $nname
   done

   (( INDENTATION-- ))
   printf "%$(( INDENTATION * INDENT_FACTOR ))s}\n" ''

   declare -g NODE="$save"
}


function pprint_decl_variable {
   local -- save=$NODE
   local -n node=$save

   printf "%$(( INDENTATION * INDENT_FACTOR ))s" ''
   walk_pprint ${node[name]}

   if [[ ${node[type]} ]] ; then
      printf ' ('
      walk_pprint "${node[type]}"
      printf ')'
   fi

   if [[ ${node[expr]} ]] ; then
      printf ' '
      walk_pprint ${node[expr]}
      printf ';\n'
   fi

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


function pprint_array {
   local -- save=$NODE
   local -n node=$save

   (( INDENTATION++ ))
   printf '['

   for nname in "${node[@]}"; do
      printf "\n%$(( INDENTATION * INDENT_FACTOR ))s" ''
      walk_pprint $nname
   done

   (( INDENTATION-- ))
   printf "\n%$(( INDENTATION * INDENT_FACTOR ))s]" ''

   declare -g NODE=$save
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
   printf '"%s"' "${node[value]}"
}


function pprint_path {
   local -n node=$NODE
   printf "'%s'" "${node[value]}"
}


function pprint_identifier {
   local -n node=$NODE
   printf '%s' "${node[value]}"
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
      -e 's,^declare\s-[-Aaig]+\s,,'         # declare -a NODE    ->  NODE
      -e 's,\[([[:alpha:]%]+)\]=,\1: ,g'     # [file]="value"     ->  file: "value"
   )

   (
      declare -p parent_symtab child_symtab
      declare -p ${!NODE_*}
      declare -p ${!SYMTAB*}
      declare -p ${!SYMBOL_*}
      declare -p ${!TYPE_*}
   ) | sort -V -k3 | sed "${sed_params[@]}"
}
