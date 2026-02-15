#!/bin/bash
set -e
cd "$(dirname "$0")"
npm install
npx esbuild editor.js --bundle --format=iife --outfile=../Shared/Resources/tiptap-bundle.js
echo "Build complete: ../Shared/Resources/tiptap-bundle.js"
