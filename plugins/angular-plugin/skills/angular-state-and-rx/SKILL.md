---
name: angular-state-and-rx
description: |
  State management for Angular 18-21: signals (signal/computed/effect), services-as-state, NgRx Store + Effects + Selectors, NgRx Component Store, NgRx Signals (newer signal-based store). RxJS essentials — operators, async pipe, takeUntilDestroyed, signal/observable interop.

  Use this skill to:
  - Pick the right state tool (signals / services / NgRx variant / vue-query equivalent).
  - Use signals correctly (signal/computed/effect — when each).
  - Build a Pinia-style service-as-state singleton.
  - Set up NgRx Store + Effects + Selectors.
  - Use RxJS without leaking subscriptions (async pipe, takeUntilDestroyed, Subject patterns).
  - Bridge signals ↔ observables via toSignal / toObservable.

  Do NOT use this skill for:
  - General Angular conventions (see angular-conventions).
  - Routing state (see angular-routing).
  - Form state (see angular-forms).
  - Testing state (see angular-testing).
user-invocable: false
paths: ["src/**/*.ts"]
---

# Angular State + RxJS Patterns

Modern Angular era (17+) introduces signals as a first-class reactivity primitive alongside RxJS. Both have a place — signals для component state, RxJS для async streams. Plus optional NgRx variants for complex apps.

## Decision tree

| Need | Tool |
|---|---|
| Local component state (count, isOpen) | `signal()` |
| Computed from other state | `computed()` |
| Side effects on signal change | `effect()` (sparingly) |
| Cross-component shared state | `@Injectable({ providedIn: 'root' })` service з signals |
| Server data with caching | TanStack Query Angular OR custom RxJS service з shareReplay |
| Complex domain state з time-travel debugging | NgRx Store + Effects + Selectors |
| Lightweight per-component reactive store | NgRx Component Store |
| Signal-based store API | `@ngrx/signals` (Angular 17+) |
| URL state | `ActivatedRoute` snapshot / queryParams |

Detect what's installed; mirror project's choice; never introduce a new state lib without BA approval.

## Signals (Angular 17+)

```ts
import { signal, computed, effect } from '@angular/core';

count = signal(0);
double = computed(() => this.count() * 2);

constructor() {
  effect(() => {
    console.log('count is now', this.count());
  });
}

increment() {
  this.count.update((c) => c + 1);          // functional update — best for derivations
}

set(value: number) {
  this.count.set(value);                     // direct set
}

reset() {
  this.count.set(0);
}
```

### `signal(initial)` vs `computed(fn)` vs `effect(fn)`

- `signal()` — writable, returns a function. Read with `signal()`, write with `signal.set()` or `signal.update()`.
- `computed()` — read-only, derived from other signals. Auto-tracks dependencies (calls inside the function are observed). Memoized — recomputes only when deps change.
- `effect()` — runs after component init and re-runs when read signals change. Use SPARINGLY — most reactivity flows through templates (auto-track via `{{ signal() }}`).

### When NOT to use `effect()`

- ❌ For derived state — use `computed()`.
- ❌ For state synchronization — usually a sign of bad architecture.
- ❌ For form-control updates — Angular Forms have their own reactivity.
- ✅ For non-Angular DOM access (e.g., third-party charting library that needs imperative updates).
- ✅ For logging / analytics on state changes.

### Signal inputs/outputs (Angular 17.1+)

```ts
import { input, output, computed } from '@angular/core';

@Component({ ... })
export class UserCardComponent {
  user = input.required<User>();              // required input — InputSignal<User>
  showActions = input(false);                  // optional with default — InputSignal<boolean>
  delete = output<string>();                   // OutputEmitterRef<string>

  isAdmin = computed(() => this.user().role === 'admin');

  onDelete() {
    this.delete.emit(this.user().id);
  }
}
```

For new components in Angular 17.1+, prefer `input()` / `output()` over `@Input()` / `@Output()` decorators. Mirror existing project style if all components still use decorators.

## Services as state (singleton pattern)

