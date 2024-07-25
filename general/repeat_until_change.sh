#!/bin/sh
export RED=$(tput setaf 1 :-"" 2>/dev/null)
export GREEN=$(tput setaf 2 :-"" 2>/dev/null)
export YELLOW=$(tput setaf 3 :-"" 2>/dev/null)
export BLUE=$(tput setaf 4 :-"" 2>/dev/null)
export RESET=$(tput sgr0 :-"" 2>/dev/null)

delay=1;

while getopts d:c: flag
do
    case "${flag}" in
        d) delay=${OPTARG};;
        c) command=${OPTARG};;
        *) command=$@;;
    esac
done

count=0;

unset prev
while output=$($command);
      let "count++";
      echo $GREEN; printf "$count.   $(date +%F_%T)"; echo $RESET;
      echo "$output";
      echo $BLUE; printf '%.s─' $(seq 1 $(tput cols)); echo $RESET;
      [ "${prev+set}" != set ] || [ "$output" = "$prev" ];
do
    prev=$output;
    sleep $delay;
done
