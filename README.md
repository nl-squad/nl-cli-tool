# 🚢 nl-cli-tool

Tool for NL servers management and control. Created because of a lack of public tools for managing CoD2 servers. The settings should be defined in a `project-definition.json` file. You can create one basing on the example [sample.project-definition.json](https://github.com/nl-squad/nl-cli-tool/blob/main/sample.project-definition.json).

# 🌱 Features for managing a remote server

- direct connect
- deploying the local repository version
- restarting the remote server
- getting logs
- reloading the current map
- rotating the current map
- changing to any given map
- executing a remote command as RCON
- getting info and status
- creating .iwd files
- unpacking .iwd files

# 🛫 Installation

Just clone this repository and create the link and alias as in the example below.

```sh
sudo ln -s $(pwd)/mynl.sh /usr/local/bin/mynl.sh
alias mynl='mynl.sh'
```
