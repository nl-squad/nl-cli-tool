#!/bin/zsh

project=$(basename $PWD)

function print_usage()
{
    echo "Usage: nl.sh"
}

if [[ $1 == "connect" ]]; then
    echo "Connecting to mynl.pl SSH"
else
    echo "Error: Invalid verb '$1'"
    print_usage
    exit 1
fi