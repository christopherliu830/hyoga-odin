#!/usr/bin/env zx

import { Command } from 'commander';

const program = new Command();

program
	.name('zx task')

program.command('run')
	.description('build and run hyoga')
	.option('-d, --debug', 'debug build')
	.action(async (d) => { build(d); run(d) })

program.command('build')
	.description('build hyoga')
	.option('-d, --debug', 'debug build')
	.action(build)

program.command('format')
	.description('format source')
	.action(async () => {
		await $`odin fmt src`;
	})

program.parse(process.argv.slice(1));

async function build(d) {
	await $`make ${d ? 'debug' : ''}`;
}
async function run(d) {
	$.cwd = 'build'
	const exe = d ? './hyogad.exe' : './hyoga.exe';
	const exit = await $`${exe}`.nothrow();
	console.log(`Process exited with code ${exit.exitCode}`)
}