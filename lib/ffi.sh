#!/bin/bash
#
# Need to come up with a way in which we can dynamically name a sourced package.
# Considerations:
#  1. It must not significantly increase startup time
#     - Limit use of subshells, external commands
#     - Only load any lib on a `load` command or something, even the stdlib, so
#       we never unknowingly pay the additional cost. Programmer aware of
#       decisions they are making.
#  2. Must be easy on the programmer to write. No one is going to use the
#     validation if it's troublesome or annoying.
#  3. No side effects, tests & directives only return numeric exit status. It's
#     up to the library author to provide a reference of error codes.
#  4. No more than one function per test/directive. Functions are globally
#     unique. There is no good way to ensure two different programmers don't
#     stomp on each others functions. Only the primary function we're aware of
#     can be used.

# THINKIES:
# We can shift some of the burden of function name uniqueness onto the
# programmer, so long as we give them a trivial means of naming the function,
# and creating the requisite directory structure.
#
# I think symlinks here are a very good idea. It allows for multiple versions
# of the same library, as well as giving someone the ability to easily modify
# (but not in-place) other's code. Example:
#
# code/
#  +-- config.conf
#  `-- lib/
#       `-- len/
#            +-- len/ -> v2/
#            +-- v1/
#            +-- v2/
#            |    +-- README
#            |    +-- len-test.sh
#            |    +-- len-directive.sh
#            `-- v3/
#
# The above can feel a little silly if you only have a single version, would end
# up with two dirs of the same name under each other. However there's
# significantly greater ease when you want different versions.
#
# Hmm. Maybe we'd want the other versions paralell to each other, more like this:
#
# code/
#  +-- config.conf
#  `-- lib/
#       +-- len/ -> .len_v2/
#       +-- .len_v1/
#       +-- .len_v2/
#       |    +-- README
#       |    +-- len-test.sh
#       |    +-- len-directive.sh
#       `-- .len_v3/
#
# I think this is better. Then maybe can have a module containing functions as:
#
# code/
#  +-- config.conf
#  `-- lib/
#       `-- math/
#            +-- add/
#            `-- sub/
#
# How do we know if a directory counts as a module though? Probably need to put
# some sort of dotfile that marks it as a module containing function-dirs. Maybe
# need a .exports file that declares which sub-file is valid?

#--- Example @programmer file
# exist/
#  +-- exist-test.sh
#  `-- exist-directive.sh

# parent
#%use 'std.exist' as exist;
#
#
#FunctionSymbol(
#   fn_name:   $HASH
#   author:
#   version:
#
#   takes: [
#      Type('array', subtype: None),
#      Type('array', subtype: Type('file', subtype: None))
#      Type('array', subtype: Type('dir', subtype: None))
#   ]
#)
#
#
## exist.conf
#{
#   takes: [
#      'path',
#      'path:file',
#      'path:dir'
#   ]
#}
#
#function exist-test {
#   #params:  <data:str> <type:indexed array>
#   # `data`
#   #     * the input upon which a test is performed
#   #     * always supplied as a string, while the actual type is declared in the
#   #       second parameter
#   # `type`
#   #     * passed in as the name of an indexed array containing the type (and
#   #       potentially subtype(s)).
#   #     * must declare a nameref to the 2nd paramater to access these values:
#   #       > local -n type="$2"
#   
#   local -- data="$1"
#   local -n type="$2"
#   
#   if [[ "${type[0]}" != 'path' ]] ; then
#      raise invalid_type "exist() expects a (path), received (${type[0]})."
#   fi
#
#   [[ -e "${data}" ]]
#}
#
#
#function exist-directive {
#   local -- data="$1" ; shift
#   local -n type="$1" ; shift
#   local -a params=( "$@" )
#   
#   if [[ "${type[0]}" != 'path' ]] ; then
#      raise invalid_type "exist() expects a (path), received (${type[0]})."
#   fi
#
#   case "${type[1]}" in
#      'dir')   mkdir -p "$data" ;;
#      *)       touch "$data"    ;;
#      # In this case, if the subtype is a file (or unspecified), we're assuming
#      # the user wants to create a file. Maybe this could be modified based upon
#      # a config flag/variable. `--strict-mode` or something.
#   esac
#}
#
#
# Perhaps we'd want to allow passing in additional arguments (or more aptly
# flags) to tests/directives, to modify behavior. Example, `exist` can take a
# "strict" param, that requires exact type:subtype.
#
#> file (path:file): '/path/to/file' {
#>    exist("strict")
#> }
#
# Any params are passed as arguments $3->
#> [[ $type_str =~ ([[:alpha:]]+)(:[[:alpha:]]+)* ]]
#> declare -a _TYPE=( "${BASH_REMATCH[@]:1:${#BASH_REMATCH[@]}-1}" )
#> declare -a _TYPE=( "${_TYPE[@]/:/}" )
#> $fn "$data"  _TYPE  "${params[@]}"


