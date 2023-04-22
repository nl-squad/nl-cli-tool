#!/usr/bin/env node

const { program } = require('commander');

function exec(cmd) {
    const execFn = require('child_process').exec;
    return new Promise((resolve, reject) => {
        execFn(cmd, (error, stdout, stderr) => {
            if (error) {
                console.warn(error);
            }
            resolve(stdout ? stdout : stderr);
        });
    });
}

program.command('connect')
  .description('Connects to the machine')
  .argument('[project-name]', 'Project name (for example: nl-cod2-test, nl-cod2-zom)', null)
  .action(async (projectName) => {
    const a = await exec("ls -la");
    console.log(a);
  });

program.parse();