```ts
// users.service.ts
import { Injectable, signal, computed, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';
import type { User } from './user.model';

@Injectable({ providedIn: 'root' })
export class UsersService {
  private http = inject(HttpClient);

  // Private writable signals
  private _users = signal<User[]>([]);
  private _loading = signal(false);
  private _error = signal<string | null>(null);

  // Public readonly signals
  users = this._users.asReadonly();
  loading = this._loading.asReadonly();
  error = this._error.asReadonly();

  // Public computed
  count = computed(() => this._users().length);
  hasError = computed(() => this._error() !== null);

  async loadUsers() {
    this._loading.set(true);
    this._error.set(null);
    try {
      const users = await firstValueFrom(this.http.get<User[]>('/api/users'));
      this._users.set(users);
    } catch (err) {
      this._error.set(err instanceof Error ? err.message : 'Failed to load');
    } finally {
      this._loading.set(false);
    }
  }

  addUser(user: User) {
    this._users.update((users) => [...users, user]);
  }

  removeUser(id: string) {
    this._users.update((users) => users.filter((u) => u.id !== id));
  }
}
```

`asReadonly()` exposes a read-only view — consumers can't `.set()` on it. Internal mutations stay encapsulated.

Component consumers:

```ts
@Component({
  template: `
    @if (usersService.loading()) {
      <p>Loading...</p>
    } @else {
      <p>{{ usersService.count() }} users</p>
      <ul>
        @for (user of usersService.users(); track user.id) {
          <li>{{ user.name }}</li>
        }
      </ul>
    }
  `
})
export class UsersListComponent {
  usersService = inject(UsersService);

  ngOnInit() {
    this.usersService.loadUsers();
  }
}
```

## RxJS essentials

Angular still uses RxJS heavily — HttpClient returns Observables, ActivatedRoute params/queryParams are Observables, NgRx Effects are Observables.

### Common operators

```ts
import { map, filter, switchMap, mergeMap, exhaustMap, debounceTime, distinctUntilChanged, tap, catchError, finalize, takeUntil, take, shareReplay } from 'rxjs';

this.search$.pipe(
  debounceTime(300),                     // wait 300ms after last input
  distinctUntilChanged(),                // skip duplicates
  switchMap((query) => this.searchService.search(query)),  // cancel prior on new input
  catchError((err) => of([])),           // error fallback
);
```

| Operator | Use |
|---|---|
| `map(fn)` | Transform values |
| `filter(fn)` | Keep matching values |
| `tap(fn)` | Side effect (logging) without changing stream |
| `switchMap(fn)` | Cancel previous inner observable on new outer (search, autocomplete) |
| `mergeMap(fn)` | Run all inner observables in parallel |
| `concatMap(fn)` | Sequential — wait for prior to complete |
| `exhaustMap(fn)` | Ignore new outer while inner pending (login, save buttons) |
| `debounceTime(ms)` | Wait quiet period before emitting |
| `distinctUntilChanged()` | Skip consecutive duplicates |
| `take(n)` | Take first n then complete |
| `takeUntil(notifier$)` | Stop when notifier emits (manual cleanup pattern) |
| `shareReplay({ bufferSize: 1, refCount: true })` | Cache last value for late subscribers (HTTP caching pattern) |
| `catchError(fn)` | Recover from errors |
| `finalize(fn)` | Cleanup on complete or error |

### `async` pipe in templates

```html
@if (users$ | async; as users) {
  @for (user of users; track user.id) {
    <p>{{ user.name }}</p>
  }
} @else {
  <p>Loading...</p>
}
```

`async` pipe handles subscribe + unsubscribe automatically. Always prefer over manual `subscribe()` in component classes.

### `takeUntilDestroyed()` (Angular 16+)

For when you need `subscribe()` directly:

```ts
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute } from '@angular/router';
import { inject, Component, OnInit } from '@angular/core';

@Component({ ... })
export class UserDetailComponent implements OnInit {
  private route = inject(ActivatedRoute);

  ngOnInit() {
    this.route.params
      .pipe(takeUntilDestroyed())          // automatic cleanup tied to component
      .subscribe((params) => {
        // ...
      });
  }
}
```

`takeUntilDestroyed()` MUST be called in injection context — class field initializer or constructor. If called inside `ngOnInit()`, you must pass an explicit `DestroyRef`:

