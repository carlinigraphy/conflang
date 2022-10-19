## ref.
# a = []           # 0             N_1
# b = ['a', 'c']   #    3          N_2
# c = ['d', 'e']   #   2           N_3
# d = []           # 0             N_4
# e = ['f']        #  1            N_5
# f = []           # 0             N_6

declare -a N_1=()
declare -a N_2=( N_1  N_3 )
declare -a N_3=( N_4  N_5 )
declare -a N_4=()
declare -a N_5=( N_6 )
declare -a N_6=()

DEPTH=0

declare -A unordered=()
declare -a ordered=()

function get_depth {
   local -- nname="$1"
   local -n node="$nname"
   local -i level="${2:-0}"

   if ! (( ${#node[@]} )) ; then
      DEPTH="$level" ; return
   fi

   (( ++level ))
   local _depth="$DEPTH"

   local -- n
   local -a levels=()

   for n in "${node[@]}" ; do
      get_depth  "$n"  "$level"
      levels+=( $DEPTH )
   done

   declare -g DEPTH="$_depth"

   local max="${levels[0]}"
   for n in "${levels[@]}" ; do
      (( max = (n > max) ? n : max ))
   done

   DEPTH="${max}"
}


function make_order {
   local -i  i=0  num
   local --  key
   
   while (( ${#unordered[@]} > 0 )) ; do
      for key in "${!unordered[@]}" ; do
         num=${unordered[$key]}
         if (( num == i )) ; then
            unset 'unordered[$key]'
            ordered+=( $key )
         fi
      done
      (( ++i ))
   done
}


function sort {
   local i n

   for i in $(seq 1 6) ; do
      n="N_${i}"
      get_depth "$n"
      unordered[$n]="$DEPTH"
   done

   make_order
}


sort

printf '%s,' "${ordered[@]}"
printf '\n'
