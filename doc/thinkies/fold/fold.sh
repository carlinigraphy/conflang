#!/bin/bash
#
# Given the following input:
#> S0 {
#>   a: [1, S0>b];
#>   b: 2;
#>   S1 {
#>     c: 3;
#>   }
#> }
#
#-- Compiles to...
# %inline;
declare -A _ROOT=(
   [S0]=SKELLY1
)

# S0;
declare -A SKELLY1=(
   [a]=SKELLY2
   [b]=SKELLY3
   [S1]=SKELLY4
)

# S0> a;
declare -- SKELLY2=DATA1
declare -a DATA1=(
   1
   2
)

# S0> b;
declare -- SKELLY3=2

# S0> S1
declare -A SKELLY4=(
   [c]=SKELLY5
)

# S0> S1> c
declare -- SKELLY5=3


#--
declare -A IS_SECTION=(
   [_ROOT]=true
   [SKELLY1]=true
   [SKELLY4]=true
)


#--
function fold {
   local -n src="$1"

   for key in "${!src[@]}" ; do
      local skelly="${src[$key]}"

      if [[ ${IS_SECTION[$skelly]} ]] ; then
         fold "$skelly"
      else
         local -n val="$skelly"
         src[$key]="$val"
         unset $skelly
      fi
   done
}


fold _ROOT
declare -p _ROOT
declare -p ${!SKELLY*}
declare -p ${!DATA*}


#-- Results in:
#> declare -A _ROOT=(
#>    [S0]="SKELLY1"
#> )
#> declare -A SKELLY1=(
#>    [a]="DATA1"
#>    [b]="2"
#>    [S1]="SKELLY4"
#> )
#> declare -a DATA1=(
#>    [0]="1"
#>    [1]="2"
#> )
#> declare -A SKELLY4=(
#>    [c]="3"
#> )

# or...

#> _ROOT = {
#>    S0: {
#>       a: [1, 2],
#>       b: 2,
#>       S1: {
#>          c: 3
#>       }
#>    }
#> }

# Yay, that's correct!

# Things that are important to note...
# Leaf expressions must not have their own DATA node, but are attached directly
# to the SKELLY. Example...
#
#> key: 1;
#
# ...should result in...
#
#> declare -- SKELLY_1="1"
#
# ...and not...
#
#> declare -- SKELLY_1="DATA_1"
#> declare -- DATA_1="1"
#
# Secondly, pointers to nodes must never point to the SKELLY, always the node to
# which the SKELLY refers. For leafy expressions, that will be the expression
# itself. For references to sections/arrays, it shall point to the resulting
# SKELLY/DATA node respectively.
