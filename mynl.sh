#!/bin/zsh

project_definition="project-definition.json"
if [ ! -f $project_definition ]; then
    echo "Error: $project_definition doesn't exist. Please use mynl CLI tool from within NL directory."
    exit 1
fi

function extract_value_or_exit() {
    local key=$1
    local value=$(jq -r "$key" "$project_definition")

    if [ "$value" = "null" ]; then
        echo "Error: $key not found in the $project_definition file."
        exit 1
    fi

    echo "$value"
}


connection_address=$(extract_value_or_exit '.connection.address')

echo_colorize() {
    local input="$1"
    local output="${input//^0/\\e[30m}"
    output="${output//^1/\\e[31m}"
    output="${output//^2/\\e[32m}"
    output="${output//^3/\\e[33m}"
    output="${output//^4/\\e[34m}"
    output="${output//^5/\\e[36m}"
    output="${output//^6/\\e[35m}"
    output="${output//^7/\\e[97m}"
    output="${output//^8/\\e[94m}"
    output="${output//^9/\\e[90m}"
    echo -e "${output}\e[0m"
}

function print_usage()
{
    echo ""
    echo "Control commands:"
    echo -e "mynl connect \t\t\t Connects to the machine."
    echo -e "mynl deploy \t\t\t Sync current content."
    echo -e "mynl deploy clean \t\t Syncs current content and removes remote files that don't exist locally."
    echo -e "mynl restart \t\t\t Executes restart.sh on remote machine."
    echo -e "mynl restart detached \t\t Executes restart.sh on remote machine with detached mode."
    echo -e "mynl logs follow \t\t Attaches to project log stream."
    echo -e "mynl logs [tail-lines] \t\t Prints all or last n lines of logs."
    echo ""
    echo "RCON commands:"
    echo -e "mynl getstatus \t\t\t Gets public server status (without using rcon password)."
    echo -e "mynl serverinfo \t\t Prints server information."
    echo -e "mynl status \t\t\t Prints the status of the server."
    echo -e "mynl rotate \t\t\t Rptates the map on server to the next one."
    echo -e "mynl map <map-name> \t\t Changes map to requested one."
    echo -e "mynl exec <command> \t\t Performs given command on the server."
}

function exec_ssh()
{
    connection_user=$(extract_value_or_exit '.connection.user')
    connection_key_path=$(extract_value_or_exit '.connection.keyPath')
    ssh -i $connection_key_path -t $connection_user@$connection_address "$1"
}

SERVER_RESPONSE=""
function rcon_execute()
{
    rcon=$(extract_value_or_exit '.cod2.rconPassword')
    cmd=$@
    server_execute "rcon $rcon $cmd"
}

function server_execute()
{
    cod2_port=$(extract_value_or_exit '.cod2.port')
    cmd=$@
    obfuscated_cmd=$(echo $cmd | perl -pe 's/(rcon) (\w+) (.+)/\1 ***** \3/g')
    echo "Executing command '$obfuscated_cmd' for server $connection_address:$cod2_port."

    response=$(echo -n -e "\xff\xff\xff\xff$cmd" | nc -u -w 2 $connection_address $cod2_port)
    clean_response=${response//$'\xff\xff\xff\xffprint'}
    clean_response=$(echo $clean_response | tr -cd '\11\12\15\40-\176')
    SERVER_RESPONSE=$clean_response
}

if [[ $1 == "connect" ]]; then
    deployment_path=$(extract_value_or_exit '.deployment.path')
    echo "Connecting to $connection_address SSH"
    exec_ssh "cd $deployment_path ; bash --login"
elif [[ $1 == "deploy" ]]; then
    delete_arg=$([[ $2 == "clean" ]] && echo "--delete")
    connection_user=$(extract_value_or_exit '.connection.user')
    connection_key_path=$(extract_value_or_exit '.connection.keyPath')
    exclude_list=($(jq -r '.deployment.rsyncExclude | .[]' "$project_definition"))
    deployment_path=$(extract_value_or_exit '.deployment.path')
    rsync_exclude_options=""
    for exclude_item in "${exclude_list[@]}"; do
        rsync_exclude_options+=" --exclude=$exclude_item"
    done

    rsync -az -e "ssh -i $connection_key_path" --progress $delete_arg $rsync_exclude_options ./* $connection_user@$connection_address:$deployment_path
    rcon_execute "say ^8[UPDATE] ^7Mod version updated"
elif [[ $1 == "restart" ]]; then
    restart_path=$(extract_value_or_exit '.restart.path')
    detach_arg=$([[ $2 == "detach" ]] && echo "detach")
    [[ -z $detach_arg ]] && echo "Ctrl + \\ to detach"
    exec_ssh "cd $restart_path && ./restart.sh $detach_arg"
elif [[ $1 == "logs" ]]; then
    flag_arg=$([[ $2 == "follow" ]] && echo "-f" || ([[ $2 =~ ^[0-9]+$ ]] && echo "--tail $2" || echo ""))
    project=$(extract_value_or_exit '.deployment.logsContainer')
    exec_ssh "docker logs $flag_arg $project"
elif [[ $1 == "serverinfo" ]]; then
    rcon_execute "serverinfo"
    echo $SERVER_RESPONSE
elif [[ $1 == "status" ]]; then
    rcon_execute "status"
    echo $SERVER_RESPONSE
elif [[ $1 == "getstatus" ]]; then
    server_execute "getstatus"

    # Extract the current map name, hostname, players list, and player count
    current_map=$(echo "$SERVER_RESPONSE" | awk -F'\\' '{for (i=1; i<=NF; i++) if ($i == "mapname") print $(i+1)}')
    hostname=$(echo "$SERVER_RESPONSE" | awk -F'\\' '{for (i=1; i<=NF; i++) if ($i == "sv_hostname") print $(i+1)}')
    players_list=$(echo "$SERVER_RESPONSE" | awk -F'\n' '/^[0-9]+ .*$/ {print $0}')
    player_count=$(echo "$PLAYERS_LIST" | wc -l)

    # Check if the map name and hostname were successfully extracted
    if [ -z "$current_map" ] || [ -z "$hostname" ]; then
        echo "Error: Could not retrieve the required information from the CoD2 server."
    else
        echo "-------------------"
        echo_colorize "$hostname ^7playing ^3$current_map^7, with ^3$player_count ^7players:"

        # Print each player's score and name
        while read -r player; do
            player_score=$(echo "$player" | cut -d' ' -f1)
            player_name=$(echo "$player" | cut -d' ' -f3- | tr -d '"')
            echo_colorize "Name: $player_name ^7| Score: ^2$player_score"
        done <<< "$players_list"
    fi
elif [[ $1 == "rotate" ]]; then
    rcon_execute "map_rotate"
    echo $SERVER_RESPONSE
elif [[ $1 == "map" ]]; then
    rcon_execute "map $2"
    echo $SERVER_RESPONSE
elif [[ $1 == "exec" ]]; then
    rcon_execute "${@:2}"
    echo $SERVER_RESPONSE
elif [[ -z $1 ]]; then
    echo "Error: Missing verb"
    print_usage
    exit 1
else
    echo "Error: Invalid verb '$1'"
    print_usage
    exit 1
fi