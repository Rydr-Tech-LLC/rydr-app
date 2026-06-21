# Cash Rydr Hub Firebase Permissions

Cash Rydr Hub uses Firestore and Firebase App Check. If local writes fail with
`App attestation failed` or `Missing or insufficient permissions`, check both
layers below.

## 1. Register the App Check debug token

Debug builds use `AppCheckDebugProviderFactory` in `App/AppDelegate.swift`.
When you run the app from Xcode, Firebase prints a debug token in the console.

1. Run `RydrPlayground` from Xcode.
2. In the Xcode console, copy the App Check debug token printed by Firebase.
3. Open Firebase Console.
4. Go to **App Check**.
5. Select the RydrPlayground iOS app:
   `com.khris.rydr.RydrPlayground`.
6. Open **Manage debug tokens**.
7. Add the copied token and label it with the machine name.
8. Relaunch the app.

Do not commit debug tokens to the shared Xcode scheme. Each development machine
can register its own token in Firebase Console.

## 2. Deploy Firestore rules

After editing `firestore.rules`, deploy the rules:

```bash
firebase deploy --only firestore:rules
```

The Cash Hub rules allow:

- Riders to create their own `cashRydrRequests`.
- Request owners to edit/delete their own requests.
- Drivers to connect to open requests or update requests they are connected to.
- Users to create only responses authored by their own Firebase UID.
- Response authors or the request owner to update a response.

If App Check enforcement is enabled and the debug token is not registered,
Firestore writes can fail before the Firestore rules are evaluated.
