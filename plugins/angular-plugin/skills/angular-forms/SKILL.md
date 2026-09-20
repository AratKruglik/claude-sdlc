---
name: angular-forms
description: |
  Angular forms: Reactive Forms (preferred — typed FormGroup/FormControl since Angular 14, FormBuilder, custom + async validators, FormArray, multi-step) and Template-driven (`[(ngModel)]` + FormsModule). Validation strategies, server error mapping, accessibility.

  Use this skill to:
  - Build Reactive Forms with typed FormGroup/FormControl.
  - Use FormBuilder для concise syntax.
  - Implement custom synchronous and async validators.
  - Wire FormArray for dynamic field lists.
  - Map server errors back to form fields.
  - Pick Reactive vs Template-driven (prefer Reactive).

  Do NOT use this skill for:
  - General conventions (see angular-conventions).
  - State management beyond forms (see angular-state-and-rx).
  - Routing (see angular-routing).
  - Testing forms (see angular-testing).
user-invocable: false
paths: ["src/**/*.ts", "src/**/*.html"]
---

# Angular Forms

Two paradigms: **Reactive Forms** (preferred for non-trivial) and **Template-driven** (`[(ngModel)]`-based, simpler for tiny forms). Pick what the project uses; default to Reactive for new code.

## Detection

| Marker (in template imports / `*.module.ts` imports) | Approach |
|---|---|
| `ReactiveFormsModule` | Reactive Forms (preferred) |
| `FormsModule` (without `ReactiveFormsModule`) | Template-driven only |
| Both | Mixed; mirror existing style per area |

## Reactive Forms (preferred)

### Basic typed form (Angular 14+)

```ts
import { Component, inject } from '@angular/core';
import { FormGroup, FormControl, Validators, ReactiveFormsModule } from '@angular/forms';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [ReactiveFormsModule],
  template: `
    <form [formGroup]="loginForm" (ngSubmit)="onSubmit()">
      <label>
        Email
        <input type="email" formControlName="email" [attr.aria-invalid]="emailControl.invalid && emailControl.touched" />
        @if (emailControl.invalid && emailControl.touched) {
          @if (emailControl.errors?.['required']) {
            <p role="alert">Email is required</p>
          } @else if (emailControl.errors?.['email']) {
            <p role="alert">Invalid email format</p>
          }
        }
      </label>

      <label>
        Password
        <input type="password" formControlName="password" />
        @if (passwordControl.invalid && passwordControl.touched) {
          <p role="alert">Password must be at least 8 characters</p>
        }
      </label>

      <button type="submit" [disabled]="loginForm.invalid || submitting()">
        {{ submitting() ? 'Logging in...' : 'Log in' }}
      </button>
    </form>
  `,
})
export class LoginComponent {
  loginForm = new FormGroup({
    email: new FormControl('', {
      validators: [Validators.required, Validators.email],
      nonNullable: true,
    }),
    password: new FormControl('', {
      validators: [Validators.required, Validators.minLength(8)],
      nonNullable: true,
    }),
  });

  submitting = signal(false);

  get emailControl() { return this.loginForm.controls.email; }
  get passwordControl() { return this.loginForm.controls.password; }

  async onSubmit() {
    if (this.loginForm.invalid) return;
    this.submitting.set(true);
    try {
      const { email, password } = this.loginForm.getRawValue();   // typed: { email: string; password: string }
      await this.authService.login({ email, password });
      this.router.navigate(['/dashboard']);
    } catch (err) {
      this.loginForm.setErrors({ serverError: 'Login failed' });
    } finally {
      this.submitting.set(false);
    }
  }
}
```

### Why typed forms (Angular 14+)

```ts
const form = new FormGroup({
  email: new FormControl('', { nonNullable: true }),    // FormControl<string>
  age: new FormControl<number | null>(null),             // FormControl<number | null>
});

form.value;                          // { email?: string; age?: number | null }
form.getRawValue();                  // { email: string; age: number | null }
form.controls.email.value;            // string (because nonNullable: true)
form.controls.age.value;              // number | null
```

`nonNullable: true` makes the control non-nullable — `.value` is `T`, not `T | null`. Use whenever the field has a default value.

