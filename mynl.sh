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

RCON_RESPONSE=""
function rcon_execute()
{
    ip=mynl.pl
    rcon=$(grep -i 'set rcon_password' nl/server.cfg | awk -F\" '{print $2}')
    port=$(grep -i 'COD2_SET_net_port' docker-compose.yml | awk -F': ' '{print $2}')
    cmd=$1

    echo "Executing command '$cmd' for server $ip:$port"

    response=$(echo -n -e "\xff\xff\xff\xffrcon $rcon $cmd" | nc -u -w 2 mynl.pl $port)
    clean_response=${response//$'\xff\xff\xff\xffprint'}
    RCON_RESPONSE=$clean_response
}

if [[ $1 == "connect" ]]; then
    echo "Connecting to mynl.pl SSH"
    exec_ssh "cd ~/cod2/servers/$project ; bash --login"
elif [[ $1 == "deploy" ]]; then
    exec_ssh "rm -rf ~/cod2/servers/$project/*"
    scp -i ~/.ssh/nl -r ./* ubuntu@mynl.pl:~/cod2/servers/$project
elif [[ $1 == "restart" ]]; then
    exec_ssh "cd ~/cod2/servers/$project && docker-compose down && docker-compose up -d"
elif [[ $1 == "rotate" ]]; then
    rcon_execute "map_rotate"
    echo $RCON_RESPONSE
else
    echo "Error: Invalid verb '$1'"
    print_usage
    exit 1
fi