#!/usr/bin/env zx

const d = process.argv[2] == '-d' ? true : false

await $`make ${d ? 'debug' : ''}`;