```ts
private destroyRef = inject(DestroyRef);
ngOnInit() {
  this.someStream$.pipe(takeUntilDestroyed(this.destroyRef)).subscribe(...);
}
```

Replaces the older manual pattern:

```ts
// ❌ Pre-16 — verbose, easy to forget
private destroy$ = new Subject<void>();
ngOnInit() {
  this.something$.pipe(takeUntil(this.destroy$)).subscribe(...);
}
ngOnDestroy() {
  this.destroy$.next();
  this.destroy$.complete();
}
```

### `firstValueFrom` / `lastValueFrom`

For one-shot observables (HTTP), convert to Promise:

```ts
import { firstValueFrom } from 'rxjs';

async loadUser(id: string) {
  return await firstValueFrom(this.http.get<User>(`/api/users/${id}`));
}
```

Replaces deprecated `.toPromise()`.

## Bridging signals ↔ RxJS

```ts
import { toSignal, toObservable } from '@angular/core/rxjs-interop';

// Observable → Signal
@Injectable({ providedIn: 'root' })
export class UsersService {
  private http = inject(HttpClient);
  users = toSignal(this.http.get<User[]>('/api/users'), { initialValue: [] });
}

// Signal → Observable
const filter = signal('');
const filter$ = toObservable(filter);   // emits whenever filter() changes

filter$.pipe(
  debounceTime(300),
  switchMap((q) => this.search(q)),
).subscribe(...);
```

