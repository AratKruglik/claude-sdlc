---
name: vue-conventions
description: |
  Vue 3 SFC structure, Composition API + <script setup>, file naming, project layout, props/emits/slots typing, defineModel, composables, lifecycle, watchers, UI library detection. Vue 2 fallback notes.

  Use this skill to:
  - Structure a new SFC with `<script setup>`, template, scoped styles.
  - Type props/emits/slots correctly via macros.
  - Pick `ref` vs `reactive` (prefer `ref`).
  - Build composables that compose cleanly.
  - Apply lifecycle hooks correctly.
  - Detect UI library (Vuetify/Quasar/PrimeVue/Naive UI/Element Plus/shadcn-vue) and mirror its patterns.

  Do NOT use this skill for:
  - State management lib choice (see vue-state-management).
  - Routing (see vue-routing).
  - Forms (see vue-forms).
  - Testing (see vue-testing).
user-invocable: false
paths: ["src/**/*.vue", "src/**/*.ts", "src/**/*.js"]
---

# Vue 3 Conventions

This skill consolidates idioms for Vue 3 SPA projects with `<script setup>` and the Composition API. Apply alongside `js-foundation:typescript-patterns` (general TS strictness).

Vue 2 fallback notes are at the end — applied only when project is on `"vue": "^2"`.

## Project layout

```
src/
├── main.ts                          # createApp + mount
├── App.vue                          # root SFC
├── router/
│   ├── index.ts                     # createRouter + routes
│   └── guards.ts                    # navigation guards
├── views/                           # route components (page-level)
│   ├── HomeView.vue
│   └── UsersView.vue
├── components/
│   ├── ui/                          # primitives (Button, Input, Modal)
│   └── features/                    # feature-specific
│       └── users/
│           ├── UserCard.vue
│           └── UserFilter.vue
├── composables/                     # use*.ts
│   ├── useDebounce.ts
│   └── useUsers.ts
├── stores/                          # Pinia stores
│   └── users.ts
├── lib/                             # framework-agnostic utilities
│   └── http.ts
├── types/
│   └── user.ts
└── assets/
    └── styles/
        └── global.css
```

Mirror what exists. Don't restructure as part of feature work.

## File naming

| What | Convention |
|---|---|
| SFC file | `PascalCase.vue` (`UserCard.vue`) |
| View (route) | `*View.vue` suffix common (`UsersView.vue`) — match project |
| Composable | `useCamelCase.ts` (`useDebounce.ts`) |
| Pinia store | `kebab-case.ts` or `camelCase.ts` (`users.ts`) |
| Test file | `*.spec.ts` colocated, OR mirror in `tests/` |

Component name in `<template>`: PascalCase (`<UserCard />`) OR kebab-case (`<user-card />`) — both work, Vue handles conversion.

## SFC structure

```vue
<script setup lang="ts">
// 1. Imports
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import type { User } from '@/types/user';

// 2. Props/emits/slots
interface Props {
  userId: string;
  initialName?: string;
}
const props = withDefaults(defineProps<Props>(), { initialName: '' });
const emit = defineEmits<{
  save: [name: string];
  cancel: [];
}>();

// 3. Reactive state
const name = ref(props.initialName);
const error = ref<string | null>(null);

// 4. Composables
const router = useRouter();

// 5. Computed
const isValid = computed(() => name.value.length >= 2);

// 6. Methods
function onSave() {
  if (!isValid.value) {
    error.value = 'Name must be at least 2 characters';
    return;
  }
  emit('save', name.value);
}

// 7. Lifecycle
onMounted(() => {
  console.log('UserForm mounted for', props.userId);
});
</script>

<template>
  <form @submit.prevent="onSave">
    <input v-model="name" placeholder="Name" />
    <p v-if="error" role="alert">{{ error }}</p>
    <div class="actions">
      <button :disabled="!isValid">Save</button>
      <button type="button" @click="emit('cancel')">Cancel</button>
    </div>
  </form>
</template>

<style scoped>
form {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.actions {
  display: flex;
  gap: 8px;
}
</style>
```

Section order is convention; pick per project. `<script setup>` is the modern preferred form.

### When NOT to use `<script setup>`

- Components that need `name` for recursive references (`<script>` with `name:` option). Workaround: separate `<script>` block with just `name`.
- Components with complex render functions instead of templates.

These are rare; most Vue 3 components use `<script setup>`.

