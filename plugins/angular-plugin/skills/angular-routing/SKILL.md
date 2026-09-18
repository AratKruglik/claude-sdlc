---
name: angular-routing
description: |
  Angular Router (built-in `@angular/router`) — route configuration for standalone and NgModule projects, functional guards (Angular 14.1+), lazy loading, route resolvers, typed params via signals/observables, programmatic navigation, route data and meta.

  Use this skill to:
  - Configure routes (standalone-style or NgModule-style).
  - Use functional guards (canActivate as function, preferred over class-based in 17+).
  - Lazy-load components or feature modules.
  - Implement auth guards via route meta + functional guards.
  - Read params/queries via `inject(ActivatedRoute)` + signals or RxJS.

  Do NOT use this skill for:
  - General conventions (see angular-conventions).
  - State management (see angular-state-and-rx).
  - Forms (see angular-forms).
  - Testing routes (see angular-testing).
user-invocable: false
paths: ["src/**/*.ts"]
---

# Angular Routing

Angular Router is built-in (`@angular/router`) — no third-party. This skill covers configuration, navigation, guards, lazy loading.

## Setup

### Standalone (Angular 17+)

```ts
// app.routes.ts
import { Routes } from '@angular/router';
import { authGuard } from './core/auth/auth.guard';

export const routes: Routes = [
  { path: '', component: HomeComponent },
  { path: 'login', component: LoginComponent },
  {
    path: 'dashboard',
    loadComponent: () => import('./features/dashboard/dashboard.component').then((m) => m.DashboardComponent),
    canActivate: [authGuard],
  },
  {
    path: 'users',
    loadChildren: () => import('./features/users/users.routes').then((m) => m.usersRoutes),
  },
  { path: '**', component: NotFoundComponent },
];
```

```ts
// main.ts (or app.config.ts)
bootstrapApplication(AppComponent, {
  providers: [
    provideRouter(routes, withComponentInputBinding(), withViewTransitions()),
    provideHttpClient(),
  ],
});
```

`provideRouter` features:
- `withComponentInputBinding()` — auto-binds route params to component `@Input()` / `input()`.
- `withViewTransitions()` — uses View Transitions API for navigation animations.
- `withInMemoryScrolling({ scrollPositionRestoration: 'enabled' })` — restore scroll on back nav.
- `withDebugTracing()` — log all navigation events.

### NgModule (legacy)

```ts
// app-routing.module.ts
import { NgModule } from '@angular/core';
import { RouterModule, Routes } from '@angular/router';

const routes: Routes = [ /* same shape */ ];

@NgModule({
  imports: [RouterModule.forRoot(routes)],
  exports: [RouterModule],
})
export class AppRoutingModule {}

// AppModule imports AppRoutingModule
```

`<router-outlet>` in `app.component.html` renders the matched component.

## Route configuration

```ts
{
  path: 'users',
  component: UsersComponent,
  data: { title: 'Users' },              // arbitrary route metadata
  resolve: { users: usersResolver },     // pre-load data
  canActivate: [authGuard],
  canDeactivate: [unsavedChangesGuard],
  children: [
    { path: '', component: UsersListComponent },
    { path: ':id', component: UserDetailComponent, resolve: { user: userResolver } },
    { path: ':id/edit', component: UserEditComponent, canDeactivate: [unsavedChangesGuard] },
  ],
}
```

### Path matching

```ts
{ path: '', component: HomeComponent }                     // empty path (root)
{ path: 'users', component: UsersComponent }               // /users
{ path: 'users/:id', component: UserDetailComponent }      // /users/123
{ path: 'users/:id/posts/:postId' }                        // multiple params
{ path: 'docs/**', component: DocsComponent }              // wildcard catch-all
{ path: '**', component: NotFoundComponent }               // global 404 (always last)
{ path: 'old', redirectTo: 'new', pathMatch: 'full' }      // redirect
```

`pathMatch: 'full'` for redirects — otherwise `path: ''` matches every URL.

### Lazy loading

**Standalone component**:
```ts
{
  path: 'dashboard',
  loadComponent: () => import('./features/dashboard/dashboard.component').then((m) => m.DashboardComponent),
}
```

