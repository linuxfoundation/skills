---
name: lfx-intercom
description: >
  Add or fix Intercom integration in an LFX Angular app. Detects existing
  integrations and audits them against the LFX canonical pattern — correcting
  missing JWT pre-set, broken shutdown, missing Auth0 claim, wrong app IDs, or
  absent CSP entries. Fresh installs and legacy fixes use the same workflow.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion
---

<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->
<!-- Tool names in this file use Claude Code vocabulary. See docs/tool-mapping.md for other platforms. -->

# LFX Intercom Integration Skill

You are bringing Intercom up to the LFX standard in an Angular application. This
skill handles both fresh installs and fixing/standardizing existing integrations.
Follow every step in order — the audit step (Step 2) determines which fixes are
needed. Do not skip the Auth0 section — without it, identity verification will
silently fail.

---

## Step 1 — Gather Context

Ask the user:

1. **Goal** — Are you adding Intercom for the first time, or fixing/standardizing
   an existing integration?
2. **App name** — What is the exact Auth0 client name for this app? (e.g. "LFX
   Project Control Center", "CB Funding"). This must match the `case` in the
   Auth0 custom_claims action exactly.
3. **Public pages?** — Is this app accessible to non-authenticated visitors?
   - **Yes** (e.g. Mentorship, Crowdfunding, Insights) → Intercom must boot
     anonymously on page load so banners/popups are visible to all visitors,
     then upgrade to identified on login.
   - **No** (e.g. PCC, Org Dashboard, Individual Dashboard, Security) → Intercom
     boots only after login. No anonymous boot needed.
4. **Angular version** — Angular 6 (ngrx) or Angular 14+ (standalone/signals)?
5. **LaunchDarkly** — Does this app use LaunchDarkly? If yes, Intercom should be
   feature-flagged behind `enable-intercom`.
6. **Intercom App ID** — Dev: `mxl90k6y`, Prod: `w29sqomy` (shared across all
   LFX apps; already set in Step 3 — just confirm the user hasn't been given
   different IDs by the Intercom admin).

---

## Step 2 — Audit Existing Integration

Search the repo for any existing Intercom integration before writing any code.
Check all of the following and produce a gap report:

| Check | What to look for | LFX Standard |
|---|---|---|
| **IntercomService** | Does `intercom.service.ts` exist? | Direct script injection, `isLoaded` + `isBooted` + `isLoading` + `bootedWithIdentity` state, `boot()` returns `Promise<void>` |
| **npm package** | `@intercom/messenger-js-sdk` or similar in `package.json` | ❌ Not allowed — use script injection |
| **Intercom stub** | Does `initializeIntercomFunction()` create the `i.q` stub? | ✅ Required — queues commands before script loads |
| **JWT pre-set** | Is `window.intercomSettings.intercom_user_jwt` set *before* `window.Intercom('boot')` is called? | ✅ Required |
| **JWT stripped from boot options** | Is `intercom_user_jwt` removed from the options passed to `window.Intercom('boot')`? | ✅ Required — JWT only in `intercomSettings`, not boot payload |
| **Anonymous boot** | Is `bootIntercomAnonymous()` called in `ngOnInit()` before user auth check? | ✅ Required if app has public pages; skip if auth-only app |
| **Anonymous→identified upgrade** | Does `boot()` detect anonymous session and upgrade to identified via `shutdownForReboot()`? | ✅ Required if anonymous boot is used — `bootedWithIdentity` flag tracks session type |
| **Identified boot** | Is identified `boot()` called inside `userProfile$` subscription with `intercomBootAttempted` guard? | ✅ Required |
| **Shutdown on logout** | Is `Intercom('shutdown')` called, JWT cleared, and anonymous session re-booted on logout? | ✅ Required |
| **App IDs** | Dev: `mxl90k6y`, Prod: `w29sqomy` | ✅ Shared across all LFX apps |
| **Auth0 claim** | Is `http://lfx.dev/claims/intercom` used (not the deprecated HMAC)? | ✅ JWT claim only |
| **CSP** | Are ALL Intercom domains in the Content Security Policy, including WebSocket entries? | ✅ Required if CSP exists |
| **environment vars** | Are all 4 env fields present in both `environment.ts` and `environment.prod.ts`? | ✅ Required |

After the audit, tell the user what is already correct, what is missing, and what
needs to be fixed. Then proceed only with the steps that address identified gaps.
If nothing is wrong, say so and exit — do not make unnecessary changes.

---

## Step 3 — Add Environment Variables

Add to `environment.ts`:
```typescript
intercomId: 'mxl90k6y',
intercomApiBase: 'https://api-iam.intercom.io',
auth0IntercomClaim: 'http://lfx.dev/claims/intercom',
auth0UsernameClaim: 'https://sso.linuxfoundation.org/claims/username',
```

Add to `environment.prod.ts`:
```typescript
intercomId: 'w29sqomy',
intercomApiBase: 'https://api-iam.intercom.io',
auth0IntercomClaim: 'http://lfx.dev/claims/intercom',
auth0UsernameClaim: 'https://sso.linuxfoundation.org/claims/username',
```

Also add these fields to the `Environment` interface if one exists.

---

## Step 4 — Generate IntercomService

Create `src/app/services/intercom.service.ts` (or
`src/app/shared/services/intercom.service.ts` — match existing service
placement). This is the canonical LFX implementation validated across Mentorship,
Crowdfunding, and PCC.

⚠️ **Adjust the `environment` import path** to match the chosen folder depth,
e.g. `../../environments/environment` from `src/app/services/` or
`../../../environments/environment` from `src/app/shared/services/`.

```typescript
import { Injectable } from '@angular/core';
import { environment } from '../../environments/environment'; // adjust depth if needed

export interface IntercomBootOptions {
  api_base?: string;
  app_id?: string;
  user_id?: string;
  name?: string;
  email?: string;
  created_at?: number;
  intercom_user_jwt?: string;
  [key: string]: any;
}

declare global {
  interface Window {
    Intercom?: any;
    intercomSettings?: any;
  }
}

@Injectable({ providedIn: 'root' })
export class IntercomService {
  private isLoaded = false;
  private isBooted = false;
  private isLoading = false;
  private bootedWithIdentity = false;

  /**
   * Boot Intercom. Can be called with no user data (anonymous — for banners/popups)
   * or with user data (identified — for authenticated sessions).
   * Returns a Promise so the caller can handle failures.
   */
  public boot(options: IntercomBootOptions): Promise<void> {
    return new Promise((resolve, reject) => {
      if (typeof window === 'undefined') {
        reject(new Error('Window is undefined'));
        return;
      }

      if (!environment.intercomId) {
        reject(new Error('No Intercom ID configured'));
        return;
      }

      if (this.isBooted) {
        if (options.user_id && !this.bootedWithIdentity) {
          // Upgrade from anonymous to identified: shutdown and re-boot with identity
          this.shutdownForReboot();
        } else {
          // Already booted in the same mode — update instead
          const { intercom_user_jwt: _jwt, app_id: _appId, api_base: _apiBase, ...userOptions } = options;
          this.update(userOptions);
          resolve();
          return;
        }
      }

      // Kick off script loading (deferred to first boot call)
      if (!this.isLoaded && !this.isLoading) {
        this.isLoading = true;
        this.loadIntercomScript();
      }

      // Set JWT in intercomSettings before boot — required for identity verification
      if (options.intercom_user_jwt) {
        window.intercomSettings = window.intercomSettings || {};
        window.intercomSettings.intercom_user_jwt = options.intercom_user_jwt;
      }

      // Poll until script is fully loaded (isLoaded flag, not just window.Intercom — the
      // stub is created immediately but the real script must load for identity verification)
      const checkLoaded = setInterval(() => {
        if (this.isLoaded && window.Intercom) {
          clearInterval(checkLoaded);
          clearTimeout(timeoutHandle);

          // Another concurrent boot() call may have already booted
          if (this.isBooted) {
            if (options.user_id && !this.bootedWithIdentity) {
              // Concurrent anonymous boot finished first — upgrade to identified
              this.shutdownForReboot();
              // Fall through to boot with identity below
            } else {
              const { intercom_user_jwt: _jwt, app_id: _appId, api_base: _apiBase, ...userOptions } = options;
              this.update(userOptions);
              resolve();
              return;
            }
          }

          // Set flag before calling boot() to prevent concurrent calls from racing
          this.isBooted = true;

          try {
            // Strip JWT from boot options — it's already in window.intercomSettings
            const { intercom_user_jwt: _jwt, ...bootOptions } = options;

            window.Intercom('boot', {
              api_base: environment.intercomApiBase,
              app_id: environment.intercomId,
              ...bootOptions,
            });
            this.bootedWithIdentity = !!bootOptions.user_id;

            // Force update to ensure user attributes are applied (only for identified users)
            if (bootOptions.user_id) {
              try {
                window.Intercom('update', {
                  user_id: bootOptions.user_id,
                  name: bootOptions.name,
                  email: bootOptions.email,
                });
              } catch (updateError) {
                console.warn('IntercomService: Update after boot failed', updateError);
                // Don't reset isBooted — Intercom is still booted
              }
            }

            resolve();
          } catch (error) {
            this.isBooted = false;
            console.error('IntercomService: Boot failed', error);
            reject(error);
          }
        }
      }, 100);

      const timeoutHandle = setTimeout(() => {
        clearInterval(checkLoaded);
        if (!this.isBooted) {
          this.isLoading = false;
          reject(new Error('Intercom script failed to load — check network, CSP, or ad blockers'));
        }
      }, 10000);
    });
  }

  public update(data?: Partial<IntercomBootOptions>): void {
    if (typeof window !== 'undefined' && window.Intercom && this.isBooted) {
      try {
        window.Intercom('update', data || {});
      } catch (error) {
        console.error('IntercomService: Update failed', error);
      }
    }
  }

  public show(): void {
    if (typeof window !== 'undefined' && window.Intercom && this.isBooted) {
      try {
        window.Intercom('show');
      } catch (error) {
        console.error('IntercomService: Show failed', error);
      }
    }
  }

  public hide(): void {
    if (typeof window !== 'undefined' && window.Intercom && this.isBooted) {
      try {
        window.Intercom('hide');
      } catch (error) {
        console.error('IntercomService: Hide failed', error);
      }
    }
  }

  public shutdown(): void {
    if (typeof window !== 'undefined') {
      // Clear JWT first — prevents credential leakage across sessions
      if (window.intercomSettings?.intercom_user_jwt) {
        delete window.intercomSettings.intercom_user_jwt;
      }

      if (window.Intercom && this.isBooted) {
        try {
          window.Intercom('shutdown');
          this.isBooted = false;
          this.bootedWithIdentity = false;
        } catch (error) {
          console.error('IntercomService: Shutdown failed', error);
        }
      }
    }
  }

  /**
   * Internal shutdown for re-booting (anonymous → identified transition).
   * Resets boot state but keeps the script loaded.
   */
  private shutdownForReboot(): void {
    if (typeof window !== 'undefined' && window.Intercom) {
      try {
        window.Intercom('shutdown');
      } catch (error) {
        console.warn('IntercomService: Shutdown for reboot failed', error);
      }
    }
    this.isBooted = false;
    this.bootedWithIdentity = false;
  }

  public trackEvent(eventName: string, metadata?: Record<string, any>): void {
    if (typeof window !== 'undefined' && window.Intercom && this.isBooted) {
      try {
        window.Intercom('trackEvent', eventName, metadata);
      } catch (error) {
        console.error('IntercomService: Track event failed', error);
      }
    }
  }

  public isIntercomBooted(): boolean {
    return this.isBooted;
  }

  private loadIntercomScript(): void {
    if (this.isLoaded || typeof window === 'undefined') {
      return;
    }

    // Create Intercom stub so queued calls work before script loads
    this.initializeIntercomFunction();

    // Pre-set app settings (JWT added separately in boot())
    window.intercomSettings = {
      api_base: environment.intercomApiBase,
      app_id: environment.intercomId,
    };

    const script = document.createElement('script');
    script.type = 'text/javascript';
    script.async = true;
    script.src = `https://widget.intercom.io/widget/${environment.intercomId}`;

    script.onload = () => {
      this.isLoaded = true;
      this.isLoading = false;
    };

    script.onerror = error => {
      this.isLoading = false;
      console.error('IntercomService: Failed to load script', error);
    };

    // Insert before first existing script for optimal load ordering
    const firstScript = document.getElementsByTagName('script')[0];
    if (firstScript?.parentNode) {
      firstScript.parentNode.insertBefore(script, firstScript);
    } else {
      (document.head || document.body).appendChild(script);
    }
  }

  private initializeIntercomFunction(): void {
    if (typeof window === 'undefined') {
      return;
    }

    const w = window as any;
    const ic = w.Intercom;

    if (typeof ic === 'function') {
      // Script already loaded (e.g. page reload) — reattach
      ic('reattach_activator');
      ic('update', w.intercomSettings);
    } else {
      // Create stub that queues commands until the real script loads
      const i: any = (...args: any[]) => { i.c(args); };
      i.q = [];
      i.c = (args: any) => { i.q.push(args); };
      w.Intercom = i;
    }
  }
}
```

---

## Step 5 — Wire into app.component.ts

The Intercom lifecycle has three phases: anonymous boot on page load, identified
upgrade on login, and shutdown + anonymous re-boot on logout.

### 5a — Class field and anonymous boot in ngOnInit

```typescript
// Class field
private intercomBootAttempted = false;
```

**If the app has public pages** (Step 1, question 3 = Yes), add the anonymous
boot call in `ngOnInit()` BEFORE the auth subscription:

```typescript
ngOnInit() {
  // Boot Intercom in anonymous mode so banners/popups show for all visitors
  this.bootIntercomAnonymous();
  // Setup user related settings (auth subscription)
  this.userSettings();
  // ... other init code ...
}
```

**If the app is auth-only** (Step 1, question 3 = No), skip the anonymous boot —
Intercom will boot only when the user logs in (Step 5b).

### 5b — Identified boot on login + shutdown on logout

Inside the `auth.userProfile$` subscription in `userSettings()`:

```typescript
if (userProfile) {
  // Boot Intercom with Auth0 user data (environment-controlled)
  if (!this.intercomBootAttempted && environment.intercomId) {
    const intercomJwt = userProfile[environment.auth0IntercomClaim];
    const userId = userProfile[environment.auth0UsernameClaim];

    if (userId && intercomJwt) {
      this.intercomBootAttempted = true;
      this.intercomService
        .boot({
          api_base: environment.intercomApiBase,
          app_id: environment.intercomId,
          intercom_user_jwt: intercomJwt,
          user_id: userId,
          name: userProfile.name,
          email: userProfile.email,
        })
        .catch((error: any) => {
          console.error('AppComponent: Failed to boot Intercom', error);
          this.intercomBootAttempted = false; // Allow retry on next emission
        });
    } else {
      console.warn('AppComponent: Intercom not booted — missing required claim(s)', {
        hasUserId: !!userId,
        hasIntercomJwt: !!intercomJwt,
      });
    }
  }
} else if (userProfile == null) {
  // Logout — shutdown identified session
  if (this.intercomBootAttempted) {
    this.intercomService.shutdown();
    this.intercomBootAttempted = false;
    // Re-boot anonymous so banners remain visible (public-page apps only)
    this.bootIntercomAnonymous();
  }
}
```

⚠️ **Use `== null`** (loose equality) for the logout check — this catches both
`null` and `undefined`, which different auth services may emit.

### 5c — Anonymous boot helper method (public-page apps only)

**Include this method only if the app has public pages** (Step 1, question 3 = Yes).
Auth-only apps do not need this method — remove the `bootIntercomAnonymous()` calls
from ngOnInit and the logout block if the app is auth-only.

```typescript
/**
 * Boot Intercom without user identity so banners and popups are visible to all visitors.
 * When the user logs in, the authenticated boot call will upgrade the session with identity.
 */
