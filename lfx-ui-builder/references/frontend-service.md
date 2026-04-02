<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# Frontend Service Reference

## Location

`apps/lfx-one/src/app/shared/services/<name>.service.ts`

> **Prerequisite:** The backend endpoint must already exist (validated in Step 3, built earlier if needed). Do not create a frontend service that calls an API endpoint that doesn't exist — no mock data, no placeholder URLs.

> **Query service resources:** When the backend endpoint proxies the query service for a specific resource type, check that type's `docs/indexer-contract.md` (if present) before writing the service. It documents which fields are available in `data`, which `tags` and `filters` are supported, and which `name_and_aliases` fields drive typeahead — use it to ensure the Angular service passes the right query params and maps the response correctly. For a list of all queryable types and where to find each service's contract, see [`lfx-coordinator/references/indexed-data-types.md`](../../lfx-coordinator/references/indexed-data-types.md).

## Conventions

- `@Injectable({ providedIn: 'root' })` — always tree-shakeable
- `inject(HttpClient)` — never constructor-based DI
- **GET requests:** `catchError(() => of(defaultValue))` for graceful error handling
- **POST/PUT/DELETE requests:** `take(1)` and let errors propagate to the component
- **Shared state:** Use `signal()` for data consumed by multiple components
- **Signals can't use rxjs pipes** — use `computed()` or `toSignal()` for reactive transforms
- **Interfaces:** Import from `@lfx-one/shared/interfaces`, never define locally
- **API paths:** Use relative paths (e.g., `/api/items`) — the proxy handles routing

## Example Pattern

```typescript
import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject, signal } from '@angular/core';
import { catchError, of, take } from 'rxjs';
import { MyItem, PaginatedResponse } from '@lfx-one/shared/interfaces';

@Injectable({ providedIn: 'root' })
export class MyService {
  private readonly http = inject(HttpClient);

  // Shared state
  public items = signal<MyItem[]>([]);

  // GET — catchError with sensible default
  public getItems() {
    return this.http.get<MyItem[]>('/api/items').pipe(catchError(() => of([] as MyItem[])));
  }

  // GET with pagination params
  public getItemsPaginated(projectUid: string, pageSize?: number, pageToken?: string, search?: string) {
    let params = new HttpParams().set('parent', `project:${projectUid}`);
    if (pageSize) params = params.set('page_size', pageSize.toString());
    if (pageToken) params = params.set('page_token', pageToken);
    if (search) params = params.set('name', search);
    return this.http
      .get<PaginatedResponse<MyItem>>('/api/items', { params })
      .pipe(catchError(() => of({ data: [], page_token: undefined } as PaginatedResponse<MyItem>)));
  }

  // POST — take(1), let errors propagate
  public createItem(payload: Partial<MyItem>) {
    return this.http.post<MyItem>('/api/items', payload).pipe(take(1));
  }

  // PUT — take(1), let errors propagate
  public updateItem(uid: string, payload: Partial<MyItem>) {
    return this.http.put<MyItem>(`/api/items/${uid}`, payload).pipe(take(1));
  }

  // DELETE — take(1), let errors propagate
  public deleteItem(uid: string) {
    return this.http.delete<void>(`/api/items/${uid}`).pipe(take(1));
  }
}
```

## State Management Pattern

When multiple components share state:

```typescript
@Injectable({ providedIn: 'root' })
export class MyStateService {
  private readonly _items = signal<Item[]>([]);
  public readonly items = this._items.asReadonly();
  public readonly itemCount = computed(() => this._items().length);

  public setItems(items: Item[]): void {
    this._items.set(items);
  }
}
```

## When to Use Signals vs RxJS

- **Signals:** Simple state, derived values, template binding
- **RxJS:** Complex async flows, combining multiple streams, pagination with accumulation

## Checklist

- [ ] Uses `@Injectable({ providedIn: 'root' })`
- [ ] Uses `inject(HttpClient)` (not constructor DI)
- [ ] GET requests have `catchError` with sensible default
- [ ] POST/PUT/DELETE use `take(1)`
- [ ] Interfaces imported from `@lfx-one/shared/interfaces`
- [ ] API paths are relative (`/api/...`)
- [ ] No mock data or placeholder URLs
- [ ] File has license header
