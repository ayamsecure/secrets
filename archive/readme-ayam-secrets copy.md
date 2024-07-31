# Notes for Ayam Secure Secrets

- This repo is forked from dani-garcia/vaultwarden

### When a new VW release has been published:

1. from terminal, `git checkout main` (ignore untracked changes) then `git fetch upstream` then `git merge upstream/main` then `git push origin main`
2. `git checkout main-ayam` then `git merge main` to bring in new changes into main-ayam branch, resolve conflicts (accept incoming for ayam changes), `git add .` then `git commit` to conclude merge and `git push`
3. from main-ayam branch, create new version branch `git checkout -b 1.30.1`
4. apply patches
5. use jibhi3 to build image: `docker build -f ./docker/Dockerfile.ayam -t jayknyn/ayam-secure-secrets:1.30.1 .`
6. docker login then `docker push jayknyn/ayam-secure-secrets:1.30.1`
7. git push changes and after testing on staging service merge into main-ayam via PR

## Version numbers

- 1.29.1, matches upstream 1.29.1
- 1.29.3a, patch fix for mobile clients issue, based off of 1.29.2 and latest commits to main, waiting on upstream 1.29.3

## Ayam Secure Secrets forked from Vaultwarden

- docker build -f /Users/jay/codejk/ayam-secrets/docker/Dockerfile.ayam -t jayknyn/ayam-secure-secrets:1.29.3a .
- docker push jayknyn/ayam-secure-secrets:1.29.3a

---

### Patching done on vaultwarden/main

- reference this commit for all AS patches: https://github.com/ayamsecure/secrets/commit/71a471745416b3b17bb0452ce0e6b6e71bb4eaaa

/docker/arm64/Dockerfile.alpine, change done just to signal using this file for build

/src/mail.rs
ln 585 in fn send_email, disable attaching mail-github.png singlePart

/src/api/web.rs:
ln 117 in fn static_files, disable mail-github.png

/src/static/images to change:

- logo-gray.png
- vaultwarden-icon.png
- vaultwarden-favicon.png

/src/static/templates to change:

- 404.hbs

/src/static/templates/admin to change:

- base.hbs, html title to AS

/email/admin_rest_password.hbs

---
