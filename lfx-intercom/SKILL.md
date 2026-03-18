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
3. **Angular version** — Angular 6 (ngrx) or Angular 14+ (standalone/signals)?
4. **LaunchDarkly** — Does this app use LaunchDarkly? If yes, Intercom should be
   feature-flagged behind `enable-intercom`.
5. **Intercom App ID** — Dev: `mxl90k6y`, Prod: `w29sqomy` (shared across all
   LFX apps; already set in Step 3 — just confirm the user hasn't been given
   different IDs by the Intercom admin).

---

## Step 2 — Audit Existing Integration

Search the repo for any existing Intercom integration before writing any code.
Check all of the following and produce a gap report:

| Check | What to look for | LFX Standard |
|---|---|---|
| **IntercomService** | Does `intercom.service.ts` exist? | Direct script injection, `isLoaded` + `isBooted` + `isLoading` state, `boot()` returns `Promise<void>` |
| **npm package** | `@intercom/messenger-js-sdk` or similar in `package.json` | ❌ Not allowed — use script injection |
| **Intercom stub** | Does `initializeIntercomFunction()` create the `i.q` stub? | ✅ Required — queues commands before script loads |
| **JWT pre-set** | Is `window.intercomSettings.intercom_user_jwt` set *before* `window.Intercom('boot')` is called? | ✅ Required |
| **JWT stripped from boot options** | Is `intercom_user_jwt` removed from the options passed to `window.Intercom('boot')`? | ✅ Required — JWT only in `intercomSettings`, not boot payload |
| **Auth-only boot** | Is `boot()` called only inside an authenticated user block, with `intercomBootAttempted` guard? | ✅ Required |
| **Shutdown on logout** | Is `Intercom('shutdown')` called and JWT cleared on logout? | ✅ Required |
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
  app_id: string;
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

  /**
   * Boot Intercom with user data. Returns a Promise so the caller can handle
   * failures (e.g. reset an intercomBootAttempted flag on rejection).
   */
  public boot(options: IntercomBootOptions): Promise<void> {
    return new Promise((resolve, reject) => {
      if (typeof window === 'undefined') {
        reject(new Error('Window is undefined'));
        return;
      }

      if (!environment.intercomId) {
        console.info('Intercom: Disabled (no intercomId configured in environment)');
        reject(new Error('No Intercom ID configured'));
        return;
      }

      if (this.isBooted) {
        // Already booted — update instead. Strip JWT and system fields.
        const { intercom_user_jwt: _jwt, app_id: _appId, api_base: _apiBase, ...userOptions } = options;
        this.update(userOptions);
        resolve();
        return;
      }

      // Kick off script loading (deferred to here to ensure authenticated-only loading)
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
            const { intercom_user_jwt: _jwt, app_id: _appId, api_base: _apiBase, ...userOptions } = options;
            this.update(userOptions);
            resolve();
            return;
          }

          // Set flag before calling boot() to prevent concurrent calls from racing
          this.isBooted = true;

          try {
            // Strip JWT from boot options — it's already in window.intercomSettings
            const { intercom_user_jwt: _jwt, ...bootOptions } = options;

            window.Intercom('boot', {
              api_base: environment.intercomApiBase,
              ...bootOptions,
            });

            // Force update to ensure user attributes are applied
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
        } catch (error) {
          console.error('IntercomService: Shutdown failed', error);
        }
      }
    }
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

In `app.component.ts`, add `private intercomBootAttempted = false;` as a class
field, then wire boot/shutdown into the auth subscription:

```typescript
// Class field
private intercomBootAttempted = false;

// In constructor or ngOnInit, inside auth.userProfile$ subscription:
if (userProfile) {
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
} else if (userProfile === undefined) {
  // Logout — clear Intercom session
  if (this.intercomBootAttempted) {
    this.intercomService.shutdown();
    this.intercomBootAttempted = false;
  }
}
```

The `intercomBootAttempted` flag is essential — `userProfile$` can emit multiple
times and without the flag Intercom will attempt to boot on every emission.

If the app uses **LaunchDarkly**, wrap the boot block:
```typescript
if (this.ldClient.variation('enable-intercom', false)) {
  // ... boot block above ...
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
2. Log in and check that the Intercom chat bubble appears
3. Open browser console and run: `window.Intercom('getVisitorId')` — should
   return a string, not an error
4. Log out and confirm the bubble disappears
5. Decode the Auth0 ID token and confirm `http://lfx.dev/claims/intercom` is
   present (if Auth0 change is deployed)
6. In Intercom dashboard, confirm the user appears with correct name/email

---

## Keeping This Skill Up to Date

**Canonical reference app**: LFX Mentorship (`jobspring` / `lfx-mentorship-upgrade`
repo) is the source of truth for the LFX Intercom pattern. When in doubt about
what "correct" looks like, check how Mentorship implements it — Crowdfunding and
PCC follow the same pattern and can be used for cross-validation.

**If you find this skill is outdated**: Update `SKILL.md` in the same PR where
you fix the app. Do not defer it. The skill is wrong for everyone until it's
fixed.

**Last validated**: 2026-03 against LFX Mentorship, Crowdfunding, and PCC.

---

## Notes

- **Do not use an npm Intercom package** — LFX uses direct script injection
  consistently across all apps. Keep it consistent.
- **The HMAC claim** (`https://sso.linuxfoundation.org/claims/intercom`) is
  deprecated — the JWT claim (`http://lfx.dev/claims/intercom`) is current. Use
  only the JWT claim in your Angular code.
- **Shared App IDs**: Dev (`mxl90k6y`) and Prod (`w29sqomy`) are shared across
  all LFX apps. Do not create a new Intercom workspace.
- **Identity verification is mandatory** — do not boot Intercom without the JWT.
  Booting without it allows users to impersonate others in Intercom.
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
  frame-src    https://*.intercom.io https://*.intercom-messenger.com
  media-src    https://js.intercomcdn.com
  ```
