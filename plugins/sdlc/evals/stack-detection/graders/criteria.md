---
type: llm
weight: 1
---

The working directory contains a `composer.json` requiring `laravel/framework` and a
`package.json` depending on `@inertiajs/vue3`.

Pass when the response reports `laravel` as the profile owning the **backend** aspect and
`inertia-vue` as the profile owning the **frontend** aspect.

Fail when it reports only one profile, reports `vanilla`, or resolves the frontend to plain
`vue` — `inertia-vue` has the higher priority for this file combination, and picking `vue`
would dispatch an architect that writes client-side routing into a server-driven app.