**Feature routes file**:
```ts
// features/users/users.routes.ts
import { Routes } from '@angular/router';
import { UsersListComponent } from './users-list.component';

export const usersRoutes: Routes = [
  { path: '', component: UsersListComponent },
  { path: ':id', loadComponent: () => import('./user-detail.component').then((m) => m.UserDetailComponent) },
];

// app.routes.ts
{
  path: 'users',
  loadChildren: () => import('./features/users/users.routes').then((m) => m.usersRoutes),
}
```

**NgModule (legacy)**:
```ts
{
  path: 'users',
  loadChildren: () => import('./features/users/users.module').then((m) => m.UsersModule),
}
```

Lazy loading creates a separate JS chunk — first navigation downloads it, subsequent uses cached.

## Functional guards (Angular 14.1+, preferred)

```ts
// core/auth/auth.guard.ts
import { CanActivateFn, Router } from '@angular/router';
import { inject } from '@angular/core';
import { AuthService } from './auth.service';

export const authGuard: CanActivateFn = (route, state) => {
  const auth = inject(AuthService);
  const router = inject(Router);

  if (auth.isAuthenticated()) {
    return true;
  }

  // Redirect to login with return URL
  router.navigate(['/login'], { queryParams: { returnUrl: state.url } });
  return false;
};
```

Apply:
```ts
{ path: 'dashboard', component: DashboardComponent, canActivate: [authGuard] }
```

### Multiple guards

```ts
{ path: 'admin', component: AdminComponent, canActivate: [authGuard, roleGuard('admin')] }
```

Composed guards run in order; if any returns false / UrlTree, route blocks.

### Guard factory pattern

```ts
export const roleGuard = (requiredRole: string): CanActivateFn => (route, state) => {
  const auth = inject(AuthService);
  return auth.hasRole(requiredRole);
};

// Usage
{ canActivate: [roleGuard('admin')] }
```

### Other guard types

| Guard | When |
|---|---|
| `canActivate` | Before activating route |
| `canActivateChild` | Before activating child routes |
| `canDeactivate` | Before leaving route (unsaved changes prompt) |
| `canLoad` | Before lazy-loading the route module/component (deprecated in favor of `canMatch`) |
| `canMatch` | Conditionally match the route (Angular 14.2+) |
| `resolve` | Pre-fetch data before route activates |

### Class-based guards (legacy)

```ts
@Injectable({ providedIn: 'root' })
export class AuthGuard implements CanActivate {
  canActivate(route: ActivatedRouteSnapshot, state: RouterStateSnapshot): boolean | UrlTree {
    // ...
  }
}
```

Still works but functional API is preferred. Don't migrate existing class guards as part of feature work unless BA spec asks.

## Resolvers

Pre-fetch data before route activates. Component receives data via `route.data` instead of loading inside `ngOnInit()`.

```ts
// users.resolver.ts
import { ResolveFn } from '@angular/router';
import { inject } from '@angular/core';
import { UsersService } from './users.service';
import type { User } from './user.model';

export const userResolver: ResolveFn<User> = (route) => {
  const usersService = inject(UsersService);
  const id = route.paramMap.get('id')!;
  return usersService.getUser(id);
};

// In route config
{ path: 'users/:id', component: UserDetailComponent, resolve: { user: userResolver } }

// In component
@Component({...})
export class UserDetailComponent {
  private route = inject(ActivatedRoute);
  user = this.route.snapshot.data['user'] as User;       // sync access
  // OR reactive
  user$ = this.route.data.pipe(map((data) => data['user'] as User));
}
```

Resolvers return Observable, Promise, or value. Navigation pauses until resolution completes.

## Programmatic navigation

```ts
import { Router } from '@angular/router';
import { inject } from '@angular/core';

@Component({...})
export class MyComponent {
  private router = inject(Router);

  goToProfile(id: string) {
    this.router.navigate(['/users', id]);
  }

  goRelative() {
    this.router.navigate(['..'], { relativeTo: this.route });
  }

  navigateWithQuery() {
    this.router.navigate(['/search'], { queryParams: { q: 'hello', page: 1 } });
  }

  replaceUrl() {
    this.router.navigate(['/login'], { replaceUrl: true });
  }
}
```

`router.navigate(commands, extras?)` — commands array; first element is path, rest are segments.

