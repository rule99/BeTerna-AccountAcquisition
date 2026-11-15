# Project context prompt

Paste everything below the line into a new AI coding session opened at the repository root. Paths are relative to the repo root. Identifiers below (tenant, subscription, app IDs) are not secrets.

---

You are joining an existing, working project. Before changing anything, read `CLAUDE.md` (project rules: they override your defaults), then this summary. Verify anything time-sensitive (deployed state, data, settings) against the live system before relying on it.

## 1. What this is

An interview assignment for BE-terna: an **ASP.NET Core MVC web app (.NET 10) hosted on Azure** that lists **active Dynamics 365 accounts** (Account ID, name, address, number of related active contacts) read through **web services** (Dataverse Web API). "WS" in the brief means web services, not WebSockets. Data loads with the page and again on a manual **Reload** button.

- **Orange:** the account has no active contacts.
- **Red:** at least one active contact has **none** of the contact-information columns filled: `emailaddress1, telephone1, mobilephone, fax, address1_line1, address1_city, address1_postalcode, address1_country`. Job title deliberately does not count. Null, missing or whitespace-only = empty.
- **Account ID** = `account.accountnumber` (autonumber `ACC-{SEQNUM:5}`, alternate key `lrw_AccountNumber`). The list is sorted by `accountnumber`, then `name`.
- Sign-in: Entra ID via App Service Authentication (Easy Auth), open to anyone in the tenant. All users see the same data (one app identity reads it).

## 2. Architecture

```
Browser --Entra sign-in (Easy Auth, session cookie)--> App Service (Windows F1, MVC app, system managed identity)
        --Bearer token for api://<accounts-api-app-id> (web app identity)--> API Management (Consumption)
             checks tenant + audience + caller oid, rewrites to ONE fixed Dataverse query
        --Bearer token for Dataverse (APIM managed identity)--> Dataverse Web API v9.2
             APIM identity = application user with security role "Account Acquisition API Reader" (read Account + Contact only)
Telemetry: web app (Microsoft.OpenTelemetry) + APIM logger -> Application Insights -> Log Analytics; one trace per click.
```

No secrets anywhere: both service calls use managed identities; the two Entra app registrations are identifiers only (web sign-in with ID token only; accounts API = token audience).

## 3. Repository map

| Path | Contents |
|---|---|
| `CLAUDE.md` | Project rules (prefix `lrw`, solution `BeTernaAccountAcquisition`, constants rules, ALM, commit rules) |
| `README.md` | Setup, ALM, Azure deploy steps, web app commands |
| `azure/infra/main.bicep` | All Azure resources (tags on all), APIM API/operation/named values/logger, App Service + Easy Auth (`authsettingsV2`) |
| `azure/infra/main.<env>.bicepparam` | Per-environment values (`dev` filled; `test`/`prod` have placeholders) |
| `azure/infra/policies/get-accounts.xml` | The APIM policy (token check, fixed query, managed-identity call, headers) |
| `azure/scripts/Deploy-Azure.ps1` | Providers → resource group → app registrations → Bicep → optional `-WebProject` publish |
| `azure/AccountAcquisition.slnx` | Solution: web app + tests |
| `azure/AccountAcquisition.Web/` | The MVC app (details in section 5) |
| `azure/AccountAcquisition.Web.Tests/` | 45 xUnit tests (rules, parser contract, real recorded response, Easy Auth guard) |
| `Solutions/BeTernaAccountAcquisition/` | Unpacked Dataverse solution: the role, the account alternate key, the autonumber on `accountnumber` |
| `deployment/scripts/` | `Export-Solution.ps1`, `Pack-Solution.ps1`, `Import-Solution.ps1` |
| `out/demo-data/` | Git-ignored: scripts that created/remove demo records and revert a contact edit |
| `apps/account-list/` | Experiment, not the assignment: the same list as a Power Apps code app (React/TS, Dataverse connector as the signed-in user, contact columns from env variable `lrw_ContactInfoColumns`). See its `memory-bank.md` |

## 4. Environments and identifiers (dev)

