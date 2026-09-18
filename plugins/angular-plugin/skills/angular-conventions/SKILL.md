---
name: angular-conventions
description: |
  Angular 18-21 project structure, standalone components vs NgModule, control flow (@if/@for/@switch + *ngIf/*ngFor legacy), decorators, dependency injection (inject() function), lifecycle hooks, pipes, Angular Universal SSR pointer.

  Use this skill to:
  - Detect project style (standalone vs NgModule) and apply matching patterns.
  - Pick correct decorators and DI approach.
  - Use modern control flow (@if/@for/@switch) in Angular 17+ projects.
  - Apply `inject()` function over constructor injection where appropriate.
  - Wire bootstrap correctly (bootstrapApplication for standalone, AppModule for legacy).

  Do NOT use this skill for:
  - State management (see angular-state-and-rx).
  - Routing (see angular-routing).
  - Forms (see angular-forms).
  - Testing (see angular-testing).
user-invocable: false
paths: ["src/**/*.ts", "src/**/*.html"]
---

# Angular Conventions

Modern Angular era (17+) with NgModule fallback for legacy projects. This skill covers structural patterns, decorators, DI, and template syntax.

## Project style detection

| Markers | Style |
|---|---|
| `bootstrapApplication(AppComponent, {...})` in `main.ts` + NO `*.module.ts` (or only `app-routing.module.ts`) | **Standalone-first** (Angular 17+ recommended) |
| `platformBrowserDynamic().bootstrapModule(AppModule)` + `app.module.ts` exists | **NgModule legacy** |
| Both bootstrap calls or partial migration | **Mixed/migrating** — mirror per area; prefer standalone for new code |

For new code in mixed projects, prefer standalone unless the team has a strict consistency rule.

## Project structure

```
src/
├── main.ts                          # bootstrap
├── index.html
├── styles.scss
├── app/
│   ├── app.component.ts             # root component
│   ├── app.component.html
│   ├── app.component.scss
│   ├── app.config.ts                # ApplicationConfig (standalone)
│   ├── app.routes.ts                # route definitions (standalone)
│   ├── app.module.ts                # AppModule (NgModule legacy)
│   ├── app-routing.module.ts        # routing module (NgModule legacy)
│   ├── core/                        # app-wide singletons
│   │   ├── auth/
│   │   │   ├── auth.service.ts
│   │   │   └── auth.guard.ts
│   │   └── http/
│   │       └── auth.interceptor.ts
│   ├── shared/                      # cross-feature components/pipes/directives
│   │   ├── components/
│   │   ├── pipes/
│   │   └── directives/
│   ├── features/                    # feature folders
│   │   ├── users/
│   │   │   ├── users.component.ts
│   │   │   ├── users.component.html
│   │   │   ├── users.component.scss
│   │   │   ├── users.service.ts
│   │   │   ├── users.routes.ts      # feature routes
│   │   │   └── user.model.ts
│   │   └── orders/
│   └── layout/                      # navbar, sidebar, app shell
├── assets/
└── environments/
    ├── environment.ts
    └── environment.prod.ts
```

Mirror project layout. Don't restructure as part of feature work.

## Standalone bootstrap (Angular 17+)

```ts
// main.ts
import { bootstrapApplication } from '@angular/platform-browser';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { AppComponent } from './app/app.component';
import { routes } from './app/app.routes';
import { authInterceptor } from './app/core/http/auth.interceptor';

bootstrapApplication(AppComponent, {
  providers: [
    provideRouter(routes),
    provideHttpClient(withInterceptors([authInterceptor])),
  ],
}).catch((err) => console.error(err));
```

Or split providers into `app.config.ts`:

```ts
// app.config.ts
import { ApplicationConfig } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { routes } from './app.routes';
import { authInterceptor } from './core/http/auth.interceptor';

export const appConfig: ApplicationConfig = {
  providers: [
    provideRouter(routes),
    provideHttpClient(withInterceptors([authInterceptor])),
  ],
};

// main.ts
bootstrapApplication(AppComponent, appConfig);
```

`provide*` functions are the standalone-era replacements for `*Module` imports. Examples: `provideRouter`, `provideHttpClient`, `provideAnimations`, `provideStore` (NgRx).

## NgModule bootstrap (legacy)

```ts
// main.ts
import { platformBrowserDynamic } from '@angular/platform-browser-dynamic';
import { AppModule } from './app/app.module';
platformBrowserDynamic().bootstrapModule(AppModule);

// app.module.ts
@NgModule({
  declarations: [AppComponent, UserListComponent, /* all components */],
  imports: [BrowserModule, AppRoutingModule, HttpClientModule, ReactiveFormsModule],
  providers: [{ provide: HTTP_INTERCEPTORS, useClass: AuthInterceptor, multi: true }],
  bootstrap: [AppComponent],
})
export class AppModule {}
```

Components and pipes must be declared in exactly one NgModule's `declarations` (NgModule legacy invariant).

## Standalone component

```ts
import { Component, signal, computed, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { UsersService } from './users.service';

@Component({
  selector: 'app-user-list',
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <h2>Users ({{ count() }})</h2>
    @if (loading()) {
      <p>Loading...</p>
    } @else {
      <ul>
        @for (user of users(); track user.id) {
          <li><a [routerLink]="['/users', user.id]">{{ user.name }}</a></li>
        }
      </ul>
    }
  `,
  styleUrl: './user-list.component.scss',
})
export class UserListComponent {
  private usersService = inject(UsersService);
  users = this.usersService.users;
  loading = this.usersService.loading;
  count = computed(() => this.users().length);
}
```

`standalone: true` + explicit `imports` array. The component declares its own template dependencies (CommonModule for pipes, RouterLink, other standalone components, etc.).

In Angular 19+, `standalone: true` is the default — you can omit it. For broad compatibility in 17/18, write it explicitly.

## NgModule component

```ts
@Component({
  selector: 'app-user-list',
  templateUrl: './user-list.component.html',
  styleUrl: './user-list.component.scss',
})
export class UserListComponent { /* same body */ }

