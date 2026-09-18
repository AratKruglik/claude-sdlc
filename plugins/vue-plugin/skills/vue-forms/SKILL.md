---
name: vue-forms
description: |
  Vue 3 form patterns: native v-model, vee-validate + zod (most common), VueUse helpers, defineModel for custom inputs, controlled vs uncontrolled, field arrays, multi-step wizards.

  Use this skill to:
  - Wire vee-validate with a validation schema (zod / yup).
  - Build custom form components with defineModel (Vue 3.4+).
  - Implement multi-step forms.
  - Handle async validation.
  - Integrate forms with TanStack Query mutations or Pinia actions.

  Do NOT use this skill for:
  - General SFC conventions (see vue-conventions).
  - State management (see vue-state-management).
  - Routing (see vue-routing).
  - Testing forms (see vue-testing).
user-invocable: false
paths: ["src/**/*.vue"]
---

# Vue 3 Form Patterns

`v-model` is the foundation. Add vee-validate when validation grows beyond simple HTML5 attributes.

## Detection

| Marker (in deps) | Library |
|---|---|
| `vee-validate` (+ `@vee-validate/zod` or `@vee-validate/yup`) | vee-validate (recommended) |
| `@vueuse/core` | VueUse helpers (lighter alternative) |
| (none) | Native v-model + HTML5 validation |
| `zod` / `yup` / `valibot` | Pair with vee-validate via resolver |

## Native v-model (sufficient for simple forms)

```vue
<script setup lang="ts">
import { ref } from 'vue';

const email = ref('');
const password = ref('');
const remember = ref(false);

function onSubmit() {
  // ...
}
</script>

<template>
  <form @submit.prevent="onSubmit">
    <input v-model="email" type="email" required placeholder="Email" />
    <input v-model="password" type="password" required minlength="8" placeholder="Password" />
    <label>
      <input v-model="remember" type="checkbox" /> Remember me
    </label>
    <button>Log in</button>
  </form>
</template>
```

Built-in HTML5 validation (`required`, `type="email"`, `pattern`, `minlength`, `maxlength`) is free. Use it for forms ≤3 fields with simple rules.

### v-model modifiers

```vue
<input v-model.lazy="text" />          <!-- updates on change, not input -->
<input v-model.number="age" />          <!-- coerces to number -->
<input v-model.trim="username" />       <!-- trims whitespace -->
```

### v-model on custom components

In Vue 3.4+, use `defineModel`:

```vue
<!-- CustomInput.vue -->
<script setup lang="ts">
const value = defineModel<string>();
const error = defineModel<string | null>('error', { default: null });
</script>

<template>
  <div>
    <input v-model="value" />
    <p v-if="error" class="error">{{ error }}</p>
  </div>
</template>
```

```vue
<!-- Parent -->
<CustomInput v-model="form.email" v-model:error="emailError" />
```

For Vue 3.0–3.3, use manual props + emits:

```vue
<script setup lang="ts">
const props = defineProps<{ modelValue: string }>();
const emit = defineEmits<{ 'update:modelValue': [value: string] }>();

function onInput(e: Event) {
  emit('update:modelValue', (e.target as HTMLInputElement).value);
}
</script>

<template>
  <input :value="props.modelValue" @input="onInput" />
</template>
```

## vee-validate (recommended for non-trivial forms)

```bash
pnpm add vee-validate @vee-validate/zod zod
```

### Basic form

```vue
<script setup lang="ts">
import { useForm } from 'vee-validate';
import { toTypedSchema } from '@vee-validate/zod';
import { z } from 'zod';

const schema = toTypedSchema(z.object({
  email: z.string().email('Invalid email'),
  password: z.string().min(8, 'At least 8 characters'),
  remember: z.boolean().default(false),
}));

const { defineField, handleSubmit, errors, isSubmitting } = useForm({
  validationSchema: schema,
  initialValues: { email: '', password: '', remember: false },
});

const [email, emailAttrs] = defineField('email');
const [password, passwordAttrs] = defineField('password');
const [remember, rememberAttrs] = defineField('remember');

const onSubmit = handleSubmit(async (values) => {
  await login(values);
});
</script>

<template>
  <form @submit="onSubmit">
    <label>
      Email
      <input v-model="email" v-bind="emailAttrs" type="email" />
      <p v-if="errors.email" role="alert">{{ errors.email }}</p>
    </label>

    <label>
      Password
      <input v-model="password" v-bind="passwordAttrs" type="password" />
      <p v-if="errors.password" role="alert">{{ errors.password }}</p>
    </label>

    <label>
      <input v-model="remember" v-bind="rememberAttrs" type="checkbox" />
      Remember me
    </label>

    <button :disabled="isSubmitting">
      {{ isSubmitting ? 'Logging in...' : 'Log in' }}
    </button>
  </form>
</template>
```

### Field components alternative

```vue
<script setup lang="ts">
import { Field, ErrorMessage, useForm } from 'vee-validate';
import { toTypedSchema } from '@vee-validate/zod';
import { z } from 'zod';

useForm({
  validationSchema: toTypedSchema(z.object({
    email: z.string().email(),
    password: z.string().min(8),
  })),
});
</script>

<template>
  <form>
    <Field name="email" type="email" />
    <ErrorMessage name="email" as="p" role="alert" />

    <Field name="password" type="password" />
    <ErrorMessage name="password" />
  </form>
</template>
```