| Item | Value |
|---|---|
| Dataverse | `https://org888c7c34.crm17.dynamics.com` (Switzerland), solution `BeTernaAccountAcquisition`, prefix `lrw` |
| Entra tenant | `d9174be4-62fc-4263-8e3d-f32203ee075e` |
| Azure subscription | `307137be-d00d-45f4-83c2-b5485485acca` (two subscriptions share the name "Azure subscription 1": select by ID) |
| Resource group | `rg-beterna-accounts-dev`, **Sweden Central** |
| Resources | `app-`, `asp-`, `apim-`, `appi-`, `log-beternaaccou-dev` |
| Web URL | `https://app-beternaaccou-dev.azurewebsites.net` |
| APIM operation | `https://apim-beternaaccou-dev.azure-api.net/crm/accounts` |
| App registrations | `beternaaccou-web-dev` (appId `b5d1faaf-1a62-4e6f-bf09-4bfa3682fec8`), `beternaaccou-accounts-api-dev` (audience `api://782c9cde-2c4d-4273-ae0f-94efd2ed2af0`) |
| APIM managed identity (Dataverse application user) | Application ID `42a81299-49de-4b5d-89bf-40719632ad86` |

Region history: Switzerland North had no APIM Consumption capacity; West Europe, North Europe, Germany West Central and UK South refuse this subscription ("not accepting new customers"). Sweden Central works.

## 5. Web app internals (`azure/AccountAcquisition.Web/`)

| URL | Action | Renders |
|---|---|---|
| `/` | `Controllers/AccountsController.Index` | `Views/Accounts/Index.cshtml` in `Views/Shared/_Layout.cshtml`, with partial `Views/Accounts/_AccountTable.cshtml` |
| `/Accounts/Table` (Reload) | `AccountsController.Table` | Only `_AccountTable` (502 on load failure; never 401/403) |
| `/Error` | `Controllers/ErrorController` | `Views/Shared/Error.cshtml` |

- `Program.cs`: optional telemetry (when `APPLICATIONINSIGHTS_CONNECTION_STRING` set) → MVC → `AccountsApiOptions` bound and validated at startup (`AccountsApi:BaseUrl` https, `Scope`, `TimeoutSeconds`) → sample mode (Development only) **or** `ManagedIdentityCredential(SystemAssigned)` + typed `HttpClient<IAccountSource, ApiAccountSource>` with `ManagedIdentityHandler` → pipeline: `UseEasyAuthGuard` first, exception handler/HSTS outside Development, HTTPS redirect, routing, `MapStaticAssets`, default route `Accounts/Index`.
- `Services/IAccountSource` is the repository: `ApiAccountSource` (real; requires the `X-Contact-Info-Columns` response header) and `SampleAccountSource` (reads `SampleData/accounts.json`, an envelope `{ contactInfoColumns, response }` in the real Dataverse shape).
- `Services/AccountListParser` (contract checks, address on one line, "incomplete" only for a top-level `@odata.nextLink` or an account with ≥ 5,000 contacts) and `Services/AccountStatusRules` (`Evaluate`, `HasContactInformation` against the configured columns only).
- `Auth/ManagedIdentityHandler` (adds Bearer token), `Auth/EasyAuthGuard` (outside Development, `WEBSITE_AUTH_ENABLED` not `True` → 503 for every request), `Auth/EasyAuthHeaders`.
- `Constants/`: `Account`, `Contact` (Dataverse names), `ConfigKeys`, `AccountsApiRoutes`, `AccountsApiHeaders`. Never write literal schema names or config keys elsewhere; never reuse a Dataverse constant for a non-Dataverse value.
- `wwwroot/js/accounts.js`: Reload via `fetch` (`X-Requested-With`, `redirect: manual`); 401/403/opaque redirect → full page reload; localizes the UTC time.

## 6. APIM policy and named values

Policy (`azure/infra/policies/get-accounts.xml`): `validate-azure-ad-token` (tenant, audiences `{{accounts-api-audience}}`/`{{accounts-api-client-id}}`, required claim `oid` = `{{webapp-principal-id}}`) → `set-backend-service {{dataverse-url}}/api/data/v9.2` → `rewrite-uri` fixed query (`$select=accountid,accountnumber,name,address1_composite`, active accounts, `$orderby=accountnumber asc,name asc`, `$expand=contact_customer_accounts($select=contactid,{{contact-info-columns}};$filter=statecode eq 0)`, `copy-unmatched-params=false`) → delete incoming `Authorization` → `authentication-managed-identity resource={{dataverse-url}}` → OData headers + `If-None-Match: null` → outbound header `X-Contact-Info-Columns: {{contact-info-columns}}`.

