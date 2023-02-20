#node!/bin/bash
#
#===============================================================================
# @section               Location operations & objects
#-------------------------------------------------------------------------------

# location:new()
# @set   LOCATION
# @noargs
function location:new {
   (( ++_LOC_NUM ))
   local loc="LOC_${_LOC_NUM}"
   declare -gA "$loc"
   declare -g  LOCATION="$loc"

   local -n loc_r="$loc"
   loc_r['start_ln']=
   loc_r['start_col']=
   loc_r['end_ln']=
   loc_r['end_col']=

   local -n file_r="$FILE"
   loc_r['file']="${file_r[path]}"
}


# location:copy()
# @description
#  Copies the properties from `$1`'s location node to `$2`'s. If no properties
#  are specified copy all of them. May only operate on `TOKEN`s and `NODE`s.
#
# @arg   $1    :NODE    Source location-containing node
# @arg   $2    :NODE    Destination location-containing node
function location:copy {
   local -n from_r="$1" ; shift
   local -n to_r="$1"   ; shift
   local -a props=( "$@" )

   local -n from_loc_r="${from_r[location]}"
   local -n to_loc_r="${to_r[location]}"

   if (( ! ${#props[@]} )) ; then
      props=( "${!from_loc_r[@]}" )
   fi

   local k v
   for k in "${props[@]}" ; do
      v="${from_loc_r[$k]}"
      to_loc_r["$k"]="$v"
   done
}


# location:cursor()
# @description
#  Convenience function to create a location at the current cursor's position.
#  Cleans up otherwise messy and repetitive code in the lexer.
#
# @set  LOCATION
# @env  CURSOR
#
# @noargs
function location:cursor {
   location:new
   local -n loc_r="$LOCATION"
   loc_r['start_ln']="${CURSOR[lineno]}"
   loc_r['start_col']="${CURSOR[colno]}"
   loc_r['end_ln']="${CURSOR[lineno]}"
   loc_r['end_col']="${CURSOR[colno]}"

   local -n file_r="$FILE"
   loc_r['file']="${file_r[path]}"
}
 
 
#===============================================================================
# @section                 File operations & objects
#-------------------------------------------------------------------------------

# file:new()
# @description
#  Creates new object representing a file.
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
   file_r['lines']="$lines"      #< pointer to array of file lines
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
      e=( --anchor "${location_r[location]}"
          --caught "${location_r[location]}"
          "$path"
      ); raise circular_import "${e[@]}"
   fi

   # throw:  missing_file
   if [[ ! -e "$fq_path" ]] ||
      [[ ! -r "$fq_path" ]] ||
      [[   -d "$fq_path" ]]
   then
      e=( --anchor "${location_r[location]}"
          --caught "${location_r[location]}"
          "$fq_path"
      ); raise missing_file "${e[@]}"
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
# @arg   $1    :FILE
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