`<Field>` and `<ErrorMessage>` are convenient but less flexible. Pick one approach per project.

### Field arrays

```vue
<script setup lang="ts">
import { useForm, useFieldArray } from 'vee-validate';

const { handleSubmit } = useForm({
  initialValues: { contacts: [{ email: '' }] },
});
const { fields, push, remove } = useFieldArray<{ email: string }>('contacts');
</script>

<template>
  <form @submit="handleSubmit(onSubmit)">
    <div v-for="(field, index) in fields" :key="field.key">
      <Field :name="`contacts[${index}].email`" type="email" />
      <ErrorMessage :name="`contacts[${index}].email`" />
      <button type="button" @click="remove(index)">Remove</button>
    </div>
    <button type="button" @click="push({ email: '' })">Add</button>
    <button type="submit">Save</button>
  </form>
</template>
```

`field.key` is a stable key from vee-validate — DON'T use index.

### Async validation

```ts
const schema = z.object({
  username: z.string().min(3).refine(
    async (u) => {
      const res = await fetch(`/api/users/check?u=${u}`);
      return (await res.json()).available;
    },
    'Username taken'
  ),
});

const { defineField } = useForm({
  validationSchema: toTypedSchema(schema),
  validateOnInput: false,
  validateOnBlur: true,                    // validate on blur — appropriate for expensive checks
});
```

### Server error handling

```ts
const { handleSubmit, setErrors, setFieldError } = useForm({...});

const onSubmit = handleSubmit(async (values) => {
  try {
    await createUser(values);
  } catch (err) {
    if (err instanceof FetchError && err.status === 409) {
      setFieldError('email', 'Email already in use');
    } else {
      setErrors({ form: 'Something went wrong' });
    }
  }
});
```

### Multi-step forms

```vue
<script setup lang="ts">
import { useForm } from 'vee-validate';
import { ref } from 'vue';

const step = ref(0);
const { defineField, validate, values, handleSubmit } = useForm({
  validationSchema: schema,
  initialValues: { step1: {}, step2: {} },
});

async function next() {
  const result = await validate();        // validates whole form
  if (result.valid) step.value++;
  // OR validate just current step's fields:
  // const r = await validate({ mode: 'silent' });
  // if (r.valid) step.value++;
}

const onSubmit = handleSubmit((vals) => save(vals));
</script>

<template>
  <form @submit="onSubmit">
    <Step1 v-if="step === 0" />
    <Step2 v-if="step === 1" />
    <button v-if="step < lastStep" type="button" @click="next">Next</button>
    <button v-else type="submit">Submit</button>
  </form>
</template>
```

## VueUse useForm (lighter alternative)

`@vueuse/core` doesn't have a direct `useForm` equivalent. For simple forms, native v-model + manual validation is enough. For complex forms, use vee-validate.

VueUse useful form-related composables:

- `useDebouncedRef` — debounce input value.
- `useStorage` — persist form state to localStorage (NEVER for sensitive data).
- `onClickOutside` — close dropdowns / pickers.
- `useFocus` — focus management for accessibility.

## Integration with TanStack Query / Pinia

```vue
<script setup lang="ts">
import { useForm } from 'vee-validate';
import { toTypedSchema } from '@vee-validate/zod';
import { z } from 'zod';
import { useCreateUser } from '@/composables/useUsers';
import { useRouter } from 'vue-router';

const router = useRouter();
const { mutate: createUser, isPending } = useCreateUser();

const schema = toTypedSchema(z.object({
  email: z.string().email(),
  name: z.string().min(1),
}));

const { handleSubmit, setFieldError, defineField } = useForm({ validationSchema: schema });
const [email, emailAttrs] = defineField('email');
const [name, nameAttrs] = defineField('name');

const onSubmit = handleSubmit(async (values) => {
  createUser(values, {
    onSuccess: () => router.push('/users'),
    onError: (err) => {
      if (err.status === 409) setFieldError('email', 'Email already in use');
    },
  });
});
</script>
```

## Accessibility checklist

- Every input has a `<label>` (visible or via `aria-label`).
- `aria-invalid` on inputs with errors.
- `role="alert"` on error messages (or `aria-live="polite"`).
- Focus moves to first error on submit failure.
- Submit button shows loading state.

## Anti-patterns

- ❌ Mutating props directly to update form values (use defineModel or emit).
- ❌ Skipping client-side validation thinking server suffices — UX suffers.
- ❌ Skipping server-side validation thinking client suffices — security suffers.
- ❌ Validating on every keystroke for expensive checks (DB lookup) — debounce or `validateOnBlur`.
- ❌ Forgetting to disable submit button while submitting — leads to double-submits.
- ❌ Persisting form state to localStorage when it contains PII — privacy concern.
- ❌ Resetting form to empty after server error — user re-types from scratch.
- ❌ Both `vee-validate` and `formkit` in same project without clear boundary.
