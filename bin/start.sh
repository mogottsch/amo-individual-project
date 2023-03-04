#!/bin/bash

DATA_FILE=$1
if [ -z "$DATA_FILE" ]; then
    echo "No data file provided"
    exit 1
fi
IDS_OUTPUT=$(julia ./src/get_ids.jl $DATA_FILE)

# output looks like

# Academic license - for non-commercial use only - expires 2024-01-19
# BEGIN IDS
# LF6T13
# ...
# B7
# END IDS

# we only want the ids
IDS=$(echo "$IDS_OUTPUT" | sed -n '/BEGIN IDS/,/END IDS/p' | sed '1d;$d')


i=0
for id in $IDS; do
    echo "Starting $id"
    zsh -c "sleep $i && julia ./client_main.jl $id" > /dev/null 2>&1 &
    ((i++))
    # alacritty -e zsh -c "julia ./src/distributed/client.jl $id" &
done

# start main julia script
julia ./server_main.jl $DATA_FILE
