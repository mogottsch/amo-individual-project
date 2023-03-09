#!/bin/bash

DATA_FILE=$1
if [ -z "$DATA_FILE" ]; then
    echo "No data file provided"
    exit 1
fi
IDS_OUTPUT=$(julia ./src/get_ids.jl $DATA_FILE)

# we only want the ids
IDS=$(echo "$IDS_OUTPUT" | sed -n '/BEGIN IDS/,/END IDS/p' | sed '1d;$d')

export JULIA_DEBUG="Main"

i=0
for id in $IDS; do
    zsh -c "sleep $i && julia ./client_main.jl $id" > /dev/null 2>&1 &
    ((i++))
done

# start main julia script
julia ./server_main.jl $DATA_FILE