// user.module.ts
@NgModule({
  declarations: [UserListComponent],
  imports: [CommonModule, RouterModule],
  exports: [UserListComponent],
})
export class UserModule {}
```

For NgModule projects, declare every component, directive, pipe in some module.

## Decorators

```ts
@Component({ ... })          // a Component (standalone or in NgModule)
@Directive({ ... })           // a Directive (selector-based behavior)
@Pipe({ name: 'capitalize', standalone: true })
                              // a Pipe transform
@Injectable({ providedIn: 'root' })
                              // a service singleton at root injector
@NgModule({ ... })            // a module (legacy)

// Component members
@Input() user!: User;         // input property (decorator-based, legacy)
@Input({ required: true }) user!: User;  // required input (Angular 16+)
@Input({ transform: trim }) name!: string;  // input with transform
@Output() delete = new EventEmitter<string>();
@HostBinding('class.active') isActive = false;
@HostListener('click', ['$event']) onClick(e: Event) {}
@ViewChild('myRef') myRef!: ElementRef;
@ContentChild(MyComponent) projected!: MyComponent;
```

For new code in Angular 17.1+, prefer signal-based `input()` / `output()` / `viewChild()`:

```ts
import { input, output, viewChild } from '@angular/core';

user = input.required<User>();              // required input as InputSignal<User>
name = input('Anonymous');                   // optional with default
delete = output<string>();                   // OutputEmitterRef<string>
myRef = viewChild<ElementRef>('myRef');     // Signal<ElementRef | undefined>
```

Mirror existing project — if all components use `@Input()`/`@Output()` decorators, follow that. New greenfield code: prefer signal-based APIs.

## Dependency injection

### `inject()` function (Angular 14.1+)

```ts
import { inject, Injectable } from '@angular/core';

@Injectable({ providedIn: 'root' })
export class UsersService {
  private http = inject(HttpClient);
  private router = inject(Router);

  loadUsers() {
    return this.http.get<User[]>('/api/users');
  }
}
```

`inject()` works inside:
- `@Injectable` services (constructor or class field initializers).
- `@Component` constructor or class field initializers.
- Route guards / resolvers (functional API).
- Factory providers.
- `runInInjectionContext()` blocks.

### Constructor injection (legacy, still works)

```ts
@Injectable({ providedIn: 'root' })
export class UsersService {
  constructor(private http: HttpClient, private router: Router) {}
}
```

Both work. `inject()` is preferred for new code due to:
- Works outside constructors (route guards, factory functions).
- Better type narrowing with generic tokens.
- Less boilerplate.

### Custom providers

```ts
// Standalone (in providers array of bootstrapApplication or component)
{ provide: API_URL, useValue: 'https://api.example.com' }
{ provide: 'CONFIG', useFactory: () => ({ retries: 3 }) }
{ provide: AuditLog, useClass: ProductionAuditLog }

// InjectionToken for type safety
import { InjectionToken } from '@angular/core';
export const API_URL = new InjectionToken<string>('API_URL');