`toSignal` requires either `initialValue` OR `requireSync: true` (which throws if observable doesn't emit synchronously). Most HTTP cases need `initialValue`.

## NgRx Store (when `@ngrx/store` detected)

```bash
pnpm add @ngrx/store @ngrx/effects @ngrx/store-devtools @ngrx/entity
```

### Setup (standalone)

```ts
// main.ts
bootstrapApplication(AppComponent, {
  providers: [
    provideStore({ users: usersReducer }),
    provideEffects([UsersEffects]),
    provideStoreDevtools({ maxAge: 25, logOnly: !isDevMode() }),
  ],
});
```

### Actions

```ts
// users.actions.ts
import { createAction, createActionGroup, props, emptyProps } from '@ngrx/store';

export const UsersActions = createActionGroup({
  source: 'Users',
  events: {
    'Load Users': emptyProps(),
    'Load Users Success': props<{ users: User[] }>(),
    'Load Users Failure': props<{ error: string }>(),
    'Delete User': props<{ id: string }>(),
  },
});

// Dispatch
this.store.dispatch(UsersActions.loadUsers());
this.store.dispatch(UsersActions.deleteUser({ id: '123' }));
```

### Reducer

```ts
// users.reducer.ts
import { createReducer, on } from '@ngrx/store';
import { UsersActions } from './users.actions';

export interface UsersState {
  items: User[];
  loading: boolean;
  error: string | null;
}

const initialState: UsersState = { items: [], loading: false, error: null };

export const usersReducer = createReducer(
  initialState,
  on(UsersActions.loadUsers, (state) => ({ ...state, loading: true, error: null })),
  on(UsersActions.loadUsersSuccess, (state, { users }) => ({ ...state, loading: false, items: users })),
  on(UsersActions.loadUsersFailure, (state, { error }) => ({ ...state, loading: false, error })),
  on(UsersActions.deleteUser, (state, { id }) => ({ ...state, items: state.items.filter((u) => u.id !== id) })),
);
```

### Selectors

```ts
// users.selectors.ts
import { createFeatureSelector, createSelector } from '@ngrx/store';
import type { UsersState } from './users.reducer';

export const selectUsersState = createFeatureSelector<UsersState>('users');

export const selectAllUsers = createSelector(
  selectUsersState,
  (state) => state.items
);

export const selectUserCount = createSelector(
  selectAllUsers,
  (users) => users.length
);

export const selectUserById = (id: string) => createSelector(
  selectAllUsers,
  (users) => users.find((u) => u.id === id)
);
```

### Effects

```ts
// users.effects.ts
import { Injectable, inject } from '@angular/core';
import { Actions, createEffect, ofType } from '@ngrx/effects';
import { catchError, map, of, switchMap } from 'rxjs';
import { HttpClient } from '@angular/common/http';
import { UsersActions } from './users.actions';

@Injectable()
export class UsersEffects {
  private actions$ = inject(Actions);
  private http = inject(HttpClient);

  loadUsers$ = createEffect(() =>
    this.actions$.pipe(
      ofType(UsersActions.loadUsers),
      switchMap(() =>
        this.http.get<User[]>('/api/users').pipe(
          map((users) => UsersActions.loadUsersSuccess({ users })),
          catchError((err) => of(UsersActions.loadUsersFailure({ error: err.message })))
        )
      )
    )
  );
}
```

### Component usage

```ts
@Component({...})
export class UsersListComponent implements OnInit {
  private store = inject(Store);

  users = this.store.selectSignal(selectAllUsers);   // signal-based selector (NgRx 17+)
  count = this.store.selectSignal(selectUserCount);

  ngOnInit() {
    this.store.dispatch(UsersActions.loadUsers());
  }
}
```

`store.selectSignal(selector)` returns a `Signal<T>` — read with `users()` in template.

For Observable-based: `users$ = this.store.select(selectAllUsers)` + `async` pipe.

## NgRx Component Store (per-component reactive store)

For feature-local state too small for full Store pattern:

```ts
import { ComponentStore } from '@ngrx/component-store';

interface PaginationState {
  page: number;
  pageSize: number;
  total: number;
}

@Injectable()
export class PaginationStore extends ComponentStore<PaginationState> {
  constructor() {
    super({ page: 1, pageSize: 10, total: 0 });
  }

  readonly page$ = this.select((s) => s.page);
  readonly totalPages$ = this.select((s) => Math.ceil(s.total / s.pageSize));

  readonly setPage = this.updater((state, page: number) => ({ ...state, page }));

  readonly loadPage = this.effect((trigger$: Observable<void>) =>
    trigger$.pipe(
      switchMap(() => this.api.fetchPage(this.get().page).pipe(
        tapResponse(
          (data) => this.patchState({ total: data.total }),
          (err) => console.error(err)
        )
      ))
    )
  );
}

// In component
providers: [PaginationStore]
```

Provided per-component (not `providedIn: 'root'`) — unique instance.

## NgRx Signals (newer, 2024+)

`@ngrx/signals` provides a signal-based store API. Less verbose than full Store + Effects:

```ts
import { signalStore, withState, withMethods, withComputed } from '@ngrx/signals';
import { computed, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';

export const UsersStore = signalStore(
  { providedIn: 'root' },
  withState<{ items: User[]; loading: boolean }>({ items: [], loading: false }),
  withComputed((state) => ({
    count: computed(() => state.items().length),
  })),
  withMethods((state, http = inject(HttpClient)) => ({
    async loadUsers() {
      patchState(state, { loading: true });
      const items = await firstValueFrom(http.get<User[]>('/api/users'));
      patchState(state, { items, loading: false });
    },
  }))
);

// Use
const store = inject(UsersStore);
store.count();         // signal
store.loadUsers();     // method
```

Drop-in for many feature-state cases. Less boilerplate than full NgRx Store.

## Anti-patterns

- ❌ Subscribing to observables without unsubscription strategy — leaks memory.
- ❌ Using `effect()` for derived state — use `computed()`.
- ❌ Reading `this.someService.value()` inside `effect()` then calling `this.someService.update()` from same effect — circular update warning.
- ❌ Calling signal without parens (`*ngIf="user"` instead of `*ngIf="user()"`) — common bug, doesn't unwrap.
- ❌ Putting all state in NgRx Store when service+signals would do.
- ❌ Subscribing to `NgRx Store.select()` then mutating result — selectors return immutable references.
- ❌ Forgetting `provideStore` / `provideEffects` in standalone bootstrap — runtime errors.
- ❌ Mixing observable + signal mental models in one feature without `toSignal`/`toObservable` bridges.
- ❌ Using `BehaviorSubject` exposed publicly without `.asObservable()` — consumers can `.next()`.
- ❌ Manual `Subject<void>` cleanup pattern in Angular 16+ — use `takeUntilDestroyed()`.
