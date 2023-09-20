import { Command } from 'commander';
import fs from 'node:fs';

const program = new Command();

program
	.name('tasks.mjs')

program.command('run')
	.description('build and run hyoga')
	.option('-d, --debug', 'debug build')
	.action(run)

program.parse();

function run(debug) {
	if (!fs.existsSync('./build')) {
		fs.mkdirSync('./build');
	}

	const command = debug ? ['make', 'debug'] : ['make'];
	const proc = Bun.spawnSync(command, {
		stdout: 'inherit',
		stderr: 'inherit'
	});

	if (!proc.success) return console.log('Build failed');

	console.log('Running...');

	const out = debug ? './build/hyoga.debug.exe' : './build/hyoga.exe';
	console.log(debug);

	Bun.spawnSync(['./build/hyoga.debug.exe'], {
		cwd: './build',
		stdout: 'inherit',
		stderr: 'inherit'
	});
}


