#!/bin/bash
#
# The programmer-facing part of the script. Allows accessing the nodes created
# by the config file.
#
# IMPORTS:
#  _SKELLY_$n
#  _DATA_$n

function conf {
   declare -g RV="$_SKELLY_ROOT"

   for arg in "$@" ; do
      local -n d=$RV

      if [[ ! "${d[$arg]+_}" ]] ; then
         printf 'Name Error: [%s] not found\n' "$arg"
         exit 23
      fi

      RV="${d[$arg]}"
   done
}