## Reactivity primitives

### `ref` (preferred)

```ts
import { ref } from 'vue';

const count = ref(0);
const user = ref({ name: '', email: '' });
const items = ref<string[]>([]);

count.value++;                         // .value in JS
user.value.name = 'Alice';
items.value.push('hi');
```

In `<template>`, refs auto-unwrap — no `.value` needed:

```vue
<template>
  <p>{{ count }}</p>           <!-- not {{ count.value }} -->
  <p>{{ user.name }}</p>
</template>
```

### `reactive` (sometimes)

```ts
import { reactive } from 'vue';

const state = reactive({ count: 0, items: [] });
state.count++;                         // no .value
state.items.push('hi');
```

**Footgun**: destructuring loses reactivity:

```ts
const state = reactive({ count: 0 });
const { count } = state;               // count is a snapshot, not reactive
count++;                                // doesn't update state.count
```

Workaround: `toRefs()`:

```ts
const { count } = toRefs(state);       // count is now Ref<number>
count.value++;                          // updates state.count
```

**Recommendation**: use `ref` for everything. Works for primitives AND objects, no destructure footgun. Reach for `reactive` only when team convention says so.

### `computed`

```ts
const double = computed(() => count.value * 2);

// Writable computed
const fullName = computed({
  get: () => `${first.value} ${last.value}`,
  set: (val) => {
    [first.value, last.value] = val.split(' ');
  },
});
```

### `watch` and `watchEffect`

```ts
// watch — explicit deps, gets old value
watch(count, (newVal, oldVal) => {
  console.log(`${oldVal} → ${newVal}`);
});

// Watch multiple sources
watch([count, name], ([newCount, newName], [oldCount, oldName]) => {});

// Deep watch on object refs
watch(user, (newUser) => {}, { deep: true });

// Immediate (run once on mount)
watch(count, () => {}, { immediate: true });

// watchEffect — auto-tracks deps, no oldVal
watchEffect(() => {
  console.log(`count: ${count.value}`);  // runs whenever count changes
});

// Cleanup function (e.g., unsubscribe)
watchEffect((onCleanup) => {
  const id = setInterval(() => {}, 1000);
  onCleanup(() => clearInterval(id));
});
```

`watchEffect` runs once immediately, then on each dep change. `watch` runs only on dep change unless `immediate: true`.

## Props typing

```ts
// Basic
interface Props {
  title: string;
  count?: number;
}
const props = defineProps<Props>();

// With defaults
const props = withDefaults(defineProps<Props>(), {
  count: 0,
});

// Default for objects/arrays — function form
interface ListProps {
  items: string[];
  config?: { showHeader?: boolean };
}
const props = withDefaults(defineProps<ListProps>(), {
  items: () => [],
  config: () => ({ showHeader: true }),
});
```

Mark required vs optional via `?`. Don't validate at runtime when TS handles it at compile time.

## Emits typing

```ts
// Tuple syntax — preferred
const emit = defineEmits<{
  change: [value: string];
  submit: [data: FormData];
  delete: [id: string, force?: boolean];
}>();

emit('change', 'new value');
emit('submit', formData);
emit('delete', 'id-123', true);
```

Older Vue 3 syntax (function-based) still works but tuple syntax is cleaner.

## Slots typing

```ts
defineSlots<{
  default(props: { user: User }): any;
  header?(props: { count: number }): any;
}>();
```

```vue
<template>
  <slot name="header" :count="items.length" />
  <slot v-for="item in items" :key="item.id" :user="item" />
</template>
```

Parent uses scoped slots:

```vue
<UserList :items="users">
  <template #header="{ count }">
    <h2>{{ count }} users</h2>
  </template>
  <template #default="{ user }">
    <UserCard :user="user" />
  </template>
</UserList>
```

## `defineModel()` (Vue 3.4+)

Two-way binding without manual props+emits:

```vue
<!-- CustomInput.vue -->
<script setup lang="ts">
const value = defineModel<string>();
const required = defineModel<boolean>('required', { default: false });
</script>

<template>
  <input v-model="value" :required="required" />
</template>
```

Parent:

```vue
<CustomInput v-model="form.email" v-model:required="form.emailRequired" />
```

For Vue 3.3 and earlier, use the manual props+emits pattern.

## Composables

