## Summary

<!-- What changed, and why? Keep the scope small and focused. -->

## Type of change

- [ ] Bug fix
- [ ] Feature / behavior change
- [ ] Docs / metadata only
- [ ] Build, packaging, or release workflow
- [ ] Other:

## Verification

<!-- Check the commands you ran. For docs-only PRs, focused docs checks are OK. -->

- [ ] `swift build`
- [ ] `swift test`
- [ ] `./script/build_and_run.sh --package`
- [ ] `./script/package_verify.sh dist/LithePG.app`
- [ ] `./script/dogfood_check.sh` (release-impacting changes; requires Docker/Postgres)
- [ ] Docs/template checks only (explain below)

Notes / command output summary:

```text

```

## Contributor checklist

- [ ] My commits are signed off (`git commit -s`) under the DCO.
- [ ] I read `CONTRIBUTING.md`, `GOVERNANCE.md`, and `CODE_OF_CONDUCT.md`.
- [ ] I updated docs/tests where the behavior, architecture, security posture, or release workflow changed.
- [ ] I did not add dependencies without prior discussion.
- [ ] I did not add an `.xcodeproj`; this remains SwiftPM-only.
- [ ] I preserved the local-first privacy invariant: prompts, schemas, query results, credentials, and history do not leave the user's machine.
- [ ] I did not paste or commit passwords, tokens, full connection URLs, private schemas, real query-result dumps, certificates, or real user/customer data.
- [ ] Any examples, screenshots, fixtures, or logs are redacted, seeded, or synthetic.

## Security and privacy

If this PR changes credential handling, TLS behavior, local storage, AI context,
query history, release signing/notarization, or other security-sensitive code,
explain the risk and mitigation here. Do **not** include secrets or real data.

```text

```
