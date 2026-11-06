# Ayam Secure Secrets: release pipeline design

**Status:** proposal, written 2026-11-06. Nothing here is built yet. Section 11 lists what has been
verified and what still needs a spike. This file lives in the `secrets` fork for now and moves to
the new build repo in Batch 1.

## 1. Summary

The current process needs three forks, a manual checklist with line numbers, and an x86 machine with
16GB of RAM. The proposal replaces that with one small repo on Forgejo that holds only what is
different from upstream, and a scheduled Forgejo Actions workflow that turns each upstream release
into a tested multi-arch image and an alert.

| Question | Answer |
| --- | --- |
| Must the forks live on GitHub? | No. |
| Must they be public? | Effectively yes for the source your users are owed, because the server is AGPL and you run a modified copy for remote users. Forgejo cannot serve that today, so keep one public read-only mirror. See section 3. |
| Can everything move to Forgejo, images included? | Yes, with three conditions: replica restore must not depend on agonda, CI must not starve prod, and prod and the replica must be able to reach the registry. See section 4. |
| Is there a better way to patch than merging and checking line numbers? | Yes. Build from a pristine upstream tag plus a patch stack and overlay files. Nothing is merged, so there is nothing to re-verify by hand. See section 5. |
| Why does multi-arch fail? | `build-images.sh` forces `TARGETARCH` and `TARGETVARIANT`. Remove both and one `--platform linux/amd64,linux/arm64` build works, as it does upstream. See section 7. |
| Should the patches change? | Drop four, add four, and stop hiding the disclaimer. See section 6. |

**Do first, independent of all this:** vaultwarden 1.37.5 shipped on 2026-11-01 with two Medium
security fixes and web vault v2026.10.1. This repo is on 1.37.4 with web vault 2026.7.0. The 1.37.5
notes warn that a self-served web vault older than v2026.7.1 "might have compatibility issues", and
that invalid config values now stop startup. Build that one by hand with the existing process rather
than waiting for the pipeline, and test it on staging as usual.

## 2. Where things stand today

Upstream cadence is why this is worth automating: six releases between 2026-07-24 and 2026-11-01,
and three of them (1.37.0, 1.37.4, 1.37.5) carried 19 advisories between them, one rated High (8.1).

Findings from reading the repos:

- **The web vault version rule has drifted.** `README_Ayam-Secrets-Web.md` says to use the version in
  the latest `bw_web_builds` release that is not a pre-release. v2026.8.0 was flagged as a pre-release
  there, so you stayed on 2026.7.0, yet upstream 1.37.4 pinned `v2026.8.0` as its bundled vault. The
  authority is the server repo itself: `docker/DockerSettings.yaml` holds both `vault_version` and
  `vault_image_digest`, and CI should read those two values.
- **`docker/Dockerfile.ayam` differs from `Dockerfile.alpine` by one line**, the `FROM ... AS vault`
  line. That whole "compare after merging" step exists to carry one image reference.
- **Two layers of customisation sit outside all three repos.** `./ayam-images` is bind-mounted over
  `/web-vault/images`, and `user.vaultwarden.scss.hbs` lives under `data/templates/scss` on the host
  (source copy in `jax-cloud/security/vaultwarden/custom-css`).
- **The images bind mount shadows the entire directory.** The web source has 102 files under
  `apps/web/src/images`. Anything a new web vault release adds to that directory will 404 unless it
  also exists in `./ayam-images`. Copying your files on top inside the image avoids this.
- **The CSS rebranding is positional.** `footer div:nth-last-of-type(3)` swaps the footer text by
  counting elements. If upstream adds a line to that footer it will silently hide the wrong one.
- **Patches can be missed.** The checklist cannot catch templates that upstream adds later.
  `email/change_email_invited.hbs` and its `.html.hbs` twin still say "join Vaultwarden".
- **Existing patch bug.** `admin/login.hbs` line 21 has two `class` attributes. Browsers keep the
  first, so `btn btn-primary` is ignored.
