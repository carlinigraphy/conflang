#!/usr/bin/awk -f
#
# Set as variables from the calling script:
#  STRIP_COMMENTS  :: set non-empty to skip comments
#  STRIP_NEWLINES  :: set non-empty to skip empty lines
#  SUBSCRIBE       :: comma delimited list of topics

BEGIN {
   true  = 1
   false = 0

   # Currently active topic(s). Print while active and subscribed to.
   delete TOPIC[0]

   split(SUBSCRIBE, subscribed, ",")
   for (i in subscribed) {
      if (!i) continue
      sub(/(^\s*|\s*$)/, "", subscribed[i])
      SUBSCRIBED_TO[subscribed[i]] = true
   }
}


function no_topics(   i) {
   for (i in TOPIC) return false
   return true
}


function active_topic(   t) {
   for (i in TOPIC) {
      if (SUBSCRIBED_TO[i]) return true
   }
   return false
}

# Give bash dot notation for accessing nested array elements.
match($0, /\$\{[[:alpha:]_][[:alnum:]_]*(\.[[:alpha:]_][[:alnum:]_]*)+\}/) {
   text = substr($0, RSTART, RLENGTH)
   sub(/^\$\{/, "", text) ; sub(/\}$/, "", text)
   split(text, words, ".")

   match($0, /^\s*/)
   column = RLENGTH
   indent = ""

   while (column) {
      indent = indent " "
      column = column - 1
   }

   print indent "unset '__'"
   print indent "declare -n __=\"${"  words[1]  "}\""

   len = 0
   for (w in words) len = len + 1

   for (idx=2; idx<len; ++idx) {
      print indent "declare -n __=\"${__['"  words[idx]  "']}\""
   }

   repl = "${__['"  words[len]  "']}"

   sub(/\$\{[[:alpha:]_][[:alnum:]_]*(\.[[:alpha:]_][[:alnum:]_]*)+\}/, repl)
}

# Begin topic.
/^\s*#\s*>>\s*TOPIC\s*/ {
   sub(/^\s*#\s*>>\s*TOPIC\s*/, "")
   split($0, topics, ",")

   for (i in topics) {
      if (!i) continue
      sub(/(^\s*|\s*$)/, "", topics[i])
      TOPIC[topics[i]] = true
   }

   next
}

# End topic.
/^\s*#\s*<<\s*END\s*TOPIC\s*/ {
   sub(/^\s*#\s*<<\s*END\s*TOPIC\s*/, "")
   split($0, topics, ",")

   for (i in topics) {
      if (!i) continue
      sub(/(^\s*|\s*$)/, "", topics[i])
      delete TOPIC[topics[i]]
   }

   next
}

/^#!/ && (FNR == 1) && (FNR != NR) { next }  # Skips non-first `#!`
{ sub(/\s*$/, "") }                          # Clean up EOL whitespace
STRIP_COMMENTS && /^\s*#/ { next }           # Skip comments.
STRIP_COMMENTS { sub(/\s+#.*$/, "") }        # Strip in-line comments.
STRIP_NEWLINES && /^\s*$/ { next }           # Skip empty lines.

# Not in a topic (regular text), or a topic that's active, and we're subscribed
# to it.
no_topics() || active_topic() { print }
