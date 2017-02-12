#!/bin/bash

i=1
cat ~/.encode_file | while read l
do 
    f=`echo $l | cut -f1 -d'#'`
    count=`cat ~/.encode_file | grep "$f" | wc -l`
    if [ $count -gt 1 ]
    then
        echo $l
        sed -i $i'd' ~/.encode_file
    else
        i=$((i+1))
    fi
done
