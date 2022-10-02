#!/bin/bash
#
# All of the utilities that tie together functionality from the lexer, parser,
# and compiler. Allows re-entering the parser for each included file, and
# concatenating (not literally, but in spirt) %include files.

function add_file {
   # Serves to both ensure we don't have circular imports, as well as resolving
   # relative paths to their fully qualified path.
   local -- file=$1

   # The full, absolute path to the file.
   local -- fq_path 
   local -- parent

   # The 1st call of `add_file()` will have an empty FILES[] array.
   if [[ "${#FILES[@]}" -gt 0 ]] ; then
      parent="${FILES[-1]%/*}"
   else
      # If there's nothing in FILES[], it's our first run. Any path that's
      # relative is inherently relative to our current working directory.
      parent='.'
   fi

   case "$file" in
      # Absolute paths.
      /*)   fq_path="${file}"           ;;
      ~*)   fq_path="${file/\~/$HOME}"  ;;

      # Paths relative to the calling file.
      *)    fq_path=$( realpath -m "${parent}/${file}" -q )
            ;;
   esac

   for f in "${FILES[@]}" ; do
      [[ "$f" == "$file" ]] && raise circular_import "$file"
   done

   # File must exist, must be readable.
   if [[ ! -r "$fq_path" ]] ; then
      raise missing_file "$fq_path"
   fi

   FILES+=( "$fq_path" )
}


function merge_includes {
   # Parse all `%include` files.
   for (( idx=0; idx<${#INCLUDES[@]}; ++idx )) ; do
      local -n node=${INCLUDES[idx]}
      insert_node_path="${node[path]}"

      add_file "$insert_node_path"
      _parse

      # Construct array (backwards) of the $ROOT nodes for each %include
      # statement.  Allows us to iter the INCLUDES backwards, and match $idx to
      # its corresponding root here.
      INCLUDE_ROOT=( "$ROOT" "${INCLUDE_ROOT[@]}" )
   done

   # Iterates bottom-to-top over the %include statements. Appends the items
   # from the included section into the target section.
   local -i len=${#INCLUDES[@]}
   for (( idx=(len - 1); idx >= 0; idx-- )) ; do
      local -- include_name=${INCLUDES[idx]}
      local -n include_node=${include_name}
      # e.g., INCLUDE_1(path: './colors.conf', target: NODE_2)

      local -n target_node=${include_node[target]}
      local -n target_items=${target_node[items]}
      # e.g., NODE_2(items: NODE_3, name: NODE_1)
      #       target_items = NODE_3[]

      local -- root_name=${INCLUDE_ROOT[idx]}
      local -n root_node=${root_name}
      local -n root_items=${root_node[items]}
      # e.g., INCLUDE_ROOT[idx] = NODE_16
      #       NODE_16(items: NODE_17, name: NODE_15)
      #       root_items = NODE_17[]

      # For each node in the sub-file, append it to the targetted node's
      # .items[].
      for n in "${root_items[@]}" ; do
         target_items+=( "$n" )
      done
   done
}


function identify_constraint_file {
   # Reset INCLUDE_ROOT[] and INCLUDES[] before parsing the constrain'd
   # file(s).
   declare -ga INCLUDE_ROOT=()  INCLUDES=()

   # Constraint files are sorted in order of precedence. The last found file
   # takes the highest precedence. If no file exists, throw an error.
   local last_found

   # Constrain statements are restricted to only occuring at the top-level
   # parent file. They may not be present in a sub-file, or in a sub-section.
   # We may always compare them relatively to the path of the initial $INPUT
   # file, AKA ${FILES[0]}.
   local fq_path
   for file in "${CONSTRAINTS[@]}" ; do
      case "$file" in
         /*)   fq_path="${file}"            ;;
         ~*)   fq_path="${file/\~/${HOME}}" ;;
         *)    fq_path=$( realpath -m "${FILES[0]%/*}/${file}" -q ) ;;
      esac

      if [[ -e "$fq_path" ]] ; then
         last_found="$fq_path"
      fi
   done

   for f in "${FILES[@]}" ; do
      if [[ "$f" == "$last_found" ]] ; then
         raise parse_error "\`$f' may not be both a %constrain and %include"  
      fi
   done

   if [[ ! $last_found ]] ; then
      raise missing_constraint
   else
      FILES+=( "$fq_path" )
   fi
}


function _parse {
   # Some elements of the scanner/parser need to be reset before every run.
   # Vars that hold file-specific information.

   init_scanner
   scan
   # Exports:
   #  list  TOKENS[]
   #  dict  TOKEN_*

   init_parser
   parse
   # Exports:
   #  str   ROOT
   #  dict  TYPEOF{}
   #  dict  NODE_*
}


function do_parse {
   # Parse the top-level `base' file.
   add_file "$INPUT"

   _parse
   declare -g PARENT_ROOT=$ROOT
   merge_includes
   # Merge all (potentially nested) `%include` statements from the parent file.

   if [[ $CONSTRAINTS ]] ; then
      identify_constraint_file 

      _parse
      declare -g CHILD_ROOT=$ROOT

      merge_includes
   fi

   # Restore top-level root node.
   declare -g ROOT=$PARENT_ROOT
}


function do_compile {
   # There may be both a parent and child ASTs, both of which have their own
   # symbol table. Until they're merged, we want a single point of reference
   # for any globally defined identifiers--currently typedefs. After the symbol
   # tables are merged we can copy the types to the root of the parent symtab.
   mk_symtab
   declare -gn GLOBALS="$SYMTAB"
   populate_globals

   # Each section assumes there's a symtab above it. There is a "hidden" top-
   # level section `%inline'. Need to create a parent symtab above to hold it.
   mk_symtab ; parent_symtab=$SYMTAB
   walk_symtab "$PARENT_ROOT"

   if [[ "$CHILD_ROOT" ]] ; then
      mk_symtab ; child_symtab=$SYMTAB
      walk_symtab "$CHILD_ROOT"

      # shellcheck disable=SC2128
      # It thinks the parent_symtab is an array itself, rather than the name of
      # an array.
      merge_symtab "$PARENT_ROOT"  "$parent_symtab"  "$child_symtab"
   fi

   # Reset pointer back to the parent symtab.
   declare -g SYMTAB="$parent_symtab"

   # Integrate globals at the root of the top-level symbol table.
   declare -n _symtab="$parent_symtab"
   for global in "${!GLOBALS[@]}" ; do
      _symtab[$global]="${GLOBALS[$global]}"
   done

   # Re-point $GLOBALS at the root of the symbol table.
   declare -gn GLOBALS="${parent_symtab}"

   walk_semantics "$PARENT_ROOT"
   walk_compiler  "$PARENT_ROOT"
}