private bootIntercomAnonymous() {
  if (environment.intercomId) {
    this.intercomService
      .boot({
        app_id: environment.intercomId,
        api_base: environment.intercomApiBase,
      })
      .catch((error: any) => {
        console.warn('AppComponent: Anonymous Intercom boot failed', error);
      });
  }
}
```

### Boot lifecycle summary

**Public-page apps** (Mentorship, Crowdfunding, Insights):
```
Page Load
  → bootIntercomAnonymous()               // banners visible to all visitors
  → Intercom boots with no user_id         // bootedWithIdentity = false

User Logs In (userProfile$ emits user)
  → boot({ user_id, intercom_user_jwt, ... })
  → IntercomService detects bootedWithIdentity === false
  → shutdownForReboot()                    // clears anonymous session
  → Intercom re-boots with identity        // bootedWithIdentity = true

User Logs Out (userProfile$ emits null)
  → shutdown()                             // clears identified session + JWT
  → intercomBootAttempted = false
  → bootIntercomAnonymous()                // banners visible again
```

**Auth-only apps** (PCC, Org Dashboard, Individual Dashboard, Security):
```
Page Load
  → (nothing — user must log in first)

User Logs In (userProfile$ emits user)
  → boot({ user_id, intercom_user_jwt, ... })
  → Intercom boots with identity           // bootedWithIdentity = true