`form.value` is partial because disabled controls are excluded; `form.getRawValue()` includes everything.

### FormBuilder (less verbose)

```ts
import { FormBuilder, Validators } from '@angular/forms';

private fb = inject(FormBuilder);

loginForm = this.fb.nonNullable.group({
  email: ['', [Validators.required, Validators.email]],
  password: ['', [Validators.required, Validators.minLength(8)]],
});
```

`fb.nonNullable.group()` makes all fields non-nullable by default. Same typed result as manual `FormGroup` + `nonNullable: true`.

For nullable fields use `fb.group({ ... })` (without `nonNullable`).

### Built-in validators

```ts
Validators.required
Validators.requiredTrue                      // for checkboxes (must be checked)
Validators.email
Validators.min(0)
Validators.max(100)
Validators.minLength(8)
Validators.maxLength(64)
Validators.pattern(/^[A-Za-z]+$/)
Validators.compose([Validators.required, Validators.email])
```

### Custom validators

```ts
import { AbstractControl, ValidationErrors, ValidatorFn } from '@angular/forms';

// Simple sync validator
function noWhitespace(control: AbstractControl): ValidationErrors | null {
  const value = control.value;
  return value && value.trim().length === 0 ? { whitespace: true } : null;
}

// Validator factory (parameterized)
function maxWords(max: number): ValidatorFn {
  return (control: AbstractControl): ValidationErrors | null => {
    const wordCount = (control.value || '').trim().split(/\s+/).filter(Boolean).length;
    return wordCount > max ? { maxWords: { max, actual: wordCount } } : null;
  };
}

// Cross-field validator (on FormGroup)
function passwordsMatch(group: AbstractControl): ValidationErrors | null {
  const a = group.get('password')?.value;
  const b = group.get('confirm')?.value;
  return a === b ? null : { mismatch: true };
}

// Apply
const form = new FormGroup({
  password: new FormControl('', { nonNullable: true }),
  confirm: new FormControl('', { nonNullable: true }),
}, { validators: passwordsMatch });

// Read group-level error in template
@if (form.errors?.['mismatch']) {
  <p role="alert">Passwords do not match</p>
}
```

### Async validators

```ts
import { AsyncValidatorFn, AbstractControl } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { map, catchError, of } from 'rxjs';

function uniqueEmail(http: HttpClient): AsyncValidatorFn {
  return (control: AbstractControl) =>
    http.get<{ available: boolean }>(`/api/check?email=${control.value}`).pipe(
      map((r) => (r.available ? null : { taken: true })),
      catchError(() => of(null))   // network error — don't block
    );
}

// Apply
new FormControl('', {
  validators: [Validators.required, Validators.email],
  asyncValidators: [uniqueEmail(this.http)],
  updateOn: 'blur',                // validate on blur — appropriate for expensive checks
});
```

`updateOn: 'blur'` debounces the validation — only fires when user leaves the field. Critical for async validators to avoid hammering the server.

### FormArray (dynamic field lists)

```ts
import { FormArray, FormBuilder, Validators } from '@angular/forms';

private fb = inject(FormBuilder);

contactsForm = this.fb.nonNullable.group({
  contacts: this.fb.array<FormGroup<{ email: FormControl<string> }>>([
    this.createContact(),
  ]),
});

get contacts() {
  return this.contactsForm.controls.contacts;
}

createContact() {
  return this.fb.nonNullable.group({
    email: ['', [Validators.required, Validators.email]],
  });
}

addContact() {
  this.contacts.push(this.createContact());
}

removeContact(index: number) {
  this.contacts.removeAt(index);
}
```

Template:

```html
<div formArrayName="contacts">
  @for (contact of contacts.controls; track $index; let i = $index) {
    <div [formGroupName]="i">
      <input formControlName="email" />
      <button type="button" (click)="removeContact(i)">Remove</button>
    </div>
  }
</div>
<button type="button" (click)="addContact()">Add contact</button>
```

### Server error mapping

When server returns 422 / 409 with field-specific errors:

