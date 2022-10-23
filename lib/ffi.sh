function create_ffi_symbol {
   local -n path="$1"
   local -- fn_name="$2"

   local file_idx="${path[file]}"
   local dir="${FILES[$file_idx]%/*}"

   local loc="${dir}/${path[value]}"      # Full path to the .sh file itself
   local exe="${loc##*/}"                 # The `basename`, also the prefix of
                                          # the -test/directive function names
   if [[ ! -d "$loc" ]] ; then
      echo "Package [$loc] not found."
      exit 1
   fi

   test_file="${loc}/${exe}"-test.sh
   directive_file="${loc}/${exe}"-directive.sh

   if [[ -e "$test_file" ]] ; then
      #  ┌── ignore non-source file.
      # shellcheck disable=SC1090
      source "$test_file" || {
         raise source_failure  "$test_file"
      }
      hash_t=$( md5sum "$test_file" )
      hash_t="_${hash_t%% *}"
   fi

   if [[ -e "$directive_file" ]] ; then
      #  ┌── ignore non-source file.
      # shellcheck disable=SC1090
      source "$directive_file" || {
         raise source_failure  "$directive_file"
      }
      hash_d=$( md5sum "$directive_file" )
      hash_d="_${hash_t%% *}"
   fi

   fn=$( declare -f ${exe}-test )
   eval "${fn/${exe}_test/$hash_t}"

   fn=$( declare -f ${exe}-directive )
   eval "${fn/${exe}_directive/$hash_d}"

   mk_symbol
   local -- symbol_name="$SYMBOL"
   local -n symbol="$symbol_name"

   copy_type "$_FUNCTION"
   symbol['name']="$fn_name"
   symbol['type']="$TYPE"
   symbol['test']="$hash_t"
   symbol['directive']="$hash_d"
   symbol['signature']=
}
