#!/usr/bin/env node
/**
 * Test script for the elm-safe-virtual-dom static region codemod.
 *
 * Usage: node test-esvd-codemod.js [input-file] [output-file]
 *
 * Defaults:
 *   input:  dist/elm.js.opt (the unpatched compiled Elm)
 *   output: dist/elm.patched.js
 */

import { readFileSync, writeFileSync } from 'fs';
import { patchStaticRegionsESVD } from './static-region-codemod-esvd.js';

const inputFile = process.argv[2] || 'dist/elm.js.opt';
const outputFile = process.argv[3] || 'dist/elm.patched.js';

console.log(`Reading: ${inputFile}`);
const elmCode = readFileSync(inputFile, 'utf-8');

console.log('Applying elm-safe-virtual-dom static region patches...');
const patchedCode = patchStaticRegionsESVD(elmCode);

console.log(`Writing: ${outputFile}`);
writeFileSync(outputFile, patchedCode);

console.log('Done! To test:');
console.log('1. Update dist/static-region-test/index.html to use elm.patched.js');
console.log('2. Serve the dist directory: npx serve dist');
console.log('3. Open http://localhost:3000/static-region-test/');
