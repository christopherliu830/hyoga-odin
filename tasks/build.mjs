#!/usr/bin/env zx

const d = process.argv[3] === '-d' ? true : false

await $`make ${d ? 'debug' : ''}`;
