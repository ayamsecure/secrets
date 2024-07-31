# Notes for Ayam Secure Secrets

- This repo is forked from dani-garcia/vaultwarden

## When a new VW release has been published:

1. from terminal, `git checkout main` (ignore untracked changes) then `git fetch upstream` then `git merge upstream/main` then `git push origin main`
2. `git checkout main-ayam` then `git merge main` to bring in new changes into main-ayam branch, resolve conflicts (accept incoming for ayam changes), `git add .` then `git commit` to conclude merge and `git push`
3. from main-ayam branch, create new version branch `git checkout -b 1.31.0`
4. confirm patches (below) are still applied and check for changes to Dockerfile.alpine
5. use colima (x86 arch) on optimac to build image, ensure logged in to docker hub for push
6. git push changes and after testing on staging service merge into main-ayam via PR

- have to --push, can't --load, maybe due to multi-arch images

```
export AYAM_VW_VERSION=1.31.0
export AYAM_WEB_VAULT_VERSION=2024.5.1
export AYAM_SECRETS_TAG=$AYAM_VW_VERSION-$AYAM_WEB_VAULT_VERSION
docker buildx build --platform linux/amd64,linux/arm64 -f ./docker/Dockerfile.ayam \
--build-arg VW_VERSION=$AYAM_VW_VERSION \
--build-arg DB=postgresql,enable_mimalloc \
--build-arg TARGETARCH=arm \
--build-arg TARGETVARIANT=64 \
-t jayknyn/ayam-secure-secrets:$AYAM_SECRETS_TAG . --push
```

Notes:

- Dockerfile.ayam is based on Dockerfile.alpine, so always compare after pulling in updates from upstream before docker build
- update the secrets-web docker image tag in this readme and Dockerfile.ayam

## Version numbers

- 1.29.1, matches upstream 1.29.1
- 1.29.3a, patch fix for mobile clients issue, based off of 1.29.2 and latest commits to main, waiting on upstream 1.29.3
- 1.30.1, matches upstream 1.30.1
- 1.30.5 matches upstream
- 1.31.0 matches upstream, api-config.json is not in upstream, update version here

## Changelog

[03/12/24]

- simplified Dockerfile.ayam to just replace one line, web-vault image hash
- updated readme with multi-arch build command for arm64 and amd64

---

## Patching done on vaultwarden/main

- reference this commit for all AS patches: https://github.com/ayamsecure/secrets/commit/71a471745416b3b17bb0452ce0e6b6e71bb4eaaa

### Confirm after merge with upstream:

/src/api/web.rs:

- ln 154 in func static_files, disable mail-github.png

/src/mail.rs

- ln 585 in fn send_email, disable attaching mail-github.png singlePart

/src/static/images to change:

- logo-gray.png
- vaultwarden-icon.png
- vaultwarden-favicon.png

/src/static/templates/404.hbs to change:

- ln 19 change navbar-brand to Secrets Admin
- ln 38 change to ayamsecure.com
- ln 41 footer change

/src/static/templates/admin/base.hbs:

- ln 8 change title to AS
- ln 16 navbar-brand to AS

/src/static/templates/admin/login.hbs:

- ln 13 comment out
- ln 21 change Enter to Login

/src/static/templates/admin/users.hbs:

- ln 2 moved Invite User section to top

/src/static/templates/email/change_email.hbs

- ln 3 your web vault

/src/static/templates/email/change_email.html.hbs

- ln 7 your web vault

/src/static/templates/email/email_footer.hbs

- ln 8 and ln 10, font-size: 16px; line-height: 25px;
- ln 21 url ayamsecure

/src/static/templates/email/email_footer_text.hbs

- ln 3 url ayamsecure

/src/static/templates/email/email_header.hbs

- ln 9 title ayam secure
- ln 109 img alt ayam secure

/src/static/templates/email/invite_accepted.hbs

- ln 4 please log in to the web vault

/src/static/templates/email/invite_accepted.html.hbs

- ln 20 please log in to the web vault

/src/static/templates/email/invite_confirmed.hbs

- ln 4 will now appear in your vault

/src/static/templates/email/invite_confirmed.html.hbs

- ln 12 and ln 14 log in to your web vault

/src/static/templates/email/protected_action.hbs

- ln 5 passcode ayamsecure

/src/static/templates/email/protected_action.html.hbs

- ln 12 passcode ayamsecure

/src/static/templates/email/smtp_test.hbs

- ln 1 title ayamsecure

/src/static/templates/email/smtp_test.html.hbs

- ln 1 title ayamsecure

/src/static/templates/email/twofactor_email.hbs

- ln 1 subject ayamsecure
- ln 5 passcode and ayamsecure

/src/static/templates/email/twofactor_email.html.hbs

- ln 19 passcode and ayamsecure

---

## Notes

```
FROM --platform=linux/amd64 ghcr.io/blackdex/rust-musl:aarch64-musl-stable-1.76.0 as build
ARG TARGETARCH="arm"
ARG TARGETVARIANT="64"
ARG TARGETPLATFORM="aarch64"

# old build command
docker build -f ./docker/Dockerfile.ayam -t jayknyn/ayam-secure-secrets:1.31.0-2024.5.1 .

```