- **Stale files.** Nothing in `src`, `docker`, `build.rs` or `Cargo.toml` references `api-config.json`
  (version 2024.5.1). `docker/arm64/Dockerfile.alpine` is left over from an older patch.

All other patches in the README checklist were confirmed present in the working tree by reading the
files. The GitHub compare page reports 42 files changed against upstream but would not render the
list, so that list still has to come from a local `git diff` (Batch 1).

## 3. GitHub, public, and the licences

This is my reading of the licence texts, not legal advice. Since Ayam Secure sells this as a service,
it is worth a short review by a lawyer.

**GitHub is not required.** Nothing ties these projects to it.

**Public is more nuanced.** Vaultwarden is AGPL-3.0 (`LICENSE.txt` in this repo). Section 13 says:

> if you modify the Program, your modified version must prominently offer all users interacting with
> it remotely through a computer network (if your version supports such interaction) an opportunity
> to receive the Corresponding Source of your version by providing access to the Corresponding Source
> from a network server at no charge, through some standard or customary means of facilitating
> copying of software.

You modify it and clients use it remotely, so this applies. The duty is to your users rather than to
the whole world, so "public" is not strictly the requirement, but access has to be free and reachable
by them. Your Forgejo cannot do that as configured: `FORCE_PRIVATE=true`, `REQUIRE_SIGNIN_VIEW=true`,
and access limited by allowlist. A fully private setup would not meet section 13.

The web vault (`bw_web_builds`, `vw_web_builds`) is GPL-3.0. Minified JavaScript sent to a browser is
a copy in non-source form, so I would treat it as conveyed and owe the source to the same people. I
could not get the GPL FAQ to load to confirm the FSF's position, so this one is my inference.

Docker images are different. Nothing requires publishing them, because clients never receive them.

**Recommendation:** Forgejo holds the truth and does all the work. One public read-only GitHub repo
receives a Forgejo push mirror of the new build repo. That repo contains the patches, overlay, rebrand
rules and scripts, and `upstream.lock` pins the exact upstream commit and web vault digest for each
release. Push mirrors need no inbound access to Forgejo, so the instance stays private. The mirror
overwrites the GitHub side, which is fine for a publish-only target.

**The offer also has to be visible.** Your source is public today, but in the patches and templates I
read nothing in the product points to it. The one repo link in the web vault was repointed to the
contact page, and the CSS hides `#vw-disclaimer`. The AGPL's own appendix suggests a "Source" link for
web applications. Section 6 turns the disclaimer into that offer, and the client onboarding email and
an ayamsecure.com page should carry it too.

## 4. Moving to Forgejo

Your stack already has what this needs: Actions, a DinD runner, a package registry, and the unproxied
`direct.git.jaysan.org` route for image traffic. Your compose comment and `forgejo-runner.md` both
treat that as the registry address. Three conditions come from the fact that **prod, staging,
Forgejo, the registry and the runner all sit on agonda** (`server-ops/cronjobs/agonda-cron.sh`), while
the replica is on jibhi3.

**Condition 1: replica restore must not depend on agonda.** Docker Hub is independent of agonda today.
If agonda dies and the registry is on agonda, `docker compose up` on jibhi3 cannot pull the image at
the moment you most need it. Fix: an hourly jibhi3 cron reads `SECRETS_VERSION` from the newest
replicated `.env` and runs `docker pull`, so the image is always in the local cache. This is simpler
than keeping a second registry.

**Condition 2: CI must not starve prod.** The upstream `release` profile is `lto = "fat"` with
`codegen-units = 1`, built twice, on the box running the password manager and about 40 other
containers. Add `cpus` and `mem_limit` to `gitforge-dind` in the compose file, so a heavy build gets
killed inside DinD rather than pressuring prod. Set the values once agonda's shape is confirmed;
about half the machine is a reasonable start. If builds are too slow under that cap, use
`--build-arg CARGO_PROFILE=release-low` (thin LTO, 16 codegen units), which the Dockerfile already
supports. If that still hurts, add a second runner on an amd64 home machine.

