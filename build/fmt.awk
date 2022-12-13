#!/usr/bin/awk -f
#
# Set from the environment:
#  STRIP_WHITESPACE  :: set to "yes" if empty lines should be skipped
#  STRIP_COMMENTS    :: set to "yes" if comments should be skipped

BEGIN { skip = "no" }

# Skips shebangs after the initial file's.
/^#!/ && (FNR == 1) && (FNR != NR) { next }

# Clean up EOL whitespace
{ sub(/\s*$/, "") }

# Skip each file's shebang.
/^#!/ { next }

/^\s*#\s?!SKIP/  { skip = "no"  }   # End skip region.
/^\s*#\s?SKIP!/  { skip = "yes" }   # Start skip region.
{ if (skip == "yes") next }         # In skip-region.

# Skip comments.
/^\s*#/ { if (STRIP_COMMENTS == "yes") next }
{ if (STRIP_COMMENTS == "yes") sub(/\s+#.*$/, "") }

# Skip whitespace.
/^\s*$/ { if (STRIP_WHITESPACE == "yes") next }

{ print }
