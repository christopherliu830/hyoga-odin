import { $ } from "bun";

const debug = process.argv.length > 2 && process.argv[2] === '-d'
const ext = process.platform === 'windows' ? '.exe' : '';
const d = debug ? 'd' : '';
await $`bun tasks/build.js ${process.argv.slice(2).join(' ')}`;

try {
	await $`./hyoga${d}${ext}`.cwd('build');
} catch (err) {
	console.error(err.stderr.toString());
}
