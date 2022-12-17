#!/bin/bash
#===============================================================================
# @section                      File operations
#-------------------------------------------------------------------------------

# file:new()
# @description
#  Creates new object representing "files".
#
# @set   FILE
# @noargs
function file:new {
   (( ++_FILE_NUM ))
   local file="FILE_${_FILE_NUM}"
   declare -gA "$file"
   declare -g FILE="$file"

   (( ++_FILE_LINES_NUM ))
   local lines="FILE_LINES_${_FILE_LINES_NUM}"
   declare -ga "$lines"

   local -n file_r="$file"
   file_r['path']=''             #< absolute path to file
   file_r['symtab']=''           #< root symbol table for file
   file_r['container']=''        #< .container node of AST
   file_r['lines']="$lines"
}


# file:resolve()
# @description
#  Throws error on circular imports, resolves relative paths to fully qualified
#  path.
#
# @env   FILE
# @set   FILES{}
#
# @arg   $1    :str        Relative or absolute path to the file
# @arg   $2    :str        Parent to which this file is relative
# @arg   $3    :LOCATION   For error reporting invalid import statements
function file:resolve {
   local path="$1"
   local parent="$2"
   local location="$3"
   if [[ "$location" ]] ; then
      local -n location_r="$location"
   fi

   local fq_path
   case "$path" in
      # Absolute paths.
      /*) fq_path="${path}"           ;;
      ~*) fq_path="${path/\~/$HOME}"  ;;

      # Paths relative to the calling file.
      *)  fq_path=$( realpath -m "${parent}/${path}" -q )
          ;;
   esac

   # throw:  circular_import
   if [[ "${FILES[$fq_path]}" ]] ; then
      e=( circular_import
         --anchor "${location_r[location]}"
         --caught "${location_r[location]}"
         "$path"
      ); raise "${e[@]}"
   fi

   # throw:  missing_file
   if [[ ! -e "$fq_path" ]] ||
      [[ ! -r "$fq_path" ]] ||
      [[   -d "$fq_path" ]]
   then
      e=( missing_file
         --anchor "${location_r[location]}"
         --caught "${location_r[location]}"
         "$fq_path"
      ); raise "${e[@]}"
   fi

   local -n file_r="$FILE"
   file_r['path']="$fq_path"

   FILES["$fq_path"]="$FILE"
   IMPORTS+=( "$fq_path" )
}


# file:parse()
# @description
#  Generates the AST & symbol table for a single file.
#
# @set   NODE
# @set   SYMTAB
# @env   FILE
#
# @arg   $1    :FILE    Globally sets $FILE pointer for lexer & parser
function file:parse {
   local file="$1"
   local -n file_r="$file"
   declare -g FILE="$file"

   lexer:init
   lexer:scan

   parser:init
   parser:parse
   local -n node_r="$NODE"
   file_r['ast']="${node_r[container]}"

   walk:symtab "$NODE"
   file_r['symtab']="$SYMTAB"
}
