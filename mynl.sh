#!/bin/zsh

project=$(basename $PWD)

function print_usage()
{
    echo "Usage: nl.sh"
}

function exec_ssh()
{
    ssh -i ~/.ssh/nl -t ubuntu@mynl.pl "$1"
}

if [[ $1 == "connect" ]]; then
    echo "Connecting to mynl.pl SSH"
    exec_ssh "cd ~/cod2/servers/$project ; bash --login"
else
    echo "Error: Invalid verb '$1'"
    print_usage
    exit 1
fi