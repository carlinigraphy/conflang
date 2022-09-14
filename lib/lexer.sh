#!/bin/bash
# shellcheck disable=SC2184
#  "Quote arguments to `unset` so they're not glob expanded"
#     Only ever unsetting a single character in an array of single characters.
#     No ability to glob expand to anything else.
#
# Requires from ENV:
#  list:path   FILES[]

declare -gi TOKEN_NUM=0

declare -gA KEYWORD=(
   ['as']=true
   ['true']=true
   ['false']=true
   ['and']=true
   ['or']=true
   ['not']=true
   ['use']=true
   ['include']=true
   ['constrain']=true
)

function init_scanner {
   # Some variables need to be reset at the start of every run. They hold
   # information that should not be carried from file to file.

   # Reset global vars prior to each run.
   (( FILE_IDX = ${#FILES[@]} - 1 )) ||:

   # Fail if no file.
   if [[ "${#FILES[@]}" -eq 0 ]] ; then
      raise no_input
   fi

   declare -g   CURRENT=''  PEEK=''

   declare -ga  CHARRAY=()
   declare -ga  TOKENS=()

   declare -gA  FREEZE CURSOR=(
      [offset]=-1
      [lineno]=1
      [colno]=0
   )
}


function Token {
   # Effectively a Class. Creates instances of Token with information for
   # the position in the file, as well as the character type/value.

   local type=$1  value=$2

   # Realistically we can just do "TOKEN_$(( ${#TOKEN_NUM[@]} + 1 ))". Feel like
   # that add visual complexity here, despite removing slight complexity of yet
   # another global variable.
   local tname="TOKEN_${TOKEN_NUM}"
   declare -gA "${tname}"

   # Nameref to newly created global token.
   declare -n t="$tname"

   # Token data.
   t['type']="$type"
   t['value']="$value"

   # Cursor information (position in file & line).
   t['offset']=${FREEZE[offset]}
   t['lineno']=${FREEZE[lineno]}
   t['colno']=${FREEZE[colno]}

   # shellcheck disable=SC2034
   # ^-- doesn't know this is used later.
   t['file']="${FILE_IDX}"

   TOKENS+=( "$tname" )
   (( TOKEN_NUM++ )) ||:
}

                                     
function l_advance {
   # Advance cursor position, pointing to each sequential character. Also incr.
   # the column number indicator. If we go to a new line, it's reset to 0.
   #
   # NOTE: So this has some of the silliest garbage of all time. In bash, using
   # ((...)) for arithmetic has a non-0 return status if the result is 0. E.g.,
   #> (( 1 )) ; echo $?    #  0
   #> (( 2 )) ; echo $?    #  0
   #> (( 0 )) ; echo $?    #  1
   # So the stupid way around this... add an `or true`. This is the short form:
   (( ++CURSOR['offset'] )) ||:
   (( ++CURSOR['colno']  ))

   # This is a real dumb use of bash's confusing array indexing.
   CURRENT=${CHARRAY[CURSOR['offset']]}
   PEEK=${CHARRAY[CURSOR['offset']+1]}

   if [[ $CURRENT == $'\n' ]] ; then
      ((CURSOR['lineno']++))
      CURSOR['colno']=0
   fi
}


function scan {
   # For easier lookahead, read all characters first into an array. Allows us
   # to seek/index very easily.
   while read -rN1 character ; do
      CHARRAY+=( "$character" )
   done < "${FILES[-1]}"

   while [[ ${CURSOR[offset]} -lt ${#CHARRAY[@]} ]] ; do
      l_advance ; [[ -z "$CURRENT" ]] && break

      # Save current cursor information.
      FREEZE['offset']=${CURSOR['offset']}
      FREEZE['lineno']=${CURSOR['lineno']}
      FREEZE['colno']=${CURSOR['colno']}

      # Skip comments.
      if [[ $CURRENT == '#' ]] ; then
         l_comment ; continue
      fi

      # Skip whitespace.
      if [[ $CURRENT =~ [[:space:]] ]] ; then
         continue
      fi

      # Symbols.
      case $CURRENT in
         '.')  Token        'DOT' "$CURRENT"  ; continue ;;
         ',')  Token      'COMMA' "$CURRENT"  ; continue ;;
         ';')  Token       'SEMI' "$CURRENT"  ; continue ;;
         ':')  Token      'COLON' "$CURRENT"  ; continue ;;
         '$')  Token     'DOLLAR' "$CURRENT"  ; continue ;;
         '%')  Token    'PERCENT' "$CURRENT"  ; continue ;;
         '?')  Token   'QUESTION' "$CURRENT"  ; continue ;;

         '(')  Token    'L_PAREN' "$CURRENT"  ; continue ;;
         ')')  Token    'R_PAREN' "$CURRENT"  ; continue ;;

         '[')  Token  'L_BRACKET' "$CURRENT"  ; continue ;;
         ']')  Token  'R_BRACKET' "$CURRENT"  ; continue ;;

         '{')  Token    'L_BRACE' "$CURRENT"  ; continue ;;
         '}')  Token    'R_BRACE' "$CURRENT"  ; continue ;;
      esac

      # Typecast, or minus.
      if [[ $CURRENT == '-' ]] ; then
         # If subsequent `>', is an arrow for typecast.
         if [[ $PEEK == '>' ]] ; then
            l_advance
            Token 'ARROW' '->'
         else
            Token 'MINUS' '-'
         fi

         continue
      fi

      # f-{strings,paths}
      if [[ $CURRENT == 'f' ]] ; then
         if   [[ $PEEK == '"' ]] ; then
            l_advance ; l_fstring
            continue
         elif [[ $PEEK == "'" ]] ; then
            l_advance ; l_fpath
            continue
         fi
      fi

      # Identifiers.
      if [[ $CURRENT =~ [[:alpha:]_] ]] ; then
         l_identifier ; continue
      fi

      # Strings. Surrounded by `"`.
      if [[ $CURRENT == '"' ]] ; then
         l_string ; continue
      fi

      # Paths. Surrounded by `'`.
      if [[ $CURRENT == "'" ]] ; then
         l_path ; continue
      fi

      # Numbers.
      if [[ $CURRENT =~ [[:digit:]] ]] ; then
         # Bash only natively handles integers. It's not able to do floats
         # without bringing `bc` or something. For now, that's all we'll also
         # support. Maybe later I'll add a float type, just so I can write some
         # external functions that support float comparisons. Or maybe you just
         # accept that you're taking a performance hit by using floats. More
         # subshells and whatnot.
         l_number ; continue
      fi

      # Can do a dedicated error pass, scanning for error tokens, and assembling
      # the context to print useful debug messages.
      Token 'ERROR' "$CURRENT"
   done

   Token 'EOF'
}


