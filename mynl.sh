#!/bin/zsh

project_definition="project-definition.json"
if [ ! -f $project_definition ]; then
    echo "Error: $project_definition doesn't exist. Please use mynl CLI tool from within NL directory."
    exit 1
fi

### Functions - start
function extract_value_or_exit() {
    local key=$1
    local value=$(jq -r "$key" "$project_definition")

    if [ "$value" = "null" ]; then
        echo "Error: $key not found in the $project_definition file."
        exit 1
    fi

    echo "$value"
}

function extract_value_or_empty() {
    local key=$1
    local value=$(jq -r "$key" "$project_definition")

    if [ "$value" = "null" ] || [ -z "$value" ]; then
        echo ""
    else
        echo "$value"
    fi
}

function echo_colorize() {
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
    echo "Control commands:"
    echo -e "mynl connect \t\t\t Connects to the machine."
    echo -e "mynl deploy \t\t\t Syncs current content."
    echo -e "mynl restart \t\t\t Executes restart.sh on remote machine."
    echo -e "mynl restart detached \t\t Executes restart.sh on remote machine with detached mode."
    echo -e "mynl logs follow \t\t Attaches to project log stream."
    echo -e "mynl logs [tail-lines] \t\t Prints all or last n lines of logs."
    echo -e "mynl unpack \t\t\t Unpacks all iwd files and places them in iwds/ directory."
    echo -e "mynl pack \t\t\t Packs the unpacked iwd files."
    echo -e "mynl sync \t\t\t The one to rule them all - packs, deploys, restarts map or fully restarts if required."
    echo -e "mynl release-version <version> \t Releases a new version by creating a branch from main, deploying, and setting up for public."
    echo -e "mynl finalize-version <version> \t Finalizes development of a version by tagging and pushing the tag to the repository."
    echo ""
    echo "RCON commands:"
    echo -e "mynl getstatus \t\t\t Gets public server status (without using rcon password)."
    echo -e "mynl serverinfo \t\t Prints server information."
    echo -e "mynl status \t\t\t Prints the status of the server."
    echo -e "mynl mapres \t\t\t Restarts the map on server."
    echo -e "mynl rotate \t\t\t Rotates the map on server to the next one."
    echo -e "mynl map <map-name> \t\t Changes map to requested one."
    echo -e "mynl exec <command> \t\t Performs given command on the server."
    echo ""
    echo "To change profile use 'export PROFILE=myprofile'"
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
    source ./secrets
    rcon_password_var="${profile}_rcon_password"

    if [[ -z ${(P)rcon_password_var} ]]; then
        echo "Error: rcon_password not set for profile '$profile'."
        exit 1
    fi

    rcon_password="${(P)rcon_password_var}"
    if [[ -z "${rcon_password// /}" ]]; then
        echo "Error: rcon_password is empty or contains only whitespace."
        exit 1
    fi

    cmd=$@
    server_execute "rcon $rcon_password $cmd"
}

