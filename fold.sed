#!/bin/sed -nf
#
# Fold blank-line separated blocks into a single line

# Blank line
/^$/ {
  # Exchange hold with pattern space
  x
  s/\n/ /g
  s/^ //
  p
  d
}

# Non-blank line
/^./ {
 # Append hold to pattern space
 H
}

# Handle last line
$ {
 x
  s/\n/ /g
  s/^ //
  p
}
