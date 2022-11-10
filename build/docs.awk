#!/usr/bin/env awk -f
# vim: ft=awk tw=80 sw=3 ts=3 sts=3
#
# It would be trivial to write this in bash. Will likely make a bash version
# down the line. However I've wanted to learn more "advanced" AWK for a great
# long while. This is a good project to do so.
#
# Attempting something to build documentation from comments. Javadoc style. Not
# too sure on the format I'm going with. Probably going to mirror very similar
# functionality from shdoc.
#
#-------------------------------------------------------------------------------
# ref.
# [0] https://github.com/reconquest/shdoc
# [1] https://www.math.utah.edu/docs/info/gawk_12.html
# [2] https://www.gnu.org/software/gawk/manual/html_node/Multidimensional.html
# [3] https://www.gnu.org/software/gawk/manual/html_node/Arrays-of-Arrays.html
# [4] https://www.gnu.org/software/gawk/manual/html_node/Variable-Scope.html
# [5] https://www.math.utah.edu/docs/info/gawk_13.html
#
#-------------------------------------------------------------------------------
# Some notes on things I'd want:
#
# @notes       Additional notes about implementation, things to look out for
# @type        Declare something as a "type", hyperlink other references to
#              types (in functions and whatnot) to the declared type. Helps
#              to build a 'map' of where everything is used.
# @arg         Declares an argument to a function by the name it's referred
#              to as within the function, and its type.
# @noarg       Same as shdoc
# @section     Same as shdoc
# @see         Same as shdoc
# @stdin       Same as shdoc
# @stdout      Same as shdoc
# @stderr      Same as shdoc
# @internal    Same as shdoc
# @does        Same as shdoc's @description
# @global:r    Global variables READ
# @global:w    Global variables SET
# @global:rw   Global variables UPDATE
#
# Maybe actually build an html doc, if possible, instead of a .md doc. Still
# similar to produce, yes easier to open in any browser.
#
#-------------------------------------------------------------------------------
# TODO
# - [ ] Different output formatters
#       - [ ] HTML
#       - [ ] Markdown
#
#-------------------------------------------------------------------------------

BEGIN {
   ## "Declaring" variables to be used later:
   #
   # Array to hold any errors encountered during parsing.
   #let errors[];
   #
   ## Current indentation level. For something to be considered in the same
   ## "block", it must be at least at a matching indentation level.
   #let indentation = 0

   # Color escapes. For pretty-printing debugging & error information.
   c["rst"] = "\033[0m"
   c["rd"]  = "\033[31;1m"
   c["yl"]  = "\033[33;1m"
   c["cy"]  = "\033[35m"

   # Convenience variables to make boolean assignments more clear.
   false = 0
   true  = 1

   # Upon hitting an error, "panic" until the start of a next valid opt.
   panicking          = false
   opts["@notes"]     = true
   opts["@type"]      = true
   opts["@arg"]       = true
   opts["@noarg"]     = true
   opts["@section"]   = true
   opts["@see"]       = true
   opts["@stdin"]     = true
   opts["@stdout"]    = true
   opts["@stderr"]    = true
   opts["@internal"]  = true
   opts["@does"]      = true
   opts["@global:r"]  = true
   opts["@global:w"]  = true
   opts["@global:rw"] = true

   # Markers if we're in a function, argument, etc. Allows for multline blocks
   # of text for descriptions or whatever.
   in_arg       = false
   in_function  = false

   # Buffer for holding multiline strings.
   buffer = ""

   # Indentation level to apply to the same buffer.
   indentation = 0
}


function lstrip() { sub(/^\s*/, "") }
function rstrip() { sub(/\s*$/, "") }


# Pops the first word of the current line. Removes preceding whitespace before
# and after the .pop()
function pop_word(name) {
   name = $1
   sub(/^[[:space:]]*[^[:space:]]*[[:space:]]*/, "")
   return name
}


function pop_type(type) {
   # Typedefs must be surrounded by parens.
   if (! match($1, /\([[:alpha:]_][[:alnum:]_]*\)/)) {
      panicking = true
      log_error("arg typedef should be in parentheses.", "WARN")
      next
   }

   # Pop first word from stack, remove surrounding parens.
   type = pop_word()
   sub(/^\(/, "", type) ; sub(/\)$/, "", type)
   return type
}


