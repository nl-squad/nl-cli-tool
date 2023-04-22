#!/usr/bin/env node

const { program } = require('commander');

program.command('connect')
  .description('Connects to the machine')
  .argument('<project-name>', 'Project name (for example: nl-cod2-test, nl-cod2-zom)')
  .action((projectName) => {
    console.log(projectName);
  });

program.parse();