#--- Example @compiler parse of file
#
#mod="exist"
#
#hash=$( md5sum "${mod}"-test.sh )
#hash="_${hash%% *}"
#
#source <(
#   source "${mod}"-test.sh
#
#   declare -f "${mod}"-test.sh | awk "
#      sub(/^${mod}-test \(\)/, \"$hash ()\");
#      print;
#   "
#)

# Some pseudocode here, I don't feel like drafting out all the namerefs for the
# Type nodes.
#SYMTAB["$mod"]=#Symbol(Type: 'FUNCTION', node: "$hash")

# Here we re-use the .node property to instead refer to the function's name.
# Would then invoke via:
#declare -n fn="${symbol[node]}"
#$fn  "$data"  "$type"  "${params[@]}"


#--- more THINKIES:
# I feel like the above would potentially incur a decent runtime cost. We want
# to catch as much as we can as early as we can. Maybe make people supply a
# function signature in order to import something?
#
#> %use {
#>    std.exist -> path;
#>    usr.module1.module2.util -> path:file  as util;
#> }


# OOOOOH
# What if we do a little bit of "self-hosting" as it were. Not really, though,
# but whatever.
#
# Each FFI file must contain a .conf spelling out its accepted parameters, and
# whatnot.
#
#> mod: "exist";
#> params {
#>    data (str);
#>    type (array:str);
#>
#>    # Flags:
#>    strict (bool);
#> }


#-------------------------------------------------------------------------------
# For now very much just slamming out something really rough. Fuck it, we'll do
# it live!

function ffi {
   local package_location="$1"
   local exe="${package_location##*/}"

   if [[ ! -d "$package_location" ]] ; then
      echo "Package [$package_location] not found."
      exit 1
   fi

   #local header="${package_location}/${exe}.conf"
   #if [[ ! -f "$header" ]] ; then
   #   echo "Package [$package_location] missing header file."
   #   exit 1
   #fi
   ## We need to compile the .conf "header" file containing package information,
   ## version, but most importantly, the function signature of the test/directive
   ## fn's.
   ## Need to make sure the user does not specify any parser directives in
   ## the header files. May only contain "base" features. Maybe this can be
   ## done instead with a global flag we pass to the parser? I dunno.
   #add_file "$header"
   #_parse
   #local root="$ROOT"
   #do_compile
   #conf author    ; local -- author="$RV"
   #conf version   ; local -n version="$RV"
   #conf signature ; local -n signature="$RV"

   # Unset successful package import flag. It is set at the end of the `source`
   # below, the only way to determine we haden't hit an error and returned
   # early.
   unset PACKAGE_IMPORT_SUCCESS
   unset FN_T FN_D

   source <(
      # It's not ideal, but anything in this block may have no unintended output
      # to stdout. Everything must be redirected to /dev/null or stderr if
      # necessary.
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

      # Surprisingly enough this is actually faster than using awk. I belive
      # because we still need the subshell, but it avoids a pipeline AND awk,
      # keeps more in native bash. Likewise `echo` profiles a little faster
      # than `printf` does.
      fn=$( declare -f hello-test )
      echo "${fn/hello-test/$hash_t}"

      fn=$( declare -f hello-directive )
      echo "${fn/hello-directive/$hash_d}"

      declare -g FN_T="$hash_t"  FN_D="$hash_d"
      declare -p FN_T            FN_D
   )

   $FN_T
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
