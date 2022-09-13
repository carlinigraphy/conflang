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

function exist-test {
   #params:  <data:str> <type:indexed array>
   # `data`
   #     * the input upon which a test is performed
   #     * always supplied as a string, while the actual type is declared in the
   #       second parameter
   # `type`
   #     * passed in as the name of an indexed array containing the type (and
   #       potentially subtype(s)).
   #     * must declare a nameref to the 2nd paramater to access these values:
   #       > local -n type="$2"
   
   local -- data="$1"
   local -n type="$2"
   
   if [[ "${type[0]}" != 'path' ]] ; then
      raise invalid_type "exist() expects a (path), received (${type[0]})."
   fi

   [[ -e "${data}" ]]
}


function exist-directive {
   local -- data="$1" ; shift
   local -n type="$1" ; shift
   local -a params=( "$@" )
   
   if [[ "${type[0]}" != 'path' ]] ; then
      raise invalid_type "exist() expects a (path), received (${type[0]})."
   fi

   case "${type[1]}" in
      'dir')   mkdir -p "$data" ;;
      *)       touch "$data"    ;;
      # In this case, if the subtype is a file (or unspecified), we're assuming
      # the user wants to create a file. Maybe this could be modified based upon
      # a config flag/variable. `--strict-mode` or something.
   esac
}


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

mod="exist"

hash=$( md5sum "${mod}"-test.sh )
hash="_${hash%% *}"

source <(
   source "${mod}"-test.sh

   declare -f "${mod}"-test.sh | awk "
      sub(/^${mod}-test \(\)/, \"$hash ()\");
      print;
   "
)

# Some pseudocode here, I don't feel like drafting out all the namerefs for the
# Type nodes.
SYMTAB["$mod"]=#Symbol(Type: 'FUNCTION', node: "$hash")

# Here we re-use the .node property to instead refer to the function's name.
# Would then invoke via:
declare -n fn="${symbol[node]}"
$fn  "$data"  "$type"  "${params[@]}"

# ^-- To reduce confusion, we may instead want to not re-use .node. Instead
# make a .code or .func property.


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
#> name  (str): "exist";
#> takes (array:type): [
#>    path,
#> ];
#> params {
#>    strict (bool): false;
#> }


# I'm still not 100% on how these should be imported. Definitely as some sort
# of parser directive. We've already established those. Good to build off the
# existing framework.
#
# (Sidebar: as I think more on it, maybe it does not make
# the most sense that internal variables and parser directives are both
# prefixed with `%'. Hmm.)
#
#> %use 'path/to/module' as mod;
#
# Relative paths are checked in order of
#  1. Script's directory
#  2. System directory
#
# Example, if the user has a directory called ./std/exist/, and the 'system'
# does as well, the user's would take precedence if they called:
#> %use 'std/exist';
#
# All module names are loaded as the "full path" to their executable. In the
# example above, it would enter the symbol table as 'std.exist'. The `as`
# keyword would put it in as something else.
#
# There shall be only one `use` keyword, despite both tests & directives. It
# will load both (if found). If neither is found, throw a File Error. If the
# user attempts to call the test form, but there is only a directive present,
# throw a Name Error.
