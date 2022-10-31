#!/usr/bin/awk -f

BEGIN {
   skip = "no"
}

/^\s*#\s?!SKIP/ { skip = "no"  }    # End skip region.
/^\s*#\s?SKIP!/ { skip = "yes" }    # Start skip region.
{ if (skip == "yes") next }         # In skip-region.

/^\s*#/ { next }                    # Ignore comments.
/^\s*$/ { next }                    # Ignore empty lines.
{ sub(/\s*$/, "") }                 # Trim trailing space.
{ sub(/\s*#.*$/, "") }              # Trim line-comments.

{
   print
}
