#!/bin/bash

function each-test {
   local -- fn_name="$1" ; shift
   local -a args=( "$@" )

   local -n symbol="${SYMTAB[$fn_name]}"
   if [[ ! $symbol ]] ; then
      raise cannot_call "$fn_name"
   fi

   local -n fn="${symbol[test]}"
   $fn "${args[@]}"
}


function each-directive {
   local -- fn_name="$1" ; shift
   local -a args=( "$@" )

   local -n symbol="${SYMTAB[$fn_name]}"
   if [[ ! $symbol ]] ; then
      raise cannot_call "$fn_name"
   fi

   local -n fn="${symbol[directive]}"
   $fn "${args[@]}"

   (( $? )) || raise validation_error 'each'
}