```ts
// src/composables/useDebounce.ts
import { ref, watch, onBeforeUnmount } from 'vue';
import type { Ref } from 'vue';

export function useDebounce<T>(value: Ref<T>, delay = 300): Ref<T> {
  const debounced = ref(value.value) as Ref<T>;
  let timer: ReturnType<typeof setTimeout> | undefined;

  watch(value, (newVal) => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => { debounced.value = newVal; }, delay);
  });

  onBeforeUnmount(() => { if (timer) clearTimeout(timer); });

  return debounced;
}
```

Conventions:
- Name `useFooBar()`.
- Take refs as input, return refs as output.
- Cleanup side effects in `onBeforeUnmount`.
- Pure composables (no DOM access) → easy to test.

VueUse (`@vueuse/core`) provides 200+ pre-built composables — check before writing your own.

## Lifecycle hooks

```ts
import { onMounted, onBeforeMount, onUpdated, onBeforeUnmount, onUnmounted, onErrorCaptured, onActivated, onDeactivated } from 'vue';

onMounted(() => { /* DOM ready */ });
onBeforeUnmount(() => { /* cleanup */ });
onErrorCaptured((err, instance, info) => { /* error boundary */ return false; });
```

`onActivated` / `onDeactivated` fire when wrapped in `<KeepAlive>`.

In `<script setup>`, hooks register implicitly via call site. No need to return them.

## UI library detection

The agent should detect what's installed and mirror its patterns. Common Vue UI libraries:

| Library | Marker (in deps) | Style |
|---|---|---|
| Vuetify | `vuetify` | Material Design components, opinionated grid |
| Quasar | `quasar`, `@quasar/cli` | Cross-platform (web/SSR/SPA/PWA/desktop), large |
| PrimeVue | `primevue` | Comprehensive, themeable |
| Naive UI | `naive-ui` | Modern TS-first, no heavy theme system |
| Element Plus | `element-plus` | Popular in Asia, mature |
| shadcn-vue (radix-vue) | `radix-vue` | Headless primitives, copy-paste components |
| HeadlessUI Vue | `@headlessui/vue` | Headless from Tailwind Labs |

**Rule**: never introduce a new UI lib without BA approval. Detect what's installed; mirror its patterns. If multiple UI libs present (gradual migration), match the area you're touching.

## Anti-patterns

- ❌ `<script>` without `setup` for new Vue 3 components — boilerplate without benefit.
- ❌ Mixing Options API and Composition API in same component.
- ❌ Destructuring `reactive()` objects without `toRefs()`.
- ❌ Mutating props directly (`props.user.name = 'X'`) — use defineModel or emit.
- ❌ Logic in template expressions (`{{ items.filter(...).map(...).join(', ') }}`) — extract to computed.
- ❌ `v-html` without sanitization.
- ❌ Forgetting `:key` on `v-for` lists, or using array index as key for reorderable lists.
- ❌ `process.env.X` for build-time secrets — use `import.meta.env.VITE_*` (PUBLIC by definition).
- ❌ Long composables that "do everything" — split by concern.

## Vue 2 fallback (legacy)

When `"vue": "^2"` detected, apply minimum-effort patterns:

```vue
<script>
export default {
  name: 'UserForm',
  props: {
    userId: { type: String, required: true },
    initialName: { type: String, default: '' },
  },
  data() {
    return {
      name: this.initialName,
    };
  },
  computed: {
    isValid() {
      return this.name.length >= 2;
    },
  },
  methods: {
    onSave() {
      if (!this.isValid) return;
      this.$emit('save', this.name);
    },
  },
  mounted() {
    console.log('mounted');
  },
};
</script>

<template>
  <form @submit.prevent="onSave">
    <input v-model="name" placeholder="Name" />
    <button :disabled="!isValid">Save</button>
  </form>
</template>
```

Differences from Vue 3:
- No `<script setup>`, no `defineProps`/`defineEmits` macros.
- `data()` returns reactive state; access via `this.x`.
- No Composition API by default (Vue 2.7 has it as opt-in via `@vue/composition-api` plugin).
- State management: Vuex 3.x (`store.commit`, `store.dispatch`, `mapState`/`mapActions` helpers).
- Router: `vue-router` v3.x.
- Reactivity: `Vue.set()` / `this.$set()` for adding new keys to reactive objects (Vue 3 fixed this).

Migrate to Vue 3 only when BA spec explicitly asks. For new features in Vue 2 codebase, follow existing Options API patterns.
