# Account List (Code App) — Memory Bank

Experiment: the account list from the assignment (`azure/AccountAcquisition.Web`, ASP.NET Core MVC on Azure) rebuilt as a Power Apps code app. The MVC app stays the assignment's answer.

## Project

- Path: `apps/account-list/` (relative to the repo root)
- App name: Account List (Code App)
- Environment: Luka-TechnicalAssigment (`94faa566-3cbc-e90a-8866-bff29ec30448`), Dataverse `https://org888c7c34.crm17.dynamics.com`
- Solution: `BeTernaAccountAcquisition` (solution ID `3a8882e2-c5dd-f111-84e8-e4fade0da3ee`) — push with `--solution-id`
- CLI Binary: `pa` (`npx --no-install pa`)
- CLI Version: 1.4.1 (`PA_INLINE_CONNECTIONS=yes`)
- App ID: `3df905c4-1305-486d-b0c7-2f1e40c41397` (in solution BeTernaAccountAcquisition, component type 300)
- App URL: https://apps.powerapps.com/play/e/94faa566-3cbc-e90a-8866-bff29ec30448/app/3df905c4-1305-486d-b0c7-2f1e40c41397
- Version: 1.0.0 (`src/version.ts`, shown in the header; increase on each push)

## Decisions

- Contact-information columns come from a new Dataverse environment variable `lrw_ContactInfoColumns` (in the solution); missing/empty = error, never a guessed list.
- Theme: dark.
- Same behaviour as the MVC app: active accounts sorted by `accountnumber`, `name`; orange = no active contacts; red = at least one active contact with none of the configured columns filled; Reload; loaded time; error panel; incomplete warning; version shown in the UI.
- Data is read as the signed-in user via the Dataverse connector (users need Power Apps Premium and read on Account/Contact).

## Completed Steps

- [x] Prerequisites (Node v24.20.0, Git 2.55)
- [x] Scaffold (npx degit, npm install, power-apps-cli dev dependency)
- [x] Initialize (`pa app init`; `power.config.json` environmentId verified)
- [x] Baseline build (`npm run build`)
- [x] Baseline deploy (after enabling **Power Apps code apps → Enable code apps** in the admin center; took a few minutes to apply)
- [x] Environment variable `lrw_ContactInfoColumns` (definition `9ca054f5-1be1-f111-84e8-e4fade0da3ee`, Text, default = the 8 columns, in the solution); added to `deployment/settings/deploymentSettings.test.json` / `.prod.json`
- [x] Data sources: account, contact, environmentvariabledefinition, environmentvariablevalue (Dataverse connector, no connection needed)
- [x] Implement app: `src/constants/dataverse.ts`, `src/domain/accountStatus.ts`, `src/data/loadAccounts.ts`, `src/components/{AccountTable,Legend,ErrorPanel}.tsx`, `src/App.tsx`, dark theme; build + lint clean; rule checked with Node (12 checks)
- [x] Final build and deploy: v1.0.0 pushed 2026-11-15 (user confirmed)
- [ ] Verify in the browser: 8 accounts sorted ACC-00001…ACC-00008, ACC-00007 orange, ACC-00008 red; Reload; env variable change takes effect without redeploy
- [ ] Solution export + commit (ask first)

## Notes

- Sign-in: `npx --no-install pa auth login` (browser). Device-code sign-in is blocked by the tenant (AADSTS530035).
- npm skips esbuild's install script by default; the build works without it.
