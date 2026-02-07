#!/bin/bash
set -e
cd "$(dirname "$0")"
npm install
npx esbuild editor.js --bundle --format=iife --outfile=../ClaudeChat/Resources/tiptap-bundle.js
echo "Build complete: ../ClaudeChat/Resources/tiptap-bundle.js"
