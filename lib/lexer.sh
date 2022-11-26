#!/bin/bash

declare -gi TOKEN_NUM=0

declare -gA KEYWORD=(
   ['true']=true
   ['false']=true
   ['import']=true
   ['as']=true
   ['typedef']=true
)

function lexer:init {
   # Some variables need to be reset at the start of every run. They hold
   # information that should not be carried from file to file.

   (( FILE_IDX = ${#FILES[@]} - 1 )) ||:

   local lines="FILE_${FILE_IDX}_LINES"
   declare -ga "$lines"
   declare -g  FILE_LINES="$lines"

   declare -g   CHAR=''  PEEK_CHAR=''
   declare -ga  CHARRAY=()
   declare -ga  TOKENS=()
   declare -gA  FREEZE CURSOR=(
      [index]=-1
      [lineno]=1
      [colno]=0
   )
}


function token:new {
   local type=$1  value=$2

   (( ++TOKEN_NUM ))
   local token="TOKEN_${TOKEN_NUM}"
   declare -gA "$token"
   TOKENS+=( "$token" )

   # Nameref to newly created global token.
   declare -n t_r="$token"

   # Token data.
   t_r['type']="$type"
   t_r['value']="$value"

   location:new
   t_r['location']="$LOCATION"

   local -n loc_r="$LOCATION"
   loc_r['file']="$FILE_IDX"
   loc_r['start_ln']="${FREEZE[lineno]}"
   loc_r['start_col']="${FREEZE[colno]}"
   loc_r['end_ln']="${CURSOR[lineno]}"
   loc_r['end_col']="${CURSOR[colno]}"
}


function lexer:advance {
   (( ++CURSOR['colno'] )) ||:
   (( ++CURSOR['index'] )) ||:
   local -i idx="${CURSOR[index]}"

   declare -g CHAR="${CHARRAY[$idx]}"
   declare -g PEEK_CHAR="${CHARRAY[$idx + 1]}"

   if [[ "$CHAR" == $'\n' ]] ; then
      ((CURSOR['lineno']++))
      CURSOR['colno']=0
   fi
}


function lexer:scan {
   # For later error reporting. Easier to report errors by line number if we
   # have them in lines... by number...
   local -n file_lines_r="$FILE_LINES"
   mapfile -t -O1 file_lines_r < "${FILES[-1]}"

   # For easier lookahead, read all characters first into an array. Allows us
   # to seek/index very easily.
   while read -rN1 character ; do
      CHARRAY+=( "$character" )
   done < "${FILES[-1]}"

   while (( "${CURSOR[index]}" < ${#CHARRAY[@]} )) ; do
      lexer:advance ; [[ ! "$CHAR" ]] && break

      # Save current cursor information.
      FREEZE['index']=${CURSOR['index']}
      FREEZE['lineno']=${CURSOR['lineno']}
      FREEZE['colno']=${CURSOR['colno']}

      # Skip comments.
      if [[ $CHAR == '#' ]] ; then
         lexer:comment ; continue
      fi

      # Skip whitespace.
      if [[ $CHAR =~ [[:space:]] ]] ; then
         continue
      fi

      # Symbols.
      case $CHAR in
         '@')  token:new  'AT'        "$CHAR"  ; continue ;;
         '.')  token:new  'DOT'       "$CHAR"  ; continue ;;
         ',')  token:new  'COMMA'     "$CHAR"  ; continue ;;
         ';')  token:new  'SEMI'      "$CHAR"  ; continue ;;
         ':')  token:new  'COLON'     "$CHAR"  ; continue ;;
         '$')  token:new  'DOLLAR'    "$CHAR"  ; continue ;;
         '?')  token:new  'QUESTION'  "$CHAR"  ; continue ;;
                                      
         '(')  token:new  'L_PAREN'   "$CHAR"  ; continue ;;
         ')')  token:new  'R_PAREN'   "$CHAR"  ; continue ;;

         '[')  token:new  'L_BRACKET' "$CHAR"  ; continue ;;
         ']')  token:new  'R_BRACKET' "$CHAR"  ; continue ;;

         '{')  token:new  'L_BRACE'   "$CHAR"  ; continue ;;
         '}')  token:new  'R_BRACE'   "$CHAR"  ; continue ;;
      esac

      # Typecast, or minus.
      if [[ $CHAR == '-' ]] ; then
         # If subsequent `>', is an arrow for typecast.
         if [[ $PEEK_CHAR == '>' ]] ; then
            lexer:advance
            token:new 'ARROW' '->'
         else
            token:new 'MINUS' '-'
         fi

         continue
      fi

      # f-{strings,paths}
      if [[ $CHAR == 'f' ]] ; then
         if   [[ $PEEK_CHAR == '"' ]] ; then
            lexer:advance ; lexer:fstring
            continue
         elif [[ $PEEK_CHAR == "'" ]] ; then
            lexer:advance ; lexer:fpath
            continue
         fi
      fi

      # Identifiers.
      if [[ $CHAR =~ [[:alpha:]_] ]] ; then
         lexer:identifier ; continue
      fi

      # Strings. Surrounded by `"`.
      if [[ $CHAR == '"' ]] ; then
         lexer:string ; continue
      fi

      # Paths. Surrounded by `'`.
      if [[ $CHAR == "'" ]] ; then
         lexer:path ; continue
      fi

      # Numbers.
      if [[ $CHAR =~ [[:digit:]] ]] ; then
         # Bash only natively handles integers. It's not able to do floats
         # without bringing `bc` or something. For now, that's all we'll also
         # support. Maybe later I'll add a float type, just so I can write some
         # external functions that support float comparisons. Or maybe you just
         # accept that you're taking a performance hit by using floats. More
         # subshells and whatnot.
         lexer:number ; continue
      fi

      token:new 'ERROR'
      local -n t_r="${TOKENS[-1]}"
      e=( syntax_error
         --anchor "${t_r[location]}"
         --caught "${t_r[location]}"
          "invalid character [$CHAR]"
      ); raise "${e[@]}"
   done

   FREEZE[lineno]="${CURSOR[lineno]}"
   FREEZE[colno]="${CURSOR[colno]}"
   token:new 'EOF'
}


