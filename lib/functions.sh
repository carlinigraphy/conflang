#!/bin/bash
#
# Create dicts required to make functions, as well as the standard by which
# they should all adhere.
#
# Mostly at this point this is just thinkies and drafts.
#
# THINKIES:
# User must be able to create & import their own functions. Probably going to
# need to extend the syntax somewhat. Maybe some pre-determined "internal"
# sections, to control the behavior of `conflang` itself.
#
# User gets access to the standard library by default. Then have some __use__
# section to bring in new functions, or import other shit?
#> __meta__ {
#>    use  array:str  [
#>       "std.len"
#>       # Strings starting without a `path prefix' (./, /, ~/) are assumed to
#>       # be part of the conflang library, rather than including from a user-
#>       # created location. Like:
#>       "./extend/function"
#>    ]
#>
#>    # Import another config file.
#>    include  array:path  [
#>       ./config2.cfg
#>       ./config3.cfg
#>    ]
#> }

# Hmmm. Having trouble thinking through how a user would easily provide their
# created functions.
#
# Maybe if each file is structured like:
#> $ cat ./$FUNC_NAME
#>
#> function $FUNC_NAME {
#>    ...
#> }
#>
#> declare -A meta (
#>    [arity]= 
#>    [returns]= 
#> )

# Functions can be stored internally with literally any identifier. Likely going
# to use an `_' + md5sum of the contents to identify them. Then symtab maps name
# to the function definition. Do need a fast way of creating these though. Maybe
# just path, actually. I think the full path to the file as the key?
#
# Hmm.

# Really hitting a wall here thinking through how these should work. Kinda gonna
# just stream-of-consciousness some thinkies. There are no function declarations
# in the language. Functions are solely coming from external bash files. Source
# the file in a subshell, dump the function definition with a `declare -f`, and
# modify the name to be unique. Create the Symbol. E.g.,
#> Symbol(
#>    name: 'len'
#>    type: Type(
#>       kind: 'FUNCTION'
#>       subtype: Type(
#>          kind: $FUNCTION_RETURN_TYPE
#>          subtype: $SUBTYPE_IF_COMPLEX_TYPE
#>       )
#>    )
#>   definition: $FN_NODE_NUM
#> )
#
# Can import functions something like the below:
#> source <(
#>    source "/path/to/function_name"
#>    declare -f function_name | awk -v FN="FN_${FN_NUM}" 'NR==1 {sub(/^[[:alpha:]_][[:alnum:]_]*/, FN)} ; {print}'
#> )
#
# As this changes only the name of the function, it does make recursion not
# possible. We'd need to gsub() the function name everywhere, and that feels
# like it could be reliable. Particularly with a short, general function name.
#
# Running the source from a subshell also allows us to import the same named
# function without stomping on any previously defined functions with the same
# name. But how do we enter these into the symbol table, or make the idents
# not stomp on each other?

# Hmmmmmmmmmmmmmmm. I think the below approach is starting out pretty good, but
# ultimately is going to work. The user will need access to mk_value. I think
# we need to make much, much more user-friendly functions. May not hurt to start
# drafting out what the FFI actually looks like, rather than the internal
# nonsense for it.

#declare -- ARITY  RETURN         # Temporary pointers in loop.
#declare -- FN                    # Globally declared functions.
#declare -i FN_NUM
#
#declare -- SYMBOL
#declare -i SYMBOL_NUM
#
#function mk_symbol {
#   (( SYMBOL_NUM++ ))
#   local   --  sname="_SYMBOL_${SYMBOL_NUM}"
#   declare -gA $sname
#   declare -gn SYMBOL=$sname
#   local   --  symbol=$sname
#
#   symbol[type]=
#   symbol[arity]=
#   symbol[definition]=
#}
#
#
#function mk_function {
#   (( FN_NUM++ ))
#   declare -g FN="_FN_${FN_NUM}"
#}
#
#
#function import {
#   for path in "${imports[@]}" ; do
#      mk_function
#      local -- fname=$FN
#
#      fn_params=(
#         -v RE='[[:alpha:]_][[:alnum:]_]*'
#         -v SUB="$fname" 
#      )
#
#      ar_params=(
#         -v RE='-[g-]\sARITY'
#         -v SUB="-g ARITY" 
#      )
#
#      rv_params=(
#         -v RE='-[g-]\sRETURN'
#         -v SUB="-g RETURN" 
#      )
#
#      local -- f="${path##*/}"
#      source <(
#         source "$path"
#         declare -f "$f" | awk "${fn_params[@]}" 'NR==1 {sub(RE, SUB)} {print}'
#         declare -p ARITY | awk "${ar_params[@]}" 'sub(RE, SUB) {print}'
#         declare -p RETURN | awk "${rv_params[@]}" 'sub(RE, SUB) {print}'
#      )
#
#      # Save existing IFS. Temporarily set to ':'.
#      local -- ifs="$IFS" ; IFS=':'
#      local -a types=( $RETURN )
#
#      # Reset global type pointer. Working our way bottom-to-top, so at the
#      # START of each loop, the TYPE becomes the [subtype] for that node.
#      declare -g TYPE=
#
#      # Iterate backwards.
#      for (( idx = ${#types[@]} - 1; idx <= 0; idx-- )) ; do
#         local -- t="${types[idx]}"
#
#         mk_type
#         local -- tname=$TYPE
#         local -n type=$TYPE
#
#         type[subtype]=$TYPE
#         type[kind]="${BUILT_INS[t]}"
#      done
#
#      # Save subtype(s) generated from the loop above.
#      local -- subtype=$TYPE
#
#      # Create function type itself, assigning it's subtype (return type), to
#      # the above created node.
#      mk_type
#      local -- tname=$TYPE
#      local -n type=$TYPE
#      type[kind]='FUNCTION'
#      type[subtype]="$subtype"
#
#      # Restore IFS to standard value.
#      IFS="$ifs"
#
#      symbol[arity]=$ARITY
#      symbol[return]=$tname
#      symbol[function]=$fname
#   done
#}