// Inject
private apiUrl = inject(API_URL);
```

### Hierarchical injection

`providedIn: 'root'` — singleton at root injector (most services).
`providedIn: 'platform'` — shared across multiple Angular apps (rare).
Component-level providers in `@Component({ providers: [...] })` — new instance per component instance.

## Modern control flow (Angular 17+)

```html
@if (user(); as u) {
  <p>Welcome, {{ u.name }}</p>
} @else if (loading()) {
  <p>Loading...</p>
} @else {
  <a routerLink="/login">Log in</a>
}

@for (item of items(); track item.id; let i = $index, isFirst = $first) {
  <li [class.first]="isFirst">{{ i + 1 }}. {{ item.name }}</li>
} @empty {
  <li>No items</li>
}

@switch (status()) {
  @case ('loading') { <spinner /> }
  @case ('error') { <error-banner [error]="error()" /> }
  @default { <user-list [users]="users()" /> }
}
```

`track` is **mandatory** in `@for` — pick a stable identifier (entity ID), not index. Use `track $index` only when items have no stable identity.

`$index`, `$first`, `$last`, `$even`, `$odd`, `$count` are available local variables in `@for`.

## Legacy structural directives (NgModule projects, Angular ≤16)

```html
<p *ngIf="user; else noUser">Welcome, {{ user.name }}</p>
<ng-template #noUser>
  <a routerLink="/login">Log in</a>
</ng-template>

<li *ngFor="let item of items; trackBy: trackById">{{ item.name }}</li>

<div [ngSwitch]="status">
  <spinner *ngSwitchCase="'loading'"></spinner>
  <error-banner *ngSwitchCase="'error'" [error]="error"></error-banner>
  <user-list *ngSwitchDefault [users]="users"></user-list>
</div>
```

Requires `CommonModule` import.

## Lifecycle hooks

```ts
implements OnInit, OnDestroy, OnChanges, AfterViewInit
ngOnInit() { /* after first @Input() values bound, before view */ }
ngOnDestroy() { /* cleanup */ }
ngOnChanges(changes: SimpleChanges) { /* @Input changes — replaces by signal `effect` */ }
ngAfterViewInit() { /* DOM available */ }
```

Order:
1. Constructor (DI runs).
2. `ngOnChanges` (first call, with @Input values).
3. `ngOnInit`.
4. `ngDoCheck`.
5. `ngAfterContentInit`, `ngAfterContentChecked`.
6. `ngAfterViewInit`, `ngAfterViewChecked`.

For destruction: `ngOnDestroy`.

In standalone components with signals + `takeUntilDestroyed()`, manual `ngOnDestroy` is rarely needed.

## Pipes

```ts
// Built-in
{{ user.name | uppercase }}
{{ user.createdAt | date:'short' }}
{{ price | currency:'USD' }}
{{ data | json }}
{{ user$ | async }}                   // subscribe + unsubscribe automatic

// Custom standalone pipe
@Pipe({ name: 'truncate', standalone: true })
export class TruncatePipe implements PipeTransform {
  transform(value: string, max = 50): string {
    return value.length > max ? value.slice(0, max) + '...' : value;
  }
}

// Use
{{ description | truncate:100 }}
```

## Angular Universal (SSR) — pointer only

For Angular 17+: `@angular/ssr` package + `provideClientHydration()` + `provideServerRendering()`. Out of scope for v0.0.1 of this plugin (SPA-focused). If BA spec requires SSR, flag in BLOCKERS — needs separate spec or follow-up plugin.

For legacy: `@nguniversal/express-engine` — older approach.

## Anti-patterns

- ❌ `*ngIf`/`*ngFor`/`*ngSwitch` in Angular 17+ standalone projects — use `@if`/`@for`/`@switch`.
- ❌ Forgetting `track` in `@for` — Angular throws compile error in 17+.
- ❌ Using index as `track` for reorderable lists — defeats the optimization.
- ❌ Mixing standalone + NgModule arbitrarily — pick one per area.
- ❌ `new MyService()` outside test files — bypasses DI.
- ❌ Mutating `@Input()` / `input()` values directly — emit event for parent updates.
- ❌ `subscribe()` without unsubscription strategy — leaks.
- ❌ Logic in templates beyond simple expressions — extract to `computed()` or method.
- ❌ Calling signal without parens (`*ngIf="users"` instead of `*ngIf="users()"`) — common bug.
- ❌ `bypassSecurityTrustHtml` without justified upstream sanitization.
- ❌ Reading `process.env` in components — use `environment.ts` (still PUBLIC after build, but consistent).