**Condition 3: reachability and auth.** `direct.git.jaysan.org` is behind `jax-allowlist`, which
`update-allowlist.sh` populates. Confirm that agonda and jibhi3 both pass it. Packages are private, so
each host needs `docker login` with a token holding `read:package` and access to all repositories
(Forgejo's "specific repositories" tokens do not appear to support package scopes).

Also watch disk. Registry blobs land in Forgejo's `./data`, which increases `forgejo dump` size, and
BuildKit state lands in `./data-dind`. Set a package cleanup rule that keeps every tag currently
deployed, and prune BuildKit weekly as `forgejo-runner.md` describes.

## 5. The patching model

Stop maintaining forks. Treat a release as a pure function of inputs:

```
image = f(upstream tag, web vault digest, patch stack, overlay, rebrand rules)
```

Nothing is merged, so nothing can be silently lost in a merge. `patches/` becomes the exact,
reviewable statement of how you differ from upstream, replacing the README checklist.

### One repo instead of three

```
secrets-build/
├── upstream.lock          # VW_TAG, VW_COMMIT, VAULT_TAG, VAULT_DIGEST, PATCH_BASE, AYAM_REV
├── patches/server/*.patch # numbered, one concern each, independent of each other
├── overlay/
│   ├── server/            # copied over the source tree: logos, user.vaultwarden.scss.hbs
│   └── web/               # copied over /web-vault: favicon, images, logos
├── web/
│   ├── Dockerfile         # starts from upstream's web vault image by digest
│   └── rebrand.sh         # string rules with assertions
├── scripts/               # prepare-tree, refresh-patches, verify-branding, smoke, notify
├── test/                  # node:test, including rebrand.sh against a fixture
├── docs/                  # Architecture.md, UserGuide.md, this document
└── .forgejo/workflows/release.yml
```

`secrets-web` and `secrets-web-source` are no longer needed. Only their patch and images survive, as
rebrand rules and overlay files. The GitHub forks can be archived after cutover, not deleted, since
they remain the source for older releases.

### Each change goes in the lightest layer that works

| Layer | Use for | Conflict behaviour |
| --- | --- | --- |
| 1. Env var | Anything upstream exposes as config | None |
| 2. Overlay | Binary files and files that are empty placeholders upstream | None, but a replaced file stops getting upstream changes |
| 3. Patch | Edits to upstream text or code | Loud, and 3-way merge resolves most moves |
| 4. Rebrand rule | Strings in the built web vault | Loud through an assertion |

### Line numbers were never the problem

A unified diff locates a hunk by its context lines, and the line number is only a starting hint, so
files shifting around do not break a patch. Only the README's "ln 283" notes go stale. `git apply
--3way` goes further: it uses the blob hashes recorded in the patch to run a real merge when the
context has changed.

One catch for CI: 3-way needs those original blobs. A `--depth 1` clone of the new tag does not have
them, so fetch the tag the patches were last refreshed against as well (`PATCH_BASE` in the lock).

```sh
git fetch --depth 1 upstream "refs/tags/$VW_TAG:refs/tags/$VW_TAG" \
  "refs/tags/$PATCH_BASE:refs/tags/$PATCH_BASE"
git checkout "$VW_TAG"
for p in ../patches/server/*.patch; do
  git apply --3way "$p" || record_failed_patch "$p"
done
cp -R ../overlay/server/. .
```

### Failure policy: a branding conflict must not delay a security fix

Every current patch is cosmetic. So if one fails to apply, undo that patch, keep building, and flag
the failure in the alert ("READY WITH WARNINGS: built without 0003-admin-branding"). This is safe
because prod is always gated by you, and patches are independent. On a security release you can then
choose to ship a slightly unbranded email or take time to fix it. Only compile failures and smoke
test failures stop the pipeline.

### Replacing "confirm patches are still active"

`verify-branding.sh` is a deny-list, not a checklist: it reports any `Vaultwarden` left in
`src/static/templates/email/**` and in other client-visible templates, minus a short allowlist. A new
upstream template is therefore caught automatically, which the current process cannot do.

### When a patch does fail

`scripts/refresh-patches.sh <tag>` checks out the tag, applies what it can, leaves conflicts for you
to fix, regenerates the `.patch` files and updates `PATCH_BASE`. That is the only manual step left,
and only when upstream edits the same lines you did.

### Why not use `TEMPLATES_FOLDER` overrides for templates?

Vaultwarden does load overriding templates from `data/templates`, and it would remove the patches.
But an override is a full copy that silently stops receiving upstream changes, including any future
fix inside a template. A patch fails visibly when upstream touches those lines, which is what you want.
The overlay is only used for the SCSS file because upstream's copy is a 119-byte comment.

### Web vault: rebrand upstream's build instead of compiling it

Your web patch only changes strings, plus a favicon. So instead of compiling Angular, start from
upstream's published image at the digest in `DockerSettings.yaml`, copy the overlay, and edit strings:

```dockerfile
ARG VAULT_DIGEST
FROM --platform=linux/amd64 docker.io/vaultwarden/web-vault@${VAULT_DIGEST} AS upstream

FROM --platform=$BUILDPLATFORM docker.io/library/alpine:3.24 AS rebrand
COPY --from=upstream /web-vault /web-vault
COPY overlay/web/ /web-vault/
COPY web/rebrand.sh /rebrand.sh
RUN sh /rebrand.sh /web-vault

FROM scratch
COPY --from=rebrand /web-vault /web-vault
CMD [""]
```

`rebrand.sh` runs each replacement and fails if a needle is not found, so a change upstream is loud.

What this gains:

- Seconds instead of a large Angular build, and no 16GB x86 machine.
- No `npm ci` of a 1.6MB lockfile on a runner that shares a host with your password manager.
- The exact web vault upstream tested against that server release.
- Two fewer repos, and the fragile `checkout_web_vault.sh` edits go away.

What it costs: editing minified output is less tidy, and it can only change text. It cannot add an
element, so the source offer has to be a plain-text URL rather than a link.

Evidence so far: `webpack.base.js` and `webpack.config.js` have no subresource integrity or service
worker, and `contenthash` only affects filenames, so edited bundles should load. It still needs the
spike in Batch 1 to confirm the strings survive minification.

**Fallback:** if the spike fails, CI clones `vw_web_builds` at the tag, applies a patch and builds
from source, on a home amd64 runner because of the memory needed.

### Server image without `Dockerfile.ayam`

Use upstream's `docker/Dockerfile.alpine` untouched and override the `vault` stage from the command
line. Docker documents that a named context "overrides a stage called `name` when used as `FROM ...
AS name`":

```sh
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f docker/Dockerfile.alpine \
  --build-context vault=docker-image://$REGISTRY/$OWNER/ayam-secrets-web@$WEB_DIGEST \
  --build-arg VW_VERSION="$VW_TAG" \
  --build-arg DB=postgresql,enable_mimalloc \
  --provenance=false \
  -t "$REGISTRY/$OWNER/ayam-secure-secrets:$TAG" \
  --push .
```

The Docker docs do not show this combined with multiple platforms and an `AS` stage pinned to
`linux/amd64`, so it needs testing. Fallback: replace that one `FROM` line with `sed` and assert that
exactly one line changed.

**Tag format:** `1.37.5-2026.10.1-ayam.1`, with the trailing number bumped for patch-only rebuilds.
There are no more `-arm64` and `-amd64` tags.

## 6. Patch audit

### Keep

- Email templates: subjects, passcode wording, header, footer link, web vault wording.
- `404.hbs` and `admin/base.hbs` branding.
- The three images, moved to the overlay rather than binary patches.
- All five web vault changes (TOTP issuer, titles, `alt`, manifest, help link), as rebrand rules.
- `mail.rs`, removing the unused `mail-github.png` attachment. Setting `SMTP_EMBED_IMAGES=false` would
  remove this patch too, but the logo would become a remote image that many mail clients block by
  default, so I would keep the patch.

### Drop

| Patch | Why |
| --- | --- |
| `src/api/web.rs` `mail-github.png` route | No user effect once `mail.rs` stops attaching it. It only leaves a small icon servable. |
| `admin/users.hbs` Invite User moved to top | Structural change on a page only you see. Highest conflict risk for no client value. |
| `admin/login.hbs` tweaks | Admin-only, and it contains the `class` bug. Reverting fixes that. |
| `email_footer.hbs` font sizes | Keep the link change. The font edits touch several very long inline-style lines, so they are the noisiest hunks. Optional, since clients do see them. |

Also delete `Dockerfile.ayam`, `build-images.sh`, `api-config.json` and `docker/arm64/`. They do not
carry over to the new repo.

### Add

- **`change_email_invited.hbs` and `.html.hbs`:** still say "join Vaultwarden".
- **`INVITATION_ORG_NAME=Ayam Secure Secrets`:** the default is `Vaultwarden` and it names the org in
  invitation emails sent from the admin panel, which is how clients join. It is not in the compose
  files, so check the host `.env`. This is env only, no patch.
- **Web vault loading screen:** `app.component.html` has `alt="Vaultwarden"`.
- **Footer text:** move "Vaultwarden Web" → "Ayam Secure Secrets Web Vault" from the positional CSS to
  a rebrand rule, then delete those CSS rules.

### Change: stop hiding the disclaimer

`#vw-disclaimer { display: none }` removes "Vaultwarden is not associated with the Bitwarden project
nor Bitwarden Inc." I would keep a version of it, because it protects you as much as upstream: a paid
service built on Bitwarden clients benefits from saying plainly that it is not affiliated, and it is
the natural home for the source offer. Rewrite it with a rebrand rule to something like:

> Ayam Secure Secrets is a modified version of Vaultwarden and the Bitwarden® Web Vault. Not affiliated
> with Bitwarden Inc. Source: github.com/ayamsecure/secrets-build

### Do not patch

- `/vw_static/*` filenames and `vaultwarden-*` image names, which are internal paths.
- `src/http_client.rs` user agent, the `ACTING_ADMIN_USER` constant, the SSO `sub`, and log lines.
- Upstream links in `admin/diagnostics.hbs` and `admin/settings.hbs`, which are useful and admin-only.
  The diagnostics version check also keeps working because `VW_VERSION` stays the upstream version.
- The `version` field in `/api/config`, which clients use for compatibility decisions.

`server.name` and `server.url` in `/api/config` are optional. The web vault only null-checks them, so
the benefit depends on whether the Bitwarden apps display them, which I could not check from this
source. Leave them unless you see "Vaultwarden" in an app's About screen.

## 7. Multi-arch

**Cause.** `build-images.sh` passes `--build-arg TARGETARCH=arm` and `--build-arg TARGETVARIANT=64` (or
`amd` and `64`), which is why it loops. The Dockerfile selects its compiler with
`build_${TARGETARCH}${TARGETVARIANT}`, and BuildKit sets those two values per platform by itself. A
build arg forces one value on every platform, so a combined build cannot give each platform its own
compiler stage. Upstream's `alpine-multi` target in `docker/docker-bake.hcl` uses this same Dockerfile
and only sets `platforms`; `TARGETARCH` is never passed. Remove both args and it should just work.

**The `docker manifest create` block is unnecessary.** A single `--platform a,b --push` with the
`docker-container` driver produces one manifest list.

**QEMU is barely involved.** The compile stage runs on `$BUILDPLATFORM` and cross-compiles, so the
Rust build runs at native speed. Only the runtime stage's short `apk add` runs as the target platform.
Your runner is on arm64 (agonda is OCI Ampere), so it needs `tonistiigi/binfmt --install amd64`, a
one-off in DinD.

**To verify:** the Docker Hub tags page shows arm64 host variants of `rust-musl`, and the build uses
the ghcr.io copy of those images. No source I found shows `x86_64-musl` compiled from an arm64 host,
so it needs a test build. If it fails, the second runner in section 4 solves it.

**Forgejo registry.** Its docs do not mention multi-arch directly, but it follows the OCI specs, Gitea
users push multi-arch images, and your template already passes `--provenance=false`, which avoids the
`unknown/unknown` entries that buildx attestations cause.

## 8. The pipeline

```
schedule (hourly) or workflow_dispatch
  │
  ▼
check     compare GitHub releases/latest with upstream.lock and attempt tags   [node-24]
  │        new version: Slack "1.37.6 published, building" and push attempt tag
  ▼
build     prepare tree, apply patches, overlay, verify-branding                [docker]
  │        build and push web image, then the multi-arch server image
  │        smoke test the image
  ▼
notify    Slack and email: ready, ready with warnings, or failed               [node-24]
  ▼
you       test on staging, then promote the same digest to prod
```

Details that matter:

- **Detection** uses `api.github.com/repos/dani-garcia/vaultwarden/releases/latest`, which skips
  pre-releases. Hourly polling sits well inside the unauthenticated limit. I found no evidence that a
  Forgejo pull mirror sync can trigger Actions, and Actions are off for mirrors by default, so polling
  is simpler.
- **Dedupe:** push an `attempt/<version>` tag when a build starts, and `check` skips versions that
  have one. Otherwise a failure re-alerts every hour. `workflow_dispatch` bypasses it for retries.
- **Your runner rules apply.** `docker:dind` has no Node, so `build` is shell-only and clones for
  itself. Only this job gets the `DIND_*` secrets, and nothing from upstream runs in the job shell
  (`git apply` and `sed` only). Upstream code executes only inside `docker build`, away from the
  client certificate and registry token.
- **Stale template warning:** `jay-projects/gitforge-deploy-pipeline/forgejo-workflows/release.yml`
  still sets `DOCKER_HOST: tcp://127.0.0.1:2375`, which v9 removed. Use the mutual TLS snippet in
  `forgejo-runner.md`. Enclave's template has not necessarily been run since v9, so treat
  `build-image` as untested.
- **Cache:** use a persistent named buildx builder, whose state lives in `data-dind`. Skip
  `--cache-to type=registry`, which would push several GB into a registry on the same disk.

### Smoke test

Follows your testing convention of a real server and a real database, with no mocks. Start Postgres
and the new image in DinD, wait for `/alive`, then assert:

- `/` has the Ayam title, and `/manifest.json` has the Ayam name.
- `/css/vaultwarden.css` contains your logo rule, proving the SCSS overlay is compiled in.
- `/vw_static/logo-gray.png` matches the overlay file's hash.
- `/admin` shows the Ayam title.
- `docker run --platform linux/amd64 ... /vaultwarden --version` works, proving the amd64 variant runs.

### Alerts

Both channels get the same content from one `scripts/notify.sh`.

- **Slack:** a webhook POST, the same shape as `send_slack` in `server-ops/scripts/monitor-disk.sh`.
- **Email:** `curl` speaks SMTP natively (`--url smtps://mail.ayamsecure.com:465 --mail-from ...
  --upload-file`), so no new dependency.
- **Backstop:** `enable-email-notifications: true` at the top of the workflow makes Forgejo email on
  failure and recovery even if `notify` never runs. It does not cover success, hence `notify.sh`.

What a "ready" alert contains, so staging can start from the alert alone:

```
Ayam Secure Secrets 1.37.5 ready for staging  [READY WITH WARNINGS]
Upstream: 1.37.4 -> 1.37.5   Web vault: 2026.7.0 -> 2026.10.1
Security: GHSA-x9cq-f669-vrr4, GHSA-9pjj-f9g5-3x4c        <release notes link>
Warnings: patch 0003-admin-branding skipped; 1 template still says "Vaultwarden"
New config options: <diff of .env.template between the two tags>
DB migrations: 1 new, take a backup before prod            <migrations/postgresql diff>

SECRETS_VERSION=direct.git.jaysan.org/jay/ayam-secure-secrets:1.37.5-2026.10.1-ayam.1@sha256:...
```

The `.env.template` diff replaces the "check for new env vars" comment in your compose files.
Migrations are flagged because a release that changes the schema cannot simply be rolled back.

### Secrets

| Secret | Job | Status |
| --- | --- | --- |
| `REGISTRY_TOKEN`, `DIND_CA`, `DIND_CERT`, `DIND_KEY` | build | Exist per `forgejo-runner.md` |
| `SLACK_WEBHOOK_URL`, `SMTP_USER`, `SMTP_PASSWORD` | notify | New |
| GitHub token for the push mirror | none, set in mirror settings | New, scoped to that one repo |

### Workflow sketch

Not run. It shows the shape, not the final file.

```yaml
name: Release
enable-email-notifications: true

on:
  schedule:
    - cron: '17 * * * *'
  workflow_dispatch:
    inputs:
      vw_tag: { description: 'Upstream tag, blank for latest', required: false, default: '' }
      rev: { description: 'Ayam rebuild number', required: false, default: '1' }

env:
  REGISTRY: direct.git.jaysan.org
  OWNER: jay

jobs:
  check:
    runs-on: node-24
    outputs:
      build: ${{ steps.c.outputs.build }}
      vw_tag: ${{ steps.c.outputs.vw_tag }}
    steps:
      - uses: https://code.forgejo.org/actions/checkout@v6
        with: { fetch-depth: 0 }
      - id: c
        run: node scripts/check-upstream.mjs >> "$GITHUB_OUTPUT"

  build:
    needs: check
    if: ${{ needs.check.outputs.build == 'true' }}
    runs-on: docker # shell-only: docker:dind has no node
    outputs:
      image: ${{ steps.b.outputs.image }}
    steps:
      - run: apk add --no-cache git curl
      - name: Connect to DinD over mutual TLS
        run: echo 'write DIND_* to files, export DOCKER_HOST, see forgejo-runner.md'
      - id: b
        run: sh scripts/build.sh "${{ needs.check.outputs.vw_tag }}" "${{ inputs.rev }}"

  notify:
    needs: [check, build]
    if: ${{ always() && needs.check.outputs.build == 'true' }}
    runs-on: node-24
    steps:
      - uses: https://code.forgejo.org/actions/checkout@v6
      - run: sh scripts/notify.sh "${{ needs.build.result }}" "${{ needs.build.outputs.image }}"
```

## 9. Staging and prod

The compose files already use `image: ${SECRETS_VERSION}`, so promotion is one line:

1. Paste the `SECRETS_VERSION` line from the alert into staging's `.env`, then `docker compose up -d`.
2. Test on staging.
3. Paste the same line into prod's `.env`, take a backup if the alert flagged migrations, and run
   `docker compose up -d`.

The tag includes `@sha256:`, so staging and prod run the identical image, and a pinned digest cannot
be changed by a re-pushed tag. Multi-arch also means the `.env` restored from a backup works unchanged
on jibhi3.

A later step could deploy to staging automatically, but CI would then need SSH access to agonda and a
way to edit a `.env` full of secrets. For now that seems like more risk than the one paste saves.

Compose changes for cutover (a new `v7` of both files, staging first):

- Remove the `./ayam-images:/web-vault/images` mount and the host SCSS file, both now in the image.
- Add `INVITATION_ORG_NAME`.
- Keep `RELOAD_TEMPLATES=true` on staging. You can still drop a file into `data/templates` to iterate
  on CSS, then move it to the overlay.

`IP_HEADER=Cf-Connecting-Ip` needs no change for the 1.37.4 trusted proxy work. It is a single-value
header, and the default `IP_HEADER_TRUSTED_PROXIES=local` covers Traefik on the Docker network. It
does mean origin lock-down matters: anyone reaching Traefik without passing Cloudflare could forge that
header and dodge the login rate limit. Confirm the OCI rule from `server-ops/jax-firewall.md` is live.

## 10. Build plan

Each batch ends at something you can test. I stop after each one for your review.

**Batch 0: ship 1.37.5 by hand.** Existing process, web vault v2026.10.1. Check `.env` values against
the stricter validation on staging first. Not dependent on anything below.

**Batch 1: spikes, no repo changes.** Decides the design.

- Pull upstream's web vault image and grep for every rebrand needle.
- Test `docker login` and pull from `direct.git.jaysan.org` on agonda and jibhi3.
- Confirm `uname -m` on the runner, and agonda's CPU, RAM and free disk.
- Export the real fork diff, which needs a `git diff --stat` from you or an exception to the no-git
  rule. Done when: the 42 files are classified against section 6.

**Batch 2: the build repo, local only.** `upstream.lock`, patches, overlay, `prepare-tree.sh`,
`refresh-patches.sh`, `verify-branding.sh`, tests, AGENTS.md and docs. Done when: the prepared tree
for 1.37.5 matches your manual build, apart from the intended section 6 changes.

**Batch 3: web image.** `web/Dockerfile`, `rebrand.sh` and fixture tests. Done when: the local image
serves the rebranded web vault and a missing needle fails the build.

**Batch 4: multi-arch server build in CI.** Manual `workflow_dispatch` only. DinD limits, binfmt,
`build.sh`. Done when: one tag holds both platforms, and build time and prod impact are measured.

**Batch 5: smoke test and alerts.** `smoke.sh`, `notify.sh`, new secrets. Done when: a deliberately
broken patch produces a warning alert and a broken image produces a failure alert.

**Batch 6: go live on schedule.** `check-upstream`, attempt tags, cron. Done when: a simulated new
release, run by lowering the version in the lock, flows through to the alert.

**Batch 7: cutover.** Compose v7, jibhi3 pre-pull cron, public push mirror, disclaimer text,
onboarding email update, package cleanup rule, archive the forks. Done when: staging then prod run a
pipeline-built image, and a restore on jibhi3 works with agonda's registry unreachable.

## 11. What is verified and what is not

**Verified by reading the repos:** everything in section 2, the single-line Dockerfile delta, the
`TARGETARCH` cause, prod and Forgejo sharing agonda, the release profile, `FORCE_PRIVATE` and
`REQUIRE_SIGNIN_VIEW`, the placeholder SCSS size, and no SRI in the web build.

**Verified from upstream pages:** the release and advisory history, and the 1.37.5 upgrade notes.

**Not verified, covered by Batch 1 or 4:**

- Rebrand strings surviving minification.
- `--build-context` overriding a `linux/amd64` stage during a multi-platform build.
- `x86_64-musl` cross-compiling from an arm64 host.
- A multi-arch push and pull against your Forgejo registry.
- Build duration under DinD limits, including the runner's 3h job timeout.
- Whether DinD's `build-image` path works since the v9 change.

**Unknown, needs you:** the host `.env` contents, which I did not read. The compose `INVITATION_ORG_NAME`
and `EXPERIMENTAL_CLIENT_FEATURE_FLAGS` checks both depend on it. Invalid flags currently log a
warning at startup, so read the staging log carefully given 1.37.5's stricter validation.

**Side observation, not investigated:** the Alpine image installs no `logrotate`, so the
`vw-logrotate.conf` mount looks inert inside the container. Worth checking that `/data/vaultwarden.log`
is rotated from the host.

## 12. Sources

- [Vaultwarden releases](https://github.com/dani-garcia/vaultwarden/releases)
- [Vaultwarden security advisories](https://github.com/dani-garcia/vaultwarden/security/advisories)
- [bw_web_builds releases](https://github.com/dani-garcia/bw_web_builds/releases)
- [GNU AGPL v3](https://www.gnu.org/licenses/agpl-3.0.html)
- [docker buildx build](https://docs.docker.com/reference/cli/docker/buildx/build/)
- [Docker build variables](https://docs.docker.com/build/building/variables/)
- [Forgejo container registry](https://forgejo.org/docs/latest/user/packages/container/)
- [Forgejo packages](https://forgejo.org/docs/latest/user/packages/)
- [Forgejo token scopes](https://forgejo.org/docs/latest/user/authentication/token-scope/)
- [Forgejo repository mirrors](https://forgejo.org/docs/latest/user/repo-mirror/)
- [Forgejo Actions reference](https://forgejo.org/docs/latest/user/actions/)
- [Gitea issue on attestation entries](https://github.com/go-gitea/gitea/issues/24973)
- [rust-musl](https://github.com/BlackDex/rust-musl) and its [tags](https://hub.docker.com/r/blackdex/rust-musl/tags)
