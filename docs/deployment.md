# Android release operations

CoRHub is a signed Flutter application. Install and enable Phone access on
[CoRAgent](https://github.com/iawnix/TSPi), then run on the server:

```bash
research-agent --workspace reaction-a
research-agent phone pair
research-agent phone devices
# Revoke a lost or replaced device:
research-agent phone revoke <device-id>
```

Host connects outbound to CoRAgent Link Relay; no public Host port is
required. The app uses the trusted HTTPS Relay origin and one-time pairing
code. Upgrading from legacy protocol identities requires re-pairing.

## Publish on GitHub

1. Fetch tags, choose an increasing version/build with `tool/version.py set`,
   and add its exact `## X.Y.Z+N` section to `CHANGELOG.md`.
2. Run `tool/iterate.sh dev` and, for protocol changes, the local deterministic
   CoRAgent interoperability suite. Review the source and merge to `main`.
3. From that clean commit, create and push the annotated tag:

   ```bash
   tag=$(python3 tool/version.py tag)
   git tag -a "$tag" -m "CoRHub ${tag#corhub-v}"
   python3 tool/version.py check --tag "$tag" --release
   git push origin "$tag"
   ```

The workflow validates tag/source/version/changelog **before** signing, repeats
independent checks, builds three split APKs plus an AAB, validates archive
identity, signatures and source attestations, and generates `SHA256SUMS`.
It uploads the exact nine-file set to a **draft**, checks GitHub's asset sizes
and SHA-256 digests, then publishes and marks it latest. It refuses to modify
a public release. A failed draft can be completed by rerunning the tag workflow
or dispatching it with the same existing tag. Never move a published tag.

Required repository secrets (already used by the production release identity):

- `TS_PHONE_RELEASE_KEYSTORE_B64`
- `TS_PHONE_RELEASE_KEYSTORE_PASSWORD`
- `TS_PHONE_RELEASE_CERTIFICATE_SHA256`

Keep the original certificate and `xyz.iawnix.ts_phone` application ID. Never
regenerate the production key. Signing files are provisioned only after tests,
kept in runner temporary storage and removed by an `always()` cleanup step.
No local test data, test logs, credentials or private caches are uploaded.

## Local build

Configure `TS_PHONE_FLUTTER`, `TS_PHONE_ANDROID_SDK`, `TS_PHONE_JAVA_HOME` and
`TS_PHONE_SIGNING_DIR` to existing trusted tools and the protected production
key directory. Optional `TS_PHONE_BUILD_TOOLS` selects build-tools 36.0.0.
`build_apk.sh` is a compatibility wrapper for `tool/iterate.sh release`.

For local validation, SDK copies, caches, temporary build files and outputs
must be inside the private test root. Explicitly set:

```bash
export TS_PHONE_BUILD_ROOT=/home/iaw/project/TSPi/local_debug/corhub/android-build
export TS_PHONE_OUTPUT_ROOT=/home/iaw/project/TSPi/local_debug/corhub/android-output
# Set private SDK/cache and protected signing paths before invoking:
./tool/iterate.sh release
```

`--allow-dirty` is only for local candidates and cannot pass GitHub publication
validation. A release captures exact source before building; each artifact
embeds a small source identity manifest (commit/digest), **not the source code**.
Official downloadable artifacts are built anew on GitHub from the committed
tag; never upload artifacts from local_debug.

Most users install the arm64-v8a APK. The AAB is for store upload. Android
usually blocks downgrades and signer changes; see [recovery](recovery.md).
iOS signing and binary distribution are not part of this workflow.

## Identity retained across the CoRHub rename

The `TS_PHONE_*` environment variables and GitHub secret names, signing key
filename/alias and protected signing directory remain the existing operational
contract. Do not generate new keys or rename secrets for this brand update.
Android remains `xyz.iawnix.ts_phone`; iOS remains `xyz.iawnix.tsPhone`. Secure
storage namespaces and Host/Link/runtime schemas also remain stable. Future
release tags and downloadable filenames use `corhub-`; old releases are unchanged.