User Logs Out (userProfile$ emits null)
  → shutdown()                             // clears identified session + JWT
  → intercomBootAttempted = false
```

If the app uses **LaunchDarkly**, wrap both the anonymous and identified boot
blocks:
```typescript
if (this.ldClient.variation('enable-intercom', false)) {
  // ... boot block ...
} else {
  console.info('Intercom: Disabled by LaunchDarkly feature flag');
}
```

---

## Step 6 — Auth0 Configuration (REQUIRED)

⚠️ **This step is required.** Without it, the `http://lfx.dev/claims/intercom`
JWT claim will not be present in the user's token and Intercom will boot without
identity verification — a security issue.

### What needs to happen

The Auth0 `custom_claims` Action in the `auth0-terraform` repo must be updated
to add your app to the switch statement that generates the Intercom JWT claim.

### File to modify

`auth0-terraform/src/actions/custom_claims.js`

### Change required

Add a new `case` block to the `switch (event.client.name)` statement:

```javascript
case "Your App Name Here": {
  // HMAC claim is deprecated but kept for backward compat with existing clients.
  // New apps must add both until all clients migrate to the JWT claim.
  api.idToken.setCustomClaim(
    `${lfPrefix}intercom`,
    intercomHMAC(event.user.username),
  );
  api.idToken.setCustomClaim(
    `${lfxPrefix}intercom`,
    await intercomJWT(event.user.username),
  );
  break;
}
```

