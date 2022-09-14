#!/bin/bash

# For now very much just slamming out something really rough.
function ffi {
   local package_location="$1"
   local exe="${package_location##*/}"

   if [[ ! -d "$package_location" ]] ; then
      echo "Package [$package_location] not found."
      exit 1
   fi

   test_file="${package_location}/${exe}"-test.sh
   directive_file="${package_location}/${exe}"-directive.sh

   source "$test_file" "$directive_file" 2>/dev/null

   if [[ -e "$test_file" ]] ; then
      hash_t=$( md5sum "$test_file" )
      hash_t="_${hash_t%% *}"
   fi

   if [[ -e "$directive_file" ]] ; then
      hash_d=$( md5sum "$directive_file" )
      hash_d="_${hash_t%% *}"
   fi

   fn=$( declare -f hello-test )
   eval "${fn/hello-test/$hash_t}"

   fn=$( declare -f hello-directive )
   eval "${fn/hello-directive/$hash_d}"
}


function mk_fn_symbol {
   local package_location="$1"
   local fn_t="$2" fn_d="$3"

   local -a symbol=(
      ['type']=TYPE_1         #= Type('FUNCTION')
      ['takes']=SIGNATURE_1   #= [ Type(t) for t in $conf.signature ]
      ['test']="$fn_t"
      ['directive']="$fn_d"
   )
}


ffi "$@"



# TODO:
# Running list of things that will be necessary for this to work:
#  - [ ]. Types as a valid expression
#           - Requires changing how subscription works, everything will need to
#             shift to bracket syntax
#           - Honestly this is a better approach that we should've shifted to
#             some time ago
#           - Allows the user to supply a .conf file with their module that
#             states permissible types
#  - [ ]. Compiling a type expression returns the name of the compiled TYPE_$n
#         node.
#           - May be useful in situations such as this one in which using a
#             type as value should return the TYPE to the programmer
#           - There may also be situations useful for end users for this
#             behavior
#           - Takes us one step closer to being able to call functions from the
#             global scope. Maybe internal references don't need to use '%'
#             afterall, save it for parser statements

# SIDEBAR: but as I'm thinking about it, the diff_env function is going to
# be missing some stuff. Any nodes created in the compiler. TYPE_'s,
# DATA_'s, SYMTAB_'s and whatnot. It won't be perfect, but it should
# hopefully catch a good amount of tomfoolery.
#
# Hmm. Still don't love how we're doing the env diff. Really just need to
# make sure that if a user calls an environment variable, we reference its
# initial declaration as defined by the first dump. Wonder if we want to just
# copy the initial env into a var? I like this. Need to explore that later.
#> while FS= read -r -d '' line ; do echo "[${line}]" ; done < <(env --null)
