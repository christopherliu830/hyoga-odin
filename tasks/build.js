import { $ } from "bun";

const d = process.argv[2] === '-d';

try {
  const output = await $`make ${d ? 'debug' : ''}`.text();
  console.log(output);
}
catch (err) {
  console.log(err.stdout.toString());
  console.log(err.stderr.toString());
}


