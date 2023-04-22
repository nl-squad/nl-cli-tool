#!/bin/zsh

project=$(basename $PWD)

function print_usage()
{
    echo ""
    echo "Control commands:"
    echo "mynl connect \t\t\t Connects to the machine."
    echo "mynl deploy \t\t\t Clears the remote folder and upload current content."
    echo "mynl restart \t\t\t Performs docker-compose down and then docker-compose up -d."
    echo "mynl logs [tail-lines] \t\t Prints all or last n lines of logs."
    echo ""
    echo "RCON commands:"
    echo "mynl status \t\t\t Prints the status of the server."
    echo "mynl serverinfo \t\t\t Prints server information."
    echo "mynl rotate \t\t\t Changes map on server to the following one defined in rotation."
    echo "mynl exec [command] \t\t Performs given command on the server."
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
    cmd=$@

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
elif [[ $1 == "logs" ]]; then
    exec_ssh "docker logs ${2:+--tail $2 }$project"
elif [[ $1 == "serverinfo" ]]; then
    rcon_execute "serverinfo"
    echo $RCON_RESPONSE
elif [[ $1 == "status" ]]; then
    rcon_execute "status"
    echo $RCON_RESPONSE
elif [[ $1 == "rotate" ]]; then
    rcon_execute "map_rotate"
    echo $RCON_RESPONSE
elif [[ $1 == "exec" ]]; then
    rcon_execute "${@:2}"
    echo $RCON_RESPONSE
elif [[ -z $1 ]]; then
    echo "Error: Missing verb"
    print_usage
    exit 1
else
    echo "Error: Invalid verb '$1'"
    print_usage
    exit 1
fi