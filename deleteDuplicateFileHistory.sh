#!/bin/bash

i=1
cat ~/.encode_file | while read l
do
    f=`echo $l | cut -f1 -d'#'`
    b=`basename "$f"`
    file_name=`echo ${b%.*}`
    dir_name=`dirname "$f"`
    search="$dir_name/$file_name\.[a-z]"
    count=`cat ~/.encode_file | grep "$search" | wc -l`
    if [ $count -gt 1 ]
    then
        echo $l
        sed -i $i'd' ~/.encode_file
    else
        i=$((i+1))
    fi
done