function append(array, item,   idx) {
   while (array[idx]) idx++
   array[idx] = item
}


function set_indentation(text, spaces) {
   while (match(text, /^\s/)) {
      sub(/\s/, "", text)
      spaces++
   }
   indentation = spaces
}


function format(text, level) {
   if (level == "CRIT")   text = c["rd"]  "[CRIT]  "  c["rst"] text
   if (level == "WARN")   text = c["yl"]  "[WARN]  "  c["rst"] text
   if (level == "INFO")   text = c["cy"]  "[INFO]  "  c["rst"] text
   if (level == "DEBUG")  text = c["cy"]  "[DEBUG] "  c["rst"] text
   return text
}


function log_error(text, level) {
   text = "ln. "  NR  ", "  text
   text = format(text, level)
   append(errors, text)
}


function write(text, level) {
   print format(text, level) > "/dev/stderr"
}


function reset_in() {
   in_arg       = false
   in_function  = false
}


function indentation_match() {
   if (! match($0, /^\s+
}


# Test if this line of text should be appended to the current buffer.
indentation_match() {
   idx = indentation_match
   while (idx) {
      sub(/^\s/, "") ; --idx
   }
   buffer = buffer $0
}


# When hitting an error, start skipping lines until we hit a new synchronization
# point--a valid @identifier.
panicking && /^\s*#/ {
   if (opts[$2]) {
      panicking = false
   } else {
      next
   }
}


function build_arg(name, type, desc,   out) {
   name = "<td class='arg_name'>"     name  "</td>"
   type = "<a href=#Types#" type ">"  type  "</a>"
   type = "<td class='arg_type'>"     type  "</td>"
   desc = "<td class='arg_desc'>"     desc  "</td>"

   out = out "<tr class='arg_li'>" 
   out = out name type desc
   out = out "</tr>" 
   
   arg_list = arg_list out
}


function build_type() {
   print
}


# Matches:  # @arg
/^\s*#\s+@arg\s+/ {
   sub(/^\s*#\s+@arg /, "")
   set_indentation($0)

   arg_name = pop_word()
   arg_type = pop_type()
   arg_desc = $0
   build_arg(arg_name, arg_type, arg_desc)

   in_arg      = true
   in_function = true
}


# This is kinda our "synchronization point" for documenting a function. Upon
# hitting the actual `function foo()` block (or equivalent), can store all the
# information related to the function declaration.
in_function &&
/^\s*function\s+[[:alpha:]_][[:alnum:]_]*\s*(\(\)\s*)?{/ ||
/^\s*[[:alpha:]_][[:alnum:]_]*\s*\(\)\s*{/ {
   # Match:  function foo { ... }
   # Match:  function foo() { ... }
   if (match($0, /^\s*function\s+[[:alpha:]_][[:alnum:]_]*\s*(\(\)\s*)?{/)) {
      fn_name = $2
   }

   # Match:  foo() { ... }
   if (match($0, /^\s*[[:alpha:]_][[:alnum:]_]*\s*\(\)\s*{/)) {
      fn_name = $1
   }

   sub(/\(\)/, "", fn_name)      # Remove potential trailing '()'
   sub(/{/,    "", fn_name)      # Remove potential trailing '{'

   in_function = false
}


# Matches:  # @type
/^\s*#\s+@type\s+/ {
   reset_is()

   sub(/^\s*#\s+@type /, "")
   set_indentation($0)

   in_type = true
}


in_type &&
/^\s*declare\s+(-(-|[AagIilnrtux]+))?/ {
   in_type = false
}


# Matches:  # @does
/^\s*#\s+@does\s+/ {
   sub(/^\s*#\s+@does /, "")
   set_indentation($0)
}


# Start with the most basic here, pulling the data out and putting it somewhere?
# Functional style seems to be the way to go. `shdoc` does something like:
#>  toc = concat(toc, html_toc(text))


#function html_li() { }
#function html_ul() { }
#function html_div() { }
#function html_header() { }


# Reset if hitting a non-comment, or a blank line.
/^\s*[^#]/ || /^\s*$/ {
   reset_in()
}


END {
   if (isarray(errors)) {
      for (idx in errors) {
         print errors[idx]
      }
      exit 1
   }

   print "<table>" arg_list "</table>"
}
