# Notes for Ayam Secure Secrets

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
