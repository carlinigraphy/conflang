#!/bin/bash

function hasattr-test {
   if [[ ! -e "$DATA" ]] ; then
      raise validation_error "hasattr() expecting existing file/directory"
   fi

   case "$1" in
      "read")     [[ -r $DATA ]] ;;
      "write")    [[ -w $DATA ]] ;;
      "execute")  [[ -x $DATA ]] ;;

      *) raise argument_error 'hasattr'  'expecting ["read", "write", "execute"]'
         ;;
   esac
}

function hasattr-directive {
   case "$1" in
      "read")     chmod +r ;;
      "write")    chmod +w ;;
      "execute")  chmod +x ;;

      *) raise argument_error 'hasattr'  'expecting ["read", "write", "execute"]'
         ;;
   esac

   (( $? )) || raise validation_error 'hasattr'
}