`router.navigateByUrl('/users/123?tab=overview')` — string URL alternative.

## Reading params and queries

### Snapshot (sync, only initial)

```ts
private route = inject(ActivatedRoute);

ngOnInit() {
  const id = this.route.snapshot.paramMap.get('id');
  const tab = this.route.snapshot.queryParamMap.get('tab') ?? 'overview';
}
```

Snapshot reflects route at component creation. Won't update if user navigates within same component.

### Observables (reactive)

```ts
this.route.paramMap
  .pipe(takeUntilDestroyed())
  .subscribe((params) => {
    this.id = params.get('id')!;
  });

this.route.queryParamMap
  .pipe(takeUntilDestroyed())
  .subscribe((qp) => {
    this.tab = qp.get('tab') ?? 'overview';
  });
```

Updates on every route change within same component instance.

### Signals (Angular 16+)

```ts
import { toSignal } from '@angular/core/rxjs-interop';
import { map } from 'rxjs';

id = toSignal(this.route.paramMap.pipe(map((p) => p.get('id') ?? '')), { initialValue: '' });
tab = toSignal(this.route.queryParamMap.pipe(map((q) => q.get('tab') ?? 'overview')), { initialValue: 'overview' });
```

Use signals when consuming in computed / template:

```ts
title = computed(() => `User ${this.id()}`);
```

### `withComponentInputBinding()` (Angular 16+)

```ts
provideRouter(routes, withComponentInputBinding()),
```

Route params auto-bind to component inputs:

```ts
@Component({ ... })
export class UserDetailComponent {
  @Input() id!: string;                  // bound from route param :id
  @Input() tab = 'overview';             // bound from query ?tab=
}
```

In Angular 17.1+ with signal inputs:

```ts
id = input.required<string>();           // signal version
tab = input<string>('overview');
```

Cleanest pattern. No need for `ActivatedRoute` injection in many cases.

## RouterLink

```html
<a routerLink="/users">Users</a>
<a [routerLink]="['/users', user.id]">{{ user.name }}</a>
<a [routerLink]="['/search']" [queryParams]="{ q: 'hello' }">Search</a>
<a routerLink="/dashboard" routerLinkActive="active" [routerLinkActiveOptions]="{ exact: true }">Dashboard</a>
```

For external URLs, use plain `<a href="...">` — `routerLink` is for internal nav only.

## Route metadata via `data`

```ts
{ path: 'admin', component: AdminComponent, data: { title: 'Admin', requiresAuth: true } }
```

Read in component:
```ts
this.route.data.subscribe((data) => {
  this.title = data['title'];
});
```

For app-wide title management:
```ts
// In root component
this.router.events
  .pipe(
    filter((e) => e instanceof NavigationEnd),
    takeUntilDestroyed()
  )
  .subscribe(() => {
    let route = this.route;
    while (route.firstChild) route = route.firstChild;
    const title = route.snapshot.data['title'] ?? 'My App';
    this.titleService.setTitle(title);
  });
```

Or use `provideRouter(routes, withRouterConfig({ paramsInheritanceStrategy: 'always' }))` + `Title` service.

Or Angular 14.1+: `title` route property, set automatically:
```ts
{ path: 'admin', component: AdminComponent, title: 'Admin | My App' }
{ path: 'users/:id', component: UserDetailComponent, title: userTitleResolver }
```

## Anti-patterns

- ❌ Forgetting `<router-outlet>` in layout — routes don't render.
- ❌ `<a href="/internal">` for internal nav — full reload, defeats SPA.
- ❌ Hardcoded route strings throughout app — define route constants in `app.routes.ts` or shared file.
- ❌ Subscribing to `route.params` without `takeUntilDestroyed()` — memory leak.
- ❌ Heavy logic in resolvers — slows navigation; keep resolvers thin.
- ❌ Returning `Observable<never>` from a guard without `UrlTree` — guard hangs.
- ❌ `pathMatch: 'full'` missing on redirect — redirect catches every URL.
- ❌ Class-based guards in new Angular 17+ projects — functional API is cleaner.
- ❌ Multiple `<router-outlet>` without named outlets — only the first activates.
- ❌ Lazy-loading single-component routes when not needed — premature optimization for small components.
