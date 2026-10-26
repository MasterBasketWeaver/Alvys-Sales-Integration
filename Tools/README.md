# Tools/

Build, publish and BC-session tooling for the Alvys AL projects.

**Any new build/publish/automation script goes in this folder, not beside the AL projects.**

## Scripts

| Script | Purpose |
| --- | --- |
| `bc-publish.sh [project-path]` | Compile with `alc` and publish to the sandbox dev endpoint. Defaults to the App project. |
| `bc-publish-pte.py <project-path> [--force-sync] [--define SYMBOLS]` | Compile with `alc` (with `--define`, those preprocessor symbols), or reuse the kept build of that version in `<project>/output/` (`output/<symbols>/` with `--define`), and install as a per-tenant extension through the automation API's `extensionUpload`, uninstalling and unpublishing a dev copy of the same app first. Needs a version never uploaded before: BC refuses an app id + version it has already received, even after it was unpublished. Every uploaded build is kept there read-only; `--app <file> [--keep-dir DIR]` uploads a given build. |
| `bc-publish-tests-production.py [--force-sync]` | Build the test app with the `PRODUCTION` preprocessor symbol and install it as a PTE in `BC_ENV` (default `Production`). Regenerates codeunit "BAASIT Test Dispatch" from the `[Test]` procedures first; see *Testing in production* below. |
| `bc-symbols.py [project-path]` | Download `.app` symbols into the project's `.alpackages`. Defaults to the App project. |
| `bc_auth.py` | OAuth device-code flow with a persistent token cache. `get_access_token()` is imported by the two scripts above. |
| `project_paths.py` | Resolves `TOOLS`, `REPO` and `PROJECT_ROOT`. Use it for anything kept out of git. |
| `alvys-e2e.py [manual\|jobqueue\|both\|resume\|reset] [--auto-post off\|on\|both]` | Drives the chained Fleetrock -> BC -> Alvys -> poll test, settling the deduction in the Alvys UI between phases. With no arguments it runs two chains: Manual poll with Fleetrock auto-post off, and Job Queue poll with it on. |
| `alvys-e2e-statements.py [7777\|TEST420]` | Statement-date chain: three repair orders on the truck, paid in the Alvys UI whole, split once and split twice over three pay periods, then checks each part's payment date in BC and the invoice/Fleetrock paid dates. Uses up three pay periods on the truck per run. |
| `alvys_api.py` | Alvys public API client (token, deduction reads, `wait_until_paid`). |
| `alvys_ui.py` | Playwright helpers for the Alvys web UI: `settle_truck_deductions` settles a truck's whole Open tab, `settle_rows` only the rows named, and `split_deduction` splits a row in two. An expired session signs itself back in from `cred` (`alvys-web-user`, `alvys-web-password`). |
| `alvys-login.py [code]` | Signs the `.alvysprofile` profile in with an authenticator code, ticking "Remember this device for 30 days". Only needed when that 30 days lapses and Alvys asks for a code again. |
| `bc_session.py` | Shared Playwright helpers for the BC web client; re-authenticates automatically when the saved session expires. |
| `bc_browser.py`, `bc_click.py`, `bc_probe.py`, `bc_action_msg.py`, `bc_action_details.py`, `bc_err_probe.py`, `bc_err_copy.py` | Ad-hoc helpers for driving and inspecting BC pages while debugging. |
| `.upload_server.py` | Small HTTP upload server, writing into the project root. |

## Paths

Scripts live in the repo, but the things they read that must **not** be version controlled —
the `.bcprofile` and `.alvysprofile` browser profiles, the MSAL token cache, and any
screenshots they write — live in the project root *above* the
repository. Import `PROJECT_ROOT` from `project_paths.py` for those rather than deriving a
path from `__file__`; `REPO` in the same module is where the AL projects are.

BC, Alvys and Fleetrock passwords and API keys are in `cred` (`~/.local/bin/cred`), read through
`bc_session.cred_get`: `alvys-web-user` / `alvys-web-password` for app.alvys.com,
`alvys-api-rw-client-id` / `-secret` (read-write) and `alvys-api-ro-*` (read-only) for the Alvys
API, `alvys-bc-user` / `alvys-bc-password` for the BC web sign-in, and
`fleetrock-test-customer-*` / `fleetrock-test-vendor-*` (`-user`, `-password`, `-api-key`) for
test.fleetrock.com. `fleetrock-customer-*`, `fleetrock-vendor-*` and `fleetrock-admin-*` are the
www.fleetrock.com accounts.

## Testing

The test scripts (`bc-run-tests.py`, `alvys-e2e.py`, `alvys-e2e-statements.py`) run in the company
**Alvy's Test**; set `BC_COMPANY` to run them elsewhere (e.g. `Texas Transportation Group`), as
`BC_ENV` does for the environment.

Publish the test app, then run `bc-run-tests.py`. It posts to the test-run API page (89952),
which runs the suite synchronously, and prints the summary plus per-method detail read back from
the test-result API page (89953). `--keep-data` runs without rollback, leaving the documents in
BC and the repair order and deduction in Fleetrock and Alvys for inspection.

**Always run the suite through this script, not the web client.** Page 89951 "Alvys Test Results"
and its **Run Tests** action still exist for interactive use, but driving it with Playwright is
slow, needs a rendered session, and reports results only as a screenshot. Likewise, don't
reintroduce the old Playwright drivers for the AL Test Tool (page 130401).

Nothing external seeds, adjusts or inspects the data before or after a run.

To read or edit the Alvys Sales Setup from a script, use the test app's setup API page (89960):
`GET`/`PATCH .../api/bryana/alvys/v1.0/companies({companyId})/alvysSalesSetups({id})`, and `POST
...alvysSalesSetups({id})/Microsoft.NAV.refreshAccessToken` for the card's Refresh Access Token.
`clientSecret` is write-only (always reads back blank; `clientSecretSet` says whether one is stored).

## Testing in production

Business Central runs `Subtype = Test` and `TestRunner` codeunits only in sandboxes; in a production
environment the run fails with *Test Automation is not enabled on this system*, and Microsoft's test
framework (Library Assert and the rest) is not meant to be installed there. The test app therefore has
one source and two builds, chosen with the `PRODUCTION` preprocessor symbol (`alc /define:PRODUCTION`,
which `bc-publish-tests-production.py` passes):

- The test codeunits wrap `Subtype = Test`, `TestPermissions` and each `[Test]` attribute in
  `#if not PRODUCTION`, so in production they are ordinary codeunits with the same test bodies.
- Assertions go through codeunit "BAASIT Assert" in both builds, and expected errors are checked with
  `[TryFunction]` wrappers rather than `asserterror`, so neither build depends on the test framework.
- The three test runners exist only in the sandbox build. In production, `TestRunMgt` runs the same
  codeunit lists through "BAASIT Production Test Runner", which runs each method in its own
  `Codeunit.Run` and logs it to the same result table, so `bc-run-tests.py` works unchanged
  (`BC_ENV=Production`).
- A passing method is rolled back by ending in an error, which is finer than the sandbox's
  per-codeunit isolation, but anything a test commits stays in the company. `--keep-data` skips the
  rollback as it does in the sandbox.

Add a test as usual, with the `#if not PRODUCTION` / `[Test]` / `#endif` lines around its attribute;
the dispatch codeunit is regenerated on the next production publish. Give each production upload its
own version: BC refuses a different file under an app id + version it has already received.

