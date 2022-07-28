#!/bin/bash

declare -p FILES

(( FILE_IDX = ${#FILES[@]} - 1 ))

declare -a TOKENS=()
declare -i _TOKEN_NUM=0

# `Cursor' object to track our position when iterating through the input.
# `Freeze' saves the position at the start of each scanner loop, recording the
# start position of each Token.
declare -A FREEZE CURSOR=(
   [offset]=-1    # Starts at -1, as the first call to advance increments to 0.
   [lineno]=1
   [colno]=0
)


declare -A KEYWORD=(
   [true]=true
   [false]=true
   [and]=true
   [or]=true
   [not]=true
   [include]=true
   [constrain]=true
)


function Token {
   local type=$1  value=$2
   
   # Realistically we can just do "TOKEN_$(( ${#_TOKEN_NUM[@]} + 1 ))". Feel like
   # that add visual complexity here, despite removing slight complexity of yet
   # another global variable.
   local tname="TOKEN_${_TOKEN_NUM}"
   declare -gA "${tname}"

   # Nameref to newly created global token.
   declare -n t="$tname"

   # Token data.
   t[type]="$type"
   t[value]="$value"

   # Cursor information (position in file & line).
   t[offset]=${FREEZE[offset]}
   t[lineno]=${FREEZE[lineno]}
   t[colno]=${FREEZE[colno]}
   t[file]="${FILE_IDX}"

   TOKENS+=( "$tname" ) ; (( _TOKEN_NUM++ ))
   #echo "[${t[lineno]}:${t[colno]}] ${type} [${value}]"
}

                                     
#══════════════════════════════════╡ SCANNER ╞══════════════════════════════════
declare -- CURRENT PEEK
declare -a CHARRAY=()      # Array of each character in the file.
declare -a FILE_LINES=()   # The input file lines, for better error reporting.

function advance {
   # Advance cursor position, pointing to each sequential character. Also incr.
   # the column number indicator. If we go to a new line, it's reset to 0.
   #
   # NOTE: So this has some of the silliest garbage of all time. In bash, using
   # ((...)) for arithmetic has a non-0 return status if the result is 0. E.g.,
   #> (( 1 )) ; echo $?    #  0
   #> (( 2 )) ; echo $?    #  0
   #> (( 0 )) ; echo $?    #  1
   # So the stupid way around this... add an `or true`. This is the short form:
   (( ++CURSOR[offset] )) ||:
   (( ++CURSOR[colno]  ))

   # This is a real dumb use of bash's confusing array indexing.
   CURRENT=${CHARRAY[CURSOR[offset]]}
   PEEK=${CHARRAY[CURSOR[offset]+1]}

   if [[ $CURRENT == $'\n' ]] ; then
      ((CURSOR[lineno]++))
      CURSOR[colno]=0
   fi
}


function scan {
   # Creating secondary line buffer to do better debug output printing. It would
   # be more efficient to *only* hold a buffer of lines up until each newline.
   # Unpon an error, we'd only need to save the singular line, then can resume
   mapfile -td $'\n' FILE_LINES < "${FILES[-1]}"

   # For easier lookahead, read all characters first into an array. Allows us
   # to seek/index very easily.
   while read -rN1 character ; do
      CHARRAY+=( "$character" )
   done < "${FILES[-1]}"

   while [[ ${CURSOR[offset]} -lt ${#CHARRAY[@]} ]] ; do
      advance ; [[ -z "$CURRENT" ]] && break

      # Save current cursor information.
      FREEZE[offset]=${CURSOR[offset]}
      FREEZE[lineno]=${CURSOR[lineno]}
      FREEZE[colno]=${CURSOR[colno]}

      # Skip comments.
      if [[ $CURRENT == '#' ]] ; then
         comment ; continue
      fi

      # Skip whitespace.
      if [[ $CURRENT =~ [[:space:]] ]] ; then
         continue
      fi

      # Symbols.
      case $CURRENT in
         ';')  Token       'SEMI' "$CURRENT"  ; continue ;;
         ':')  Token      'COLON' "$CURRENT"  ; continue ;;
         ',')  Token      'COMMA' "$CURRENT"  ; continue ;;
         '-')  Token      'MINUS' "$CURRENT"  ; continue ;;
         '%')  Token    'PERCENT' "$CURRENT"  ; continue ;;
         '?')  Token   'QUESTION' "$CURRENT"  ; continue ;;

         '(')  Token    'L_PAREN' "$CURRENT"  ; continue ;;
         ')')  Token    'R_PAREN' "$CURRENT"  ; continue ;;

         '{')  Token    'L_BRACE' "$CURRENT"  ; continue ;;
         '}')  Token    'R_BRACE' "$CURRENT"  ; continue ;;

         '[')  Token  'L_BRACKET' "$CURRENT"  ; continue ;;
         ']')  Token  'R_BRACKET' "$CURRENT"  ; continue ;;
      esac

      if [[ $CURRENT == '<' ]] ; then
         if [[ $PEEK == '=' ]] ; then
            advance ; Token 'LE_EQ' '<='
            continue
         else
            Token 'LT' '<'
            continue
         fi
      fi

      if [[ $CURRENT == '>' ]] ; then
         if [[ $PEEK == '=' ]] ; then
            advance ; Token 'GT_EQ' '>='
            continue
         else
            Token 'GT' '>'
            continue
         fi
      fi

      # Identifiers.
      if [[ $CURRENT =~ [[:alpha:]_] ]] ; then
         identifier ; continue
      fi

      # Strings. Surrounded by `"`.
      if [[ $CURRENT == '"' ]] ; then
         string ; continue
      fi

      # Paths. Surrounded by `'`.
      if [[ $CURRENT == "'" ]] ; then
         path ; continue
      fi

      # Numbers.
      if [[ $CURRENT =~ [[:digit:]] ]] ; then
         # Bash only natively handles integers. It's not able to do floats
         # without bringing `bc` or something. For now, that's all we'll also
         # support. Maybe later I'll add a float type, just so I can write some
         # external functions that support float comparisons.
         number ; continue
      fi

      # Can do a dedicated error pass, scanning for error tokens, and assembling
      # the context to print useful debug messages.
      Token 'ERROR' "$CURRENT"
   done

   Token 'EOF'
}


