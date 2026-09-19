# Tools/

Build, publish and BC-session tooling for the Alvys AL projects.

**Any new build/publish/automation script goes in this folder, not beside the AL projects.**

## Scripts

| Script | Purpose |
| --- | --- |
| `bc-publish.sh [project-path]` | Compile with `alc` and publish to the sandbox dev endpoint. Defaults to the App project. |
| `bc-symbols.py [project-path]` | Download `.app` symbols into the project's `.alpackages`. Defaults to the App project. |
| `bc_auth.py` | OAuth device-code flow with a persistent token cache. `get_access_token()` is imported by the two scripts above. |
| `project_paths.py` | Resolves `TOOLS`, `REPO` and `PROJECT_ROOT`. Use it for anything kept out of git. |
| `alvys-e2e.py [manual\|jobqueue\|both\|resume\|reset] [--auto-post off\|on\|both]` | Drives the chained Fleetrock -> BC -> Alvys -> poll test, settling the deduction in the Alvys UI between phases. With no arguments it runs two chains: Manual poll with Fleetrock auto-post off, and Job Queue poll with it on. |
| `alvys-e2e-statements.py [7777\|TEST420]` | Statement-date chain: three repair orders on the truck, paid in the Alvys UI whole, split once and split twice over three pay periods, then checks each part's payment date in BC and the invoice/Fleetrock paid dates. Uses up three pay periods on the truck per run. |
| `alvys_api.py` | Alvys public API client (token, deduction reads, `wait_until_paid`). |
| `alvys_ui.py` | Playwright helpers for the Alvys web UI: `settle_truck_deductions` settles a truck's whole Open tab, `settle_rows` only the rows named, and `split_deduction` splits a row in two. |
| `bc_session.py` | Shared Playwright helpers for the BC web client; re-authenticates automatically when the saved session expires. |
| `bc_browser.py`, `bc_click.py`, `bc_probe.py`, `bc_action_msg.py`, `bc_action_details.py`, `bc_err_probe.py`, `bc_err_copy.py` | Ad-hoc helpers for driving and inspecting BC pages while debugging. |
| `.upload_server.py` | Small HTTP upload server, writing into the project root. |

## Paths

Scripts live in the repo, but the things they read that must **not** be version controlled —
the `.bcprofile` and `.alvysprofile` browser profiles, `BC_credentials.txt`, the Alvys API keys,
the MSAL token cache, and any screenshots they write — live in the project root *above* the
repository. Import `PROJECT_ROOT` from `project_paths.py` for those rather than deriving a
path from `__file__`; `REPO` in the same module is where the AL projects are.

## Testing

Publish the test app, then run `bc-run-tests.py`. It posts to the test-run API page (89952),
which runs the suite synchronously, and prints the summary plus per-method detail read back from
the test-result API page (89953). `--keep-data` runs without rollback, leaving the documents in
BC and the repair order and deduction in Fleetrock and Alvys for inspection.

**Always run the suite through this script, not the web client.** Page 89951 "Alvys Test Results"
and its **Run Tests** action still exist for interactive use, but driving it with Playwright is
slow, needs a rendered session, and reports results only as a screenshot. Likewise, don't
reintroduce the old Playwright drivers for the AL Test Tool (page 130401).

Nothing external seeds, adjusts or inspects the data before or after a run.