Replace `"Your App Name Here"` with the **exact Auth0 client name** for your
app (case-sensitive, must match `event.client.name` exactly).

### How the JWT is generated

- **Secret**: Stored in AWS Secrets Manager at
  `/cloudops/managed-secrets/cloud/intercom/secret_key`
- **Algorithm**: HS256
- **Expiry**: 12 hours
- **Payload**: `{ user_id, email, name? }`
- The secret is automatically injected into the Auth0 Action via Terraform —
  no manual secret management needed once it's in the switch statement.

### Who to contact

Raise a PR against `auth0-terraform` or ask the platform/infra team to add your
app. This is a Terraform-managed change and requires deployment to dev, staging,
and prod Auth0 tenants.

### How to verify

After the Auth0 change is deployed, decode a fresh ID token for your app (e.g.
using jwt.io) and confirm `http://lfx.dev/claims/intercom` is present and
contains a valid JWT with `user_id`, `email` fields.

---

## Step 7 — Verify the Integration

1. Run the app locally using `127.0.0.1` (not `localhost` — see Notes below)
2. **Before logging in**: verify Intercom loads (check console for
   `IntercomService: Script loaded successfully`) — banners/popups should be
   visible to anonymous visitors
3. Log in and check that the console shows
   `IntercomService: Upgrading from anonymous to identified session`
