#!/usr/bin/env bash
# Minimal Laravel + Inertia/Vue fixture: enough for stack.md detection to fire, nothing more.
set -euo pipefail
printf '{"require":{"laravel/framework":"^11.0"}}\n' > composer.json
printf '{"dependencies":{"@inertiajs/vue3":"^1.0.0","vue":"^3.4.0"}}\n' > package.json
mkdir -p app/Models resources/js/Pages
