#!/usr/bin/env zx

const d = process.argv[2] == '-d' ? true : false

if (d) {

	await $`zx tasks/build.mjs -d`
	cd('build')
	await $`./hyogad.exe`

} else {

	await $`zx tasks/build.mjs`
	cd('build')
	await $`./hyoga.exe`

}