function lexer:comment {
   # There are no multiline comments. Seeks from '#' to the end of the line.
   while [[ -n $CHAR ]] ; do
      [[ "$PEEK_CHAR" =~ $'\n' ]] && break
      lexer:advance
   done
}


function lexer:identifier {
   local buffer="$CHAR"

   while [[ -n $CHAR ]] ; do
      [[ $PEEK_CHAR =~ [^[:alnum:]_] ]] && break
      lexer:advance ; buffer+="$CHAR"
   done

   if [[ ${KEYWORD[$buffer]} ]] ; then
      token:new "${buffer^^}" "$buffer"
   else
      token:new 'IDENTIFIER' "$buffer"
   fi
}


function lexer:string {
   local -a buffer=()

   while [[ $PEEK_CHAR ]] ; do
      lexer:advance

      if [[ $CHAR == '"' ]] ; then
         # shellcheck disable=SC1003
         # Misidentified error.
         if [[ $buffer && ${buffer[-1]} == '\' ]] ; then
            # shellcheck disable=SC2184
            unset buffer[-1]
         else
            break
         fi
      fi

      buffer+=( "$CHAR" )
   done

   local join=''
   for c in "${buffer[@]}" ; do
      join+="$c"
   done

   # Create token.
   token:new 'STRING' "$join"
}


function lexer:path {
   local -a buffer=()

   while [[ $PEEK_CHAR ]] ; do
      lexer:advance

      if [[ $CHAR == "'" ]] ; then
         # shellcheck disable=SC1003
         # Misidentified error.
         if [[ $buffer && ${buffer[-1]} == '\' ]] ; then
            # shellcheck disable=SC2184
            unset buffer[-1]
         else
            break
         fi
      fi

      buffer+=( "$CHAR" )
   done

   local join=''
   for c in "${buffer[@]}" ; do
      join+="$c"
   done

   # Create token.
   token:new 'PATH' "$join"
}


function lexer:number {
   local number="${CHAR}"

   while [[ $PEEK_CHAR =~ [[:digit:]] ]] ; do
      lexer:advance ; number+="$CHAR"
   done

   token:new 'INTEGER' "$number"
}


function lexer:interpolation {
   location:cursor
   local anchor="$LOCATION"

   while [[ "${CURSOR[index]}" -lt ${#CHARRAY[@]} ]] ; do
      # String interpolation ends upon a closing R_BRACE token, or if there's
      # no current character.
      if [[ ! $CHAR ]] || [[ $PEEK_CHAR == '}' ]] ; then
         break
      fi

      lexer:advance

      # Skip whitespace.
      if [[ $CHAR =~ [[:space:]] ]] ; then
         continue
      fi

      # Save current cursor information.
      FREEZE['index']=${CURSOR['index']}
      FREEZE['lineno']=${CURSOR['lineno']}
      FREEZE['colno']=${CURSOR['colno']}

      case $CHAR in
         '.')  token:new        'DOT' "$CHAR"  ; continue ;;
         '$')  token:new     'DOLLAR' "$CHAR"  ; continue ;;
         '[')  token:new  'L_BRACKET' "$CHAR"  ; continue ;;
         ']')  token:new  'R_BRACKET' "$CHAR"  ; continue ;;
      esac

      # Identifiers.
      if [[ $CHAR =~ [[:alpha:]_] ]] ; then
         lexer:identifier ; continue
      fi

      token:new 'ERROR'
      local -n t_r="${TOKENS[-1]}"
      e=( invalid_interpolation_char
         --anchor "$anchor"
         --caught "${t_r[location]}"
         "invalid character in fstring [$CHAR]"
      ); raise "${e[@]}"
   done
}


function lexer:fstring {
   local -a buffer=()

   while [[ $PEEK_CHAR ]] ; do
      lexer:advance

      if [[ $CHAR == '"' ]] ; then
         # shellcheck disable=SC1003
         if [[ $buffer && ("${buffer[-1]}" == '\') ]] ; then
            unset 'buffer[-1]'
         else
            break
         fi
      fi

      # When used outside an expression, closing braces must be escaped.
      if [[ $CHAR == '}' ]] ; then
         if [[ $buffer && "${buffer[-1]}" == '\' ]] ; then
            unset buffer[-1]
            buffer+=( "$CHAR" )
            continue
         else
            token:new 'ERROR'
            local -n t_r="${TOKENS[-1]}"
            location:cursor
            e=( unescaped_interpolation_brace
               --anchor "${t_r[location]}"
               --caught "$LOCATION"
            ); raise "${e[@]}"
         fi
      fi

      # Start of f-string.
      if [[ $CHAR == '{' ]] ; then
         if [[ $buffer && "${buffer[-1]}" == '\' ]] ; then
            unset buffer[-1]
            buffer+=( "$CHAR" )
            continue
         fi

         # When beginning f-expressions, create a STRING token for all the text
         # found prior and reset the string buffer.
         local join=''
         for c in "${buffer[@]}" ; do
            join+="$c"
         done
         buffer=()

         token:new 'STRING'  "$join"
         token:new 'CONCAT'

         # In the case of an empty expression...
         #> _: f'{}';
         #...there will be two subsequent concat tokens, with nothing between.
         #> path('') CAT CAT path('')
         #>             ^-- expr would go here.
         #
         # In that case we want to only add one concatenation token before, and
         # omit the closing one.
         local t0="$TOKEN_NUM"

         lexer:interpolation
         lexer:advance # past the closing `}'

         # Only create the closing CONCAT token if there were contents to the
         # expression.
         local t1="$TOKEN_NUM"
         if (( $t0 != $t1 )) ; then
            token:new 'CONCAT'
         fi

         continue
      fi

      buffer+=( "$CHAR" )
   done

   local join=''
   for c in "${buffer[@]}" ; do
      join+="$c"
   done

   # Create token.
   token:new 'STRING' "$join"
}


function lexer:fpath {
   local -a buffer=()

   while [[ $PEEK_CHAR ]] ; do
      lexer:advance

      if [[ $CHAR == "'" ]] ; then
         # shellcheck disable=SC1003
         if [[ $buffer && ("${buffer[-1]}" == '\') ]] ; then
            unset 'buffer[-1]'
         else
            break
         fi
      fi

      # When used outside an expression, closing braces must be escaped.
      if [[ $CHAR == '}' ]] ; then
         if [[ $buffer && "${buffer[-1]}" == '\' ]] ; then
            unset buffer[-1]
            buffer+=( "$CHAR" )
            continue
         else
            token:new 'ERROR'
            local -n t_r="${TOKENS[-1]}"
            location:cursor
            e=( unescaped_interpolation_brace
               --anchor "${t_r[location]}"
               --caught "$LOCATION"
            ); raise "${e[@]}"
         fi
      fi

      # Start of f-path.
      if [[ $CHAR == '{' ]] ; then
         if [[ $buffer && "${buffer[-1]}" == '\' ]] ; then
            unset buffer[-1]
            buffer+=( "$CHAR" )
            continue
         fi

         # When beginning f-expressions, create a PATH token for all the text
         # found prior and reset the string buffer.
         local join=''
         for c in "${buffer[@]}" ; do
            join+="$c"
         done
         buffer=()

         token:new 'PATH'  "$join"
         token:new 'CONCAT'

         # In the case of an empty expression...
         #> _: f'{}';
         #...there will be two subsequent concat tokens, with nothing between.
         #> path('') CAT CAT path('')
         #>             ^-- expr would go here.
         #
         # In that case we want to only add one concatenation token before, and
         # omit the closing one.
         local t0="$TOKEN_NUM"

         lexer:interpolation
         lexer:advance # past the closing `}'

         # Only create the closing CONCAT token if there were contents to the
         # expression.
         local t1="$TOKEN_NUM"
         if (( $t0 != $t1 )) ; then
            token:new 'CONCAT'
         fi

         continue
      fi

      buffer+=( "$CHAR" )
   done

   local join=''
   for c in "${buffer[@]}" ; do
      join+="$c"
   done

   # Create token.
   token:new 'PATH' "$join"
}
