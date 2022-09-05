#!/bin/bash
#
# The programmer-facing part of the script. Allows accessing the nodes created
# by the config file.
#
# IMPORTS:
#  _DATA_ROOT
#  _DATA_$n

function conf {
   declare -g RV='_DATA_1'

   for arg in "$@" ; do
      local -n d=$RV

      # TODO: profiling
      # If you're suuuuper sure you're not going to have any invalid selectors,
      # taking this out shaves like 20% off the query time.
      #
      # Test if the selector exists. If it's trying to query an index that's
      # *UNSET*, rather than just declared as an empty string, it explodes.
      if [[ ! "${d[$arg]+_}" ]] ; then
         raise index_error "$arg"
      fi

      RV="${d[$arg]}"
   done
}