Named values: `tenant-id`, `dataverse-url` (single source for destination and token target), `accounts-api-audience`, `accounts-api-client-id`, `contact-info-columns`, `webapp-principal-id`, secret `appinsights-connection-string` (Bicep-owned, for APIM's logger; avoids auto-created `Logger-Credentials-*` values).

## 7. Lessons learned (don't rediscover these)

- Dataverse adds columns nobody selected to each expanded contact (`_parentcustomerid_value`, `address1_composite`). Never treat "any returned column" as contact information; use the configured list.
- A single-level `$expand` always carries `<nav>@odata.nextLink` returning the same rows: not a sign of missing data.
- Expanded collections may be served from a Dataverse cache: send `If-None-Match: null`.
- Easy Auth answers XHR without a session with 401/403, not a redirect. Microsoft sign-in refuses to load inside frames (embedded browsers show "Unsafe attempt to load URL").
- App Service's codeless App Insights agent needs extra settings on ASP.NET Core; telemetry is code-based instead and `ApplicationInsightsAgent_EXTENSION_VERSION` was removed.
- Contact has no documented Entra object ID column: `externaluseridentifier` exists but is undocumented; Power Pages (installed) has `adx_externalidentity`.
- Microsoft's "AI for Sales" contact form is not exported by "include all objects" and is intentionally not in the solution.
- Tooling on Windows: Windows PowerShell 5.1 reads `.ps1` without BOM as ANSI (keep scripts ASCII); in Git Bash pass paths with `/`, not `\`; Azure CLI may demand MFA again (`az login --tenant <tenant>`, and `--scope https://org888c7c34.crm17.dynamics.com/.default` for Dataverse tokens).
- Test APIM as the web app identity through the Kudu command API (`https://app-beternaaccou-dev.scm.azurewebsites.net/api/command`, using `IDENTITY_ENDPOINT`/`IDENTITY_HEADER`). After deleting and recreating resources, the portal list (Resource Graph) can lag.

## 8. Current state and open items

- Everything is deployed to dev and merged to `master` (PRs #1–#3). Live check: 8 accounts, ACC-00001…ACC-00008.
- **Demo data in dev:** ACC-00007 "Demo - No Contacts" (orange) and ACC-00008 "Demo - Missing Contact Info" with contacts Mia Complete / Noah Incomplete (red). Remove after the presentation with `out/demo-data/Remove-DemoAccounts.ps1` (git-ignored; if the folder is missing on this machine, delete those two accounts and two contacts by hand).
- **Kudu/FTP basic-auth deployment credentials are ON** (verified 2026-11-15). Proposed fix, not yet done: `basicPublishingCredentialsPolicies` (`scm`, `ftp`) with `allow: false` in `main.bicep`, then redeploy.
- All endpoints are public; identity protects each hop. Dataverse IP firewall is off.
- **The dev Dataverse environment is a Dynamics 365 trial that ends 2026-12-10**; check billing shows "Expires" (not "Renews"). Trial data is deleted after expiry: the solution is in the repo; demo data would need recreating.
- No CI pipeline; tests run locally. `test`/`prod` bicepparam files still have placeholders.
- Code app experiment "Account List (Code App)" is deployed to dev (app ID `3df905c4-1305-486d-b0c7-2f1e40c41397`) and in the solution with env variable `lrw_ContactInfoColumns`. Code apps had to be enabled per environment (admin center → Settings → Product → Features). Redeploy: raise `src/version.ts`, then `npm run build && npx --no-install pa app push` in `apps/account-list`. The Power Apps CLI signs in with `npx --no-install pa auth login` (browser; device code is blocked by the tenant).

## 9. Documents (Claude Docs)

- Infrastructure Guide: https://claude.ai/artifact/WgxVyccnxFuVDoL1E8RZ8Q
- Solution Design (Larman method, for the panel): https://claude.ai/artifact/3XFstnNbE6n8NuiT22TNEs
- Cheat Sheet (code walkthrough + interview Q&A): https://claude.ai/artifact/X1oYiJNMphshSQb58csdNM

## 10. Useful commands

```powershell
dotnet test azure\AccountAcquisition.slnx
dotnet run --project azure\AccountAcquisition.Web --launch-profile SampleData      # https://localhost:7180
.\azure\scripts\Deploy-Azure.ps1 -Environment dev -ResourceGroup rg-beterna-accounts-dev -WebProject azure\AccountAcquisition.Web
.\deployment\scripts\Export-Solution.ps1 -SolutionName BeTernaAccountAcquisition   # bumps the dev version afterwards
pac admin assign-user --environment <dataverse-url> --user <apim-app-id> --role 'Account Acquisition API Reader' --application-user
```

## 11. Working conventions with this user

- Explain briefly before acting; prefer small targeted edits; ask before deleting files.
- Schema changes (tables, columns, keys, roles) need explicit approval: propose first.
- Branch per change (`feature/...`), detailed commit messages, **no `Co-Authored-By` trailer**, push and open a PR; the user merges, then `master` is pulled.
- Every Azure resource is tagged in Bicep; no secrets in the repo; managed identity preferred.
- Verify platform behaviour against Microsoft Learn rather than memory, and report what was actually tested.