function server_execute()
{
    cod2_port=$(extract_value_or_exit ".profiles.\"$profile\".cod2.port")
    cmd=$@
    obfuscated_cmd=$(echo $cmd | perl -pe 's/(rcon) (\w+) (.+)/\1 ***** \3/g')
    echo "Executing command '$obfuscated_cmd' for server $connection_address:$cod2_port."

    response=$(echo -n -e "\xff\xff\xff\xff$cmd" | nc -u -w 2 $connection_address $cod2_port)
    clean_response=${response//$'\xff\xff\xff\xffprint'}
    clean_response=$(echo $clean_response | LC_ALL=C tr -cd '\11\12\15\40-\176')
    SERVER_RESPONSE=$clean_response
}
### Functions - end

command="$1"
profile=$PROFILE
if [[ -z $profile ]]; then
    profile=default
fi

if [[ $(jq -r ".profiles.\"$profile\"" "$project_definition") = "null" ]]; then
    echo "Error: Profile named '$profile' not found, to change profile try:"
    echo "export PROFILE=myprofile"
    exit 1
fi
echo "Executing with '$profile' profile"

connection_address=$(extract_value_or_exit '.connection.address')

if [[ $command == "connect" ]]; then
    deployment_remote_path=$(extract_value_or_exit ".profiles.\"$profile\".remoteDeploymentPath")
    echo "Connecting to $connection_address SSH"
    exec_ssh "cd $deployment_remote_path ; bash --login"
elif [[ $command == "deploy" ]]; then
    connection_user=$(extract_value_or_exit '.connection.user')
    connection_key_path=$(extract_value_or_exit '.connection.keyPath')
    exclude_list=($(jq -r ".profiles.\"$profile\".rsyncExclude | .[]" "$project_definition"))
    deployment_remote_path=$(extract_value_or_exit ".profiles.\"$profile\".remoteDeploymentPath")
    deployment_local_path=$(extract_value_or_exit ".profiles.\"$profile\".localDeploymentPath")

    for exclude_item in "${exclude_list[@]}"; do
        exclude_options+=("--exclude=$exclude_item")
    done

    source ./secrets
    rcon_password_var="${profile}_rcon_password"
    g_password_var="${profile}_g_password"

    if [[ -z ${(P)rcon_password_var} ]]; then
        echo "Error: rcon_password not set for profile '$profile'."
        exit 1
    fi

    rcon_password="${(P)rcon_password_var}"
    g_password="${(P)g_password_var}"
    cfg_file=$(extract_value_or_empty ".profiles.\"$profile\".cod2.cfgFile")

    if [[ -n "$cfg_file" ]]; then
        cp src/nl/$cfg_file ${cfg_file}.bak

        if [ "$g_password" != " " ]; then
            echo "Setting g_password"
            sed -i '' "s/set g_password \".*\"/set g_password \"$g_password\"/" "src/nl/$cfg_file"
        else
            echo "Clearing g_password"
            sed -i '' 's/set g_password ".*"/set g_password ""/' "src/nl/$cfg_file"
        fi

        if [[ -z "${rcon_password// /}" ]]; then
            echo "Error: rcon_password is empty or contains only whitespace."
            exit 1
        fi

        echo "Setting rcon_password"
        sed -i '' "s/set rcon_password \".*\"/set rcon_password \"$rcon_password\"/" "src/nl/$cfg_file"
    fi

    (cd $deployment_local_path && rsync -az -e "ssh -i $connection_key_path" --progress --delete ${exclude_options[@]} ./* $connection_user@$connection_address:$deployment_remote_path)

    if [[ -n "$cfg_file" ]]; then
        cp ${cfg_file}.bak src/nl/$cfg_file 
        rm ${cfg_file}.bak
    fi

    rcon_execute "say ^8[UPDATE] ^7Mod version updated"
elif [[ $command == "restart" ]]; then
    restart_path=$(extract_value_or_exit ".profiles.\"$profile\".restartPath")
    restart_docker_compose=$(extract_value_or_exit ".profiles.\"$profile\".restartDockerCompose")
    exec_ssh "cd $restart_path && ./restart.sh $restart_docker_compose"
elif [[ $command == "logs" ]]; then
    flag_arg=$([[ $2 == "follow" ]] && echo "-f" || ([[ $2 =~ ^[0-9]+$ ]] && echo "--tail $2" || echo ""))
    project=$(extract_value_or_exit ".profiles.\"$profile\".containerName")
    task_id=$(docker service ps nl-cod2-zom-dev_nl-cod2-zom-dev --filter "desired-state=running" --format "{{.ID}}" -q)
    container_id=$(docker inspect --format '{{.Status.ContainerStatus.ContainerID}}' $task_id)
    docker logs $flag_arg $container_id
elif [[ $command == "serverinfo" ]]; then
    rcon_execute "serverinfo"
    echo $SERVER_RESPONSE
elif [[ $command == "status" ]]; then
    rcon_execute "status"
    echo $SERVER_RESPONSE
elif [[ $command == "getstatus" ]]; then
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
elif [[ $command == "mapres" ]]; then
    rcon_execute "map_restart"
    echo $SERVER_RESPONSE
elif [[ $command == "rotate" ]]; then
    rcon_execute "map_rotate"
    echo $SERVER_RESPONSE
elif [[ $command == "map" ]]; then
    rcon_execute "map $2"
    echo $SERVER_RESPONSE
elif [[ $command == "exec" ]]; then
    rcon_execute "${@:2}"
    echo $SERVER_RESPONSE
elif [[ $command == "unpack" ]]; then
    iwds_path=$(extract_value_or_exit ".profiles.\"$profile\".cod2.iwdsPath") || { echo $iwds_path; exit $?; }

    if [ -d iwds ]; then
        echo "The iwds directory exists. Firstly remove it or pack using 'mynl pack'."
        exit 1
    fi

    echo "Unpacking iwd files from '$iwds_path' to 'iwds' directory"
    for iwd_file in $iwds_path/*.iwd; do
        base_filename=$(basename "$iwd_file")
        target_folder="iwds/$base_filename/all"
        mkdir -p "$target_folder"
        unzip -q "$iwd_file" -d "$target_folder"
        echo "Unpacked: $iwd_file"
    done
elif [[ "$command" == "pack" ]]; then
    iwds_path=$(extract_value_or_exit ".profiles.\"$profile\".cod2.iwdsPath") || { echo $iwds_path; exit $?; }

    echo "Packing directories from 'iwds' to '$iwds_path' iwd files"
    for iwd_folder in iwds/*.iwd/; do
        base_foldername=$(basename "$iwd_folder")
        iwd_path="$iwds_path/$base_foldername"

        temp_dir="iwds/$base_foldername.temp"
        mkdir -p "$temp_dir"

        for subfolder in "$iwd_folder"*; do
            for inner_subfolder in "$subfolder"/*; do
                relative_path="${inner_subfolder#$subfolder/}"
                mkdir -p "$temp_dir/$relative_path"
                cp -R "$inner_subfolder/"* "$temp_dir/$relative_path"
            done
        done

        tmp_iwd_path=$(realpath "iwds")/$base_foldername.tmp
        find "$temp_dir" -type f -exec touch -t 202201010000.00 {} +
        (cd "$temp_dir" && find . -type f \! -name ".DS_Store" | sort | zip -q -X -r -@ "$tmp_iwd_path")

        rm -rf "$temp_dir"

        new_iwd_sha=$(sha256sum $tmp_iwd_path | awk '{print $1}')
        old_iwd_sha=$(sha256sum $iwd_path | awk '{print $1}')

        if [[ "$new_iwd_sha" != "$old_iwd_sha" ]]; then
            mv $tmp_iwd_path $iwd_path
            echo "Packed: $iwd_path"    
        else
            rm $tmp_iwd_path
            echo "Unchanged: $iwd_path"
        fi
    done
elif [[ $command == "sync" ]]; then
    server_execute "getstatus"
    hostname=$(echo "$SERVER_RESPONSE" | awk -F'\\' '{for (i=1; i<=NF; i++) if ($i == "sv_hostname") print $(i+1)}')

    script_dir=$(dirname "$0")
    "$script_dir/mynl.sh" pack
    "$script_dir/mynl.sh" deploy

    if [[ -n "$hostname" ]]; then
        "$script_dir/mynl.sh" mapres
        "$script_dir/mynl.sh" logs follow
    else
        "$script_dir/mynl.sh" restart
    fi
elif [[ $command == "finalize-version" ]]; then
    version=$2
    if [[ -z $version ]]; then
        echo "Error: Version number required to finalize."
        exit 1
    fi
    git checkout "version/$version" && git pull
    git tag $version && git push --tags
    echo "Finalized version $version and pushed tags to remote."

elif [[ $command == "release-version" ]]; then
    new_version=$2
    if [[ -z $new_version ]]; then
        echo "Error: New version number required to release."
        exit 1
    fi
    git checkout main && git pull
    git checkout -b "version/$new_version"
    git push -u origin "version/$new_version"
    script_dir=$(dirname "$0")
    "$script_dir/mynl.sh" pack
    PROFILE=public "$script_dir/mynl.sh" deploy
    echo "Released $new_version to the public server."
elif [[ -z $command ]]; then
    echo "Error: Missing verb"
    print_usage
    exit 1
else
    echo "Error: Invalid verb '$1'"
    print_usage
    exit 1
fi