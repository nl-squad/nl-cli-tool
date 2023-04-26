#!/bin/zsh

config_file="nl/server.cfg"
if [ ! -f $config_file ]; then
    echo "Error: $config_file doesn't exist. Please use mynl CLI tool from within NL directory."
    exit 1
fi

docker_compose_file=docker-compose.yml
if [ ! -f $config_file ]; then
    echo "Error: $docker_compose_file doesn't exist. Please use mynl CLI tool from within NL directory."
    exit 1
fi

project=$(basename $PWD)

function print_usage()
{
    echo ""
    echo "Control commands:"
    echo -e "mynl connect \t\t\t Connects to the machine."
    echo -e "mynl deploy \t\t\t Sync current content."
    echo -e "mynl clean-deploy \t\t Syncs current content and removes remote files that don't exist locally."
    echo -e "mynl restart \t\t\t Performs docker-compose down and then docker-compose up -d."
    echo -e "mynl logs [tail-lines] \t\t Prints all or last n lines of logs."
    echo ""
    echo "RCON commands:"
    echo -e "mynl serverinfo \t\t Prints server information."
    echo -e "mynl status \t\t\t Prints the status of the server."
    echo -e "mynl rotate \t\t\t Changes map on server to the following one defined in rotation."
    echo -e "mynl map <map-name> \t\t Changes map to requested one."
    echo -e "mynl exec <command> \t\t Performs given command on the server."
}

function exec_ssh()
{
    ssh -i ~/.ssh/nl -t ubuntu@mynl.pl "$1"
}

RCON_RESPONSE=""
function rcon_execute()
{
    ip=mynl.pl
    rcon=$(grep -i 'set rcon_password' $config_file | awk -F\" '{print $2}' | tr -d '[:space:]')
    port=$(grep -i 'COD2_SET_net_port' $docker_compose_file | awk -F': ' '{print $2}' | tr -d '[:space:]')
    cmd=$@

    if [ -z "$rcon" ]; then
        echo "Error: RCON password not found in the $config_file file."
        exit 1
    fi

    if [ -z "$port" ]; then
        echo "Error: Server port not found in the $docker_compose_file file."
        exit 1
    fi

    echo "Executing command '$cmd' for server $ip:$port."

    response=$(echo -n -e "\xff\xff\xff\xffrcon $rcon $cmd" | nc -u -w 2 mynl.pl $port)
    clean_response=${response//$'\xff\xff\xff\xffprint'}
    RCON_RESPONSE=$clean_response
}

if [[ $1 == "connect" ]]; then
    echo "Connecting to mynl.pl SSH"
    exec_ssh "cd ~/cod2/servers/$project ; bash --login"
elif [[ $1 == "deploy" ]]; then
    delete_arg=$([[ $2 == "clean" ]] && echo "--delete")
    rsync -az -e "ssh -i ~/.ssh/nl" --progress ${delete_arg} ./* ubuntu@mynl.pl:~/cod2/servers/$project
    rcon_execute "say ^8[UPDATE] ^7Mod version updated"
elif [[ $1 == "restart" ]]; then
    detach_arg=$([[ $2 == "detach" ]] && echo "-d")
    [[ -z $detach_arg ]] && echo "Ctrl + \\ to detach"
    exec_ssh "cd ~/cod2/servers/$project && docker-compose up --force-recreate ${detach_arg}"
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
elif [[ $1 == "map" ]]; then
    rcon_execute "map $2"
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