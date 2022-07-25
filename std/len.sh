#!/bin/bash

ARITY=1
RETURN='int'

function len {
   local -n arg1="$1"
   local -n v="${arg1[value]}"
   local -n t="${arg1[type]}" 

   local -i count=

   case "${t[kind]}" in
      'STRING')
            # `wc` always is 1 high. `echo '' | wc -m` returns 1 for some
            # reason. Gotta sub 1 to be accurate.
            count=$( wc -m <<< "${v}" )
            (( count-- ))
            ;;

      'ARRAY')
            count=${#v[@]}
            ;;

      *) echo "CAN'T LEN() a ${t[kind]}" 1>&2 ;;
      # How to throw exceptions? Again, need a good user-facing errors list or
      # some such. Make it easier for them to throw an exception.
   esac

   mk_type
   local -- tname=$TYPE
   local -n type=$TYPE
   type[kind]='INTEGER'

   mk_value
   local -- vname=$VALUE
   local -- value=$VALUE
   value[type]=$tname
   value[value]=$count
}


# What's annoying in the above?
#  1) All the annoying local name & nameref(s)
#     - Can likely be solved by creating more globals before calling any
#       functions.
#     - Create some globals that refer to:
#
#           ARG1_VALUE    (ARG1..N)
#           ARG1_TYPE
#           TYPE_NAME
#           TYPE
#           VALUE_NAME
#           VALUE
#
#       Re-written, that would look like:

function len {
   local -i count=

   case "${ARG1_TYPE[kind]}" in
      'STRING')
            # `wc` always is 1 high. `echo '' | wc -m` returns 1 for some
            # reason. Gotta sub 1 to be accurate.
            count=$( wc -m <<< "${ARG1_VALUE}" )
            (( count-- ))
            ;;

      'ARRAY')
            count=${#ARG1_VALUE[@]}
            ;;

      *) echo "CAN'T LEN() a ${ARG1_TYPE[kind]}" 1>&2 ;;
      # How to throw exceptions? Again, need a good user-facing errors list or
      # some such. Make it easier for them to throw an exception.
   esac

   mk_type
   TYPE[kind]='INTEGER'

   mk_value
   VALUE[type]=$TYPE_NAME
   VALUE[value]=$count
}

# Changes we'ld ahve to make for the above to happen:
#  - `mk_type` & `mk_value` need to create a `TYPE_NAME`, and global nameref as
#    the TYPE itself (and respectively VALUE for `mk_value`).
#  - Prior to any function call, we need to
#    - For each argument on the stack, make namerefs to their type and value.

# Unset any args/refs from the last function call.
[[ ${!ARG*} ]] && unset ${!ARG*}

(( last  = ${#STACK[@]} ))
(( start = last - arity ))

for (( idx = start; idx < last; idx++ )) ; do
   local -- arg_name="${STACK[idx]}"
   local -n arg="$arg_name"

   declare -gn "ARG${idx}_TYPE"="${arg[type]}"
   declare -gn "ARG${idx}_DATA"="${arg[data]}"
done


# 2022-07-17
# Need to rethink the above, now that I'm not doing an assert-y expression-
# based kinda validation. Given the new more accurate descriptor of `tests' and 
# `directives', it's a little easier to write these functions.
#  1. All statements must be constrained to a single function
#  2. The function may not call itself, or other functions aside from those
#     provided by the conflang API (TRUE, FALSE, FAILED)
#  3. Functions may take string arguments passed from the user, e.g.,
#     ```
#     homedir  path:file  {
#        has_attr('r')
#     }
#     ```
#  4. When a function is called, the top value is popped from the stack,
#     and made available as a nameref to its ARG_TYPE, and ARG_VALUE. Though
#     complex types the user may need to do some shenanigans to access
#     everything (e.g., array of arrays).

function exists_test {
   if [[ ${ARG_TYPE[kind]} != 'path' ]] ; then
      raise 'type_error' 'test(exists) expects a type(path).'
   fi

   if [[ -e "${ARG_VALUE[data]}" ]] ; then
      TRUE
   else
      FALSE
   fi
}


function exists_directive {
   if [[ ${ARG_TYPE[kind]} != 'path' ]] ; then
      raise 'type_error' 'test(exists) expects a type(path).'
   fi

   local cmd
   local path="${ARG_VALUE[data]}"

   if [[ ${ARG_TYPE[subtype]} ]] ; then
      local -n subtype=${ARG_TYPE[subtype]}
      if [[ ${subtype[kind]} == 'FILE' ]] ; then
         cmd='touch'
      else
         cmd='mkdir -p'
      fi
   else
      if [[ ${path##*/} == '' ]] ; then
         cmd='mkdir -p'
      else
         cmd='touch'
      fi
   fi

   $cmd "$path"
   [[ $? -ne 0 ]] && FAILED
}