function l_comment {
   # There are no multiline comments. Seeks from '#' to the end of the line.
   while [[ -n $CURRENT ]] ; do
      [[ "$PEEK" =~ $'\n' ]] && break
      l_advance
   done
}


function l_identifier {
   local buffer="$CURRENT"

   while [[ -n $CURRENT ]] ; do
      [[ $PEEK =~ [^[:alnum:]_] ]] && break
      l_advance ; buffer+="$CURRENT"
   done

   if [[ ${KEYWORD[$buffer]} ]] ; then
      Token "${buffer^^}" "$buffer"
   else
      Token 'IDENTIFIER' "$buffer"
   fi
}


function l_string {
   local -a buffer=()

   while [[ $PEEK ]] ; do
      l_advance

      if [[ $CURRENT == '"' ]] ; then
         # shellcheck disable=SC1003
         # Misidentified error.
         if [[ $buffer && ${buffer[-1]} == '\' ]] ; then
            # shellcheck disable=SC2184
            unset buffer[-1]
         else
            break
         fi
      fi

      buffer+=( "$CURRENT" )
   done

   local join=''
   for c in "${buffer[@]}" ; do
      join+="$c"
   done

   # Create token.
   Token 'STRING' "$join"
}


function l_path {
   local -a buffer=()

   while [[ $PEEK ]] ; do
      l_advance

      if [[ $CURRENT == "'" ]] ; then
         # shellcheck disable=SC1003
         # Misidentified error.
         if [[ $buffer && ${buffer[-1]} == '\' ]] ; then
            # shellcheck disable=SC2184
            unset buffer[-1]
         else
            break
         fi
      fi

      buffer+=( "$CURRENT" )
   done

   local join=''
   for c in "${buffer[@]}" ; do
      join+="$c"
   done

   # Create token.
   Token 'PATH' "$join"
}


function l_number {
   local number="${CURRENT}"

   while [[ $PEEK =~ [[:digit:]] ]] ; do
      l_advance ; number+="$CURRENT"
   done

   Token 'INTEGER' "$number"
}


function l_interpolation {
   while [[ ${CURSOR[offset]} -lt ${#CHARRAY[@]} ]] ; do
      # String interpolation ends upon a closing R_BRACE token, or if there's
      # no current character.
      if [[ ! $CURRENT ]] || [[ $PEEK == '}' ]] ; then
         break
      fi

      l_advance

      # Skip whitespace.
      if [[ $CURRENT =~ [[:space:]] ]] ; then
         continue
      fi

      # Save current cursor information.
      FREEZE['offset']=${CURSOR['offset']}
      FREEZE['lineno']=${CURSOR['lineno']}
      FREEZE['colno']=${CURSOR['colno']}

      # Symbols.
      case $CURRENT in
         '$')  Token  'DOLLAR' "$CURRENT"  ; continue ;;
         '%')  Token 'PERCENT' "$CURRENT"  ; continue ;;
      esac

      # Identifiers.
      if [[ $CURRENT =~ [[:alpha:]_] ]] ; then
         l_identifier ; continue
      fi

      raise invalid_interpolation_char "$CURRENT"
   done
}


function l_fstring {
   local -a buffer=()

   while [[ $PEEK ]] ; do
      l_advance

      if [[ $CURRENT == '"' ]] ; then
         # shellcheck disable=SC1003
         # ^-- mistakenly thinks I'm trying to escape a single quote 1j.
         if [[ $buffer && ${buffer[-1]} == '\' ]] ; then
            # shellcheck disable=SC2184
            unset buffer[-1]
         else
            break
         fi
      fi

      # When used outside an expression, closing braces must be escaped.
      if [[ $CURRENT == '}' ]] ; then
         if [[ $buffer && "${buffer[-1]}" == '\' ]] ; then
            unset buffer[-1]
            buffer+=( "$CURRENT" )
            continue
         else
            raise unescaped_interpolation_brace
         fi
      fi

      # Start of f-string.
      if [[ $CURRENT == '{' ]] ; then
         if [[ $buffer && "${buffer[-1]}" == '\' ]] ; then
            unset buffer[-1]
            buffer+=( "$CURRENT" )
            continue
         fi

         # When beginning f-expressions, create a STRING token for all the text
         # found prior and reset the string buffer.
         local join=''
         for c in "${buffer[@]}" ; do
            join+="$c"
         done
         buffer=()

         Token 'STRING'  "$join"
         Token 'CONCAT'  ''

         # TODO: refactor
         # This may be a little janky. If the user has an empty expression...
         #> _: f'{}';
         #...there will be two subsequent concat tokens, with nothing between.
         #> path('') CAT CAT path('')
         #>             ^-- expr would go here.
         #
         # In that case we want to only add one concatenation token before, and
         # omit the closing one.
         local t0="$TOKEN_NUM"

         l_interpolation
         l_advance # past the closing `}'

         # Only create the closing CONCAT token if there were contents to the
         # expression.
         local t1="$TOKEN_NUM"
         if [[ ! "$t0" -eq "$t1" ]] ; then
            Token 'CONCAT'  ''
         fi

         continue
      fi

      buffer+=( "$CURRENT" )
   done

   local join=''
   for c in "${buffer[@]}" ; do
      join+="$c"
   done

   # Create token.
   Token 'STRING' "$join"
}


function l_fpath {
   local -a buffer=()

   while [[ $PEEK ]] ; do
      l_advance

      if [[ $CURRENT == "'" ]] ; then
         # shellcheck disable=SC1003
         # ^-- mistakenly thinks I'm trying to escape a single quote 1j.
         if [[ $buffer && ${buffer[-1]} == '\' ]] ; then
            # shellcheck disable=SC2184
            unset buffer[-1]
         else
            break
         fi
      fi

      # When used outside an expression, closing braces must be escaped.
      if [[ $CURRENT == '}' ]] ; then
         if [[ $buffer && "${buffer[-1]}" == '\' ]] ; then
            unset buffer[-1]
            buffer+=( "$CURRENT" )
            continue
         else
            raise unescaped_interpolation_brace
         fi
      fi

      # Start of f-path.
      if [[ $CURRENT == '{' ]] ; then
         if [[ $buffer && "${buffer[-1]}" == '\' ]] ; then
            unset buffer[-1]
            buffer+=( "$CURRENT" )
            continue
         fi

         # When beginning f-expressions, create a PATH token for all the text
         # found prior and reset the string buffer.
         local join=''
         for c in "${buffer[@]}" ; do
            join+="$c"
         done
         buffer=()

         Token 'PATH'    "$join"
         Token 'CONCAT'  ''

         # TODO: refactor
         # This may be a little janky. If the user has an empty expression...
         #> _: f'{}';
         #...there will be two subsequent concat tokens, with nothing between.
         #> path('') CAT CAT path('')
         #>             ^-- expr would go here.
         #
         # In that case we want to only add one concatenation token before, and
         # omit the closing one.
         local t0="$TOKEN_NUM"

         l_interpolation
         l_advance # past the closing `}'

         # Only create the closing CONCAT token if there were contents to the
         # expression.
         local t1="$TOKEN_NUM"
         if [[ ! "$t0" -eq "$t1" ]] ; then
            Token 'CONCAT'  ''
         fi

         continue
      fi

      buffer+=( "$CURRENT" )
   done

   local join=''
   for c in "${buffer[@]}" ; do
      join+="$c"
   done

   # Create token.
   Token 'PATH' "$join"
}