```ts
async onSubmit() {
  if (this.loginForm.invalid) return;
  try {
    await this.authService.login(this.loginForm.getRawValue());
  } catch (err) {
    if (err instanceof FieldValidationError) {
      // Map each server error to its form control
      for (const [field, message] of Object.entries(err.fields)) {
        const control = this.loginForm.get(field);
        if (control) control.setErrors({ server: message });
      }
    } else {
      this.loginForm.setErrors({ serverError: 'Generic error' });
    }
  }
}
```

In template:

```html
@if (emailControl.errors?.['server']; as msg) {
  <p role="alert">{{ msg }}</p>
}
@if (loginForm.errors?.['serverError']; as msg) {
  <p role="alert">{{ msg }}</p>
}
```

### Multi-step forms

Two patterns:

**A. Single FormGroup, conditional UI**:

```ts
@Component({...})
export class WizardComponent {
  step = signal(0);
  form = this.fb.nonNullable.group({
    profile: this.fb.nonNullable.group({
      name: ['', Validators.required],
      email: ['', [Validators.required, Validators.email]],
    }),
    address: this.fb.nonNullable.group({
      street: ['', Validators.required],
      city: ['', Validators.required],
    }),
  });

  next() {
    const currentStep = this.step() === 0 ? this.form.controls.profile : this.form.controls.address;
    currentStep.markAllAsTouched();
    if (currentStep.valid) this.step.update((s) => s + 1);
  }
}
```

**B. Separate forms per step + parent state holder** (signals or service): each step has its own form, parent merges.

Pick A for short wizards (≤3 steps), B for longer or when steps reorder dynamically.

## Template-driven Forms (legacy / simple cases)

```ts
import { FormsModule } from '@angular/forms';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [FormsModule],
  template: `
    <form #f="ngForm" (ngSubmit)="onSubmit(f)">
      <input name="email" [(ngModel)]="email" required type="email" #emailField="ngModel" />
      @if (emailField.invalid && emailField.touched) {
        <p role="alert">Invalid email</p>
      }

      <input name="password" [(ngModel)]="password" required minlength="8" />

      <button type="submit" [disabled]="f.invalid">Submit</button>
    </form>
  `,
})
export class LoginComponent {
  email = '';
  password = '';

  onSubmit(form: NgForm) {
    if (form.invalid) return;
    this.authService.login({ email: this.email, password: this.password });
  }
}
```

Easier for tiny forms (1-3 fields). Harder to test, harder to type, harder to handle async validation. Don't use for non-trivial forms.

Mixing Reactive + Template-driven in the SAME form is unsupported — pick one per form.

## Validation timing (`updateOn`)

```ts
new FormControl('', {
  validators: [Validators.required],
  updateOn: 'change' | 'blur' | 'submit',
});

// Or per-FormGroup:
new FormGroup({...}, { updateOn: 'blur' });
```

| Mode | When |
|---|---|
| `'change'` (default) | Every keystroke |
| `'blur'` | When field loses focus |
| `'submit'` | Only on form submission |

Use `'blur'` for async validators (avoid hammering server). Use `'submit'` rarely (delays user feedback).

## Accessibility checklist

- Every input has `<label>` (visible or via `aria-label`).
- `aria-invalid` on invalid + touched fields.
- `role="alert"` or `aria-live="polite"` on error messages.
- Submit button shows loading state (disabled + visual indicator).
- Focus moves to first error after failed submit (use `markAllAsTouched()` + scroll to first invalid control).

## Anti-patterns

- ❌ Untyped `FormControl` / `FormGroup` (use generics or `nonNullable: true`).
- ❌ Mixing Reactive + Template-driven in same form.
- ❌ Validating on every keystroke for expensive async checks (use `updateOn: 'blur'`).
- ❌ Skipping client validation thinking server suffices (UX suffers).
- ❌ Skipping server validation thinking client suffices (security suffers).
- ❌ Forgetting to disable submit button while submitting — double-submits.
- ❌ Not handling the `submitting` state (no spinner / disabled feedback).
- ❌ `(ngSubmit)="onSubmit()"` without checking `form.invalid` first.
- ❌ Using `(submit)` on a `<form>` instead of `(ngSubmit)` — bypasses Angular's form lifecycle.
- ❌ Mutating `form.value` directly — `value` is a getter, not the source of truth; use `form.setValue()` / `patchValue()`.
- ❌ Resetting form after server error — user re-types everything.