function comment {
   # There are no multiline comments. Seeks from '#' to the end of the line.
   while [[ -n $CURRENT ]] ; do
      [[ "$PEEK" =~ $'\n' ]] && break
      advance
   done
}


function identifier {
   local buffer="$CURRENT"

   while [[ -n $CURRENT ]] ; do
      [[ $PEEK =~ [^[:alnum:]_] ]] && break
      advance ; buffer+="$CURRENT"
   done

   if [[ -n ${KEYWORD[$buffer]} ]] ; then
      Token "${buffer^^}" "$buffer"
   else
      Token 'IDENTIFIER' "$buffer"
   fi
}


function string {
   declare -a buffer=()

   while [[ -n $CURRENT ]] ; do
      if [[ $PEEK == '"' ]] ; then
         if [[ $CURRENT == '\' ]] ; then
            unset buffer[-1]
         else
            break
         fi
      fi
      advance ; buffer+=( "$CURRENT" )
   done

   local join=''
   for c in "${buffer[@]}" ; do
      join+="$c"
   done

   # Create token.
   Token 'STRING' "$join"

   # Skip final closing `'`.
   advance
}


function path {
   declare -a buffer=()

   while [[ -n $CURRENT ]] ; do
      if [[ $PEEK == "'" ]] ; then
         if [[ $CURRENT == '\' ]] ; then
            unset buffer[-1]
         else
            break
         fi
      fi
      advance ; buffer+=( "$CURRENT" )
   done

   local join=''
   for c in "${buffer[@]}" ; do
      join+="$c"
   done

   # Create token.
   Token 'PATH' "$join"

   # Skip final closing `'`.
   advance
}


function number {
   local number=''

   while [[ $PEEK =~ [[:digit:]] ]] ; do
      advance ; number+="$CURRENT"
   done

   Token 'INTEGER'
}


scan

# If we haven't thrown an exception, I've either catastrophically missed an
# error, or we've completed the run successfully.
LEX_SUCCESS='yes'

# Dumps the tokens generated by the scanner, such that they can be used by the
# parser. This helps not polute too much the global namespace. Able to just
# import that which we need.
(
   declare -p LEX_SUCCESS
   declare -p FILE_LINES  FILES
   declare -p TOKENS  ${!TOKEN_*}
) | sort -V -k3
