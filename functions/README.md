# Admin Cloud Functions

Six callables enforce every admin/moderation action server-side using the
Firebase Auth custom claim `admin: true`. No client-supplied `actorUid` is
ever trusted; the acting admin's uid always comes from `request.auth.uid`.

## Functions

- `banUser`, `unbanUser`, `disableAccount`, `restoreAccount`
- `issueWarning`, `updateReportStatus`
- `setAdminClaim` — lets an existing admin grant/revoke the claim on another uid
- `deleteCloudinaryMedia` — signs and performs a Cloudinary asset delete on
  behalf of any signed-in user (not admin-only); see
  `CLOUDINARY_SECRET_MIGRATION_GUIDE.md` at the repo root for why this exists
  and how to configure it.

## Secret Manager configuration

`deleteCloudinaryMedia` reads three secrets via `firebase-functions/params`'
`defineSecret` — they must exist in Secret Manager before that function can
be deployed or invoked:

```
firebase functions:secrets:set CLOUDINARY_CLOUD_NAME
firebase functions:secrets:set CLOUDINARY_API_KEY
firebase functions:secrets:set CLOUDINARY_API_SECRET
```

See `CLOUDINARY_SECRET_MIGRATION_GUIDE.md` for the full walkthrough.

## Deploy

```
cd functions
npm install
npm run build
firebase deploy --only functions
```

## Granting the first admin

`setAdminClaim` requires an existing admin, so the very first admin has to be
bootstrapped out-of-band with a service account key that has Firebase Auth
Admin permission:

```
cd functions
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
  node scripts/bootstrapFirstAdmin.js <uid>
```

After this runs, that account can call `setAdminClaim` to promote or demote
any other account, and the client's `AdminGuard`/`AdminConfig.adminUids`
allowlist should be updated to match for UI purposes only — the real
authorization boundary is the custom claim, checked in both `firestore.rules`
and every callable in this directory.

Run `firebase deploy --only firestore:rules` after deploying these functions
so the two land together — the rules deny direct client writes to the
collections these functions own.