4. Verify the Intercom chat bubble appears with your identity
5. Open browser console and run: `window.Intercom('getVisitorId')` — should
   return a string, not an error
6. Log out and confirm the console shows `Intercom('shutdown')` followed by a
   fresh anonymous boot — banners should remain visible
7. Decode the Auth0 ID token and confirm `http://lfx.dev/claims/intercom` is
   present (if Auth0 change is deployed)
8. In Intercom dashboard, confirm the user appears with correct name/email

---

## Keeping This Skill Up to Date

**Canonical reference app**: LFX Mentorship (`jobspring` / `lfx-mentorship-upgrade`
repo) is the source of truth for the LFX Intercom pattern. When in doubt about
what "correct" looks like, check how Mentorship implements it — Crowdfunding and
PCC follow the same pattern and can be used for cross-validation.

**If you find this skill is outdated**: Update `SKILL.md` in the same PR where
you fix the app. Do not defer it. The skill is wrong for everyone until it's
fixed.

**Last validated**: 2026-03-24 against LFX Mentorship (PRs #147, #148),
Crowdfunding (PRs #31-#38), and PCC.

---

## Notes

- **Do not use an npm Intercom package** — LFX uses direct script injection
  consistently across all apps. Keep it consistent.
- **The HMAC claim** (`https://sso.linuxfoundation.org/claims/intercom`) is
  deprecated — the JWT claim (`http://lfx.dev/claims/intercom`) is current. Use
  only the JWT claim in your Angular code.
- **Shared App IDs**: Dev (`mxl90k6y`) and Prod (`w29sqomy`) are shared across
  all LFX apps. Do not create a new Intercom workspace.
- **Identity verification is mandatory** — do not boot identified Intercom
  without the JWT. Booting without it allows users to impersonate others in
  Intercom. Anonymous boot (no user_id) does not require JWT.
- **Local development**: Intercom only works on `127.0.0.1` locally — `localhost`
  is not supported and the launcher will not appear. Run your dev server bound to
  `127.0.0.1` (e.g. `ng serve --host 127.0.0.1`) or access via `http://127.0.0.1:4200`.
- **New hostname registration (REQUIRED)**: Intercom must be configured to allow
  each hostname where the launcher will appear. If you deploy to a new domain or
  subdomain and the chat bubble does not show, contact the Intercom Admin
  (Heather's team) to add the hostname to the Intercom installation settings. This
  applies to staging/preview environments as well as production.
- **CSP**: Add ALL of the following entries to your Content Security Policy if
  the app has one set (the WebSocket entries are required for real-time chat):
  ```
  script-src   https://widget.intercom.io https://*.intercomcdn.com
  connect-src  https://*.intercom.io https://*.intercomcdn.com https://*.intercom-messenger.com
               wss://*.intercom-messenger.com wss://*.intercom.io
  style-src    https://*.intercomcdn.com
  font-src     https://*.intercomcdn.com
  img-src      https://static.intercomassets.com https://*.intercomcdn.com
  frame-src    https://*.intercom.io https://*.intercom-messenger.com https://intercom-sheets.com
  media-src    https://js.intercomcdn.com
  ```
