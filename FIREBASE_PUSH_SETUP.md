# Fresh Market Firebase Push Setup

This project already contains the Flutter-side push notification code and the Supabase Edge Function scaffold.

You still need to connect your real Firebase project and Supabase secrets.

## 1. Current App Identifiers

Use these exact identifiers for the current Fresh Market Firebase config:

- Android application ID: `com.freshmarket.freshmarket`
- iOS bundle ID: `com.freshmarket.freshmarket`
- Supabase project ref: `qhpfppsdjmibucurucui`

Important:

- These IDs now match the Firebase files currently in the project.

## 2. Create Firebase Project

In Firebase Console:

1. Create a new project named `Fresh Market`.
2. Open `Project settings`.
3. Add an Android app.
4. Add an iOS app.

## 3. Add Android Firebase App

In Firebase Console, create the Android app with:

- Android package name: `com.freshmarket.freshmarket`

Then download:

- `google-services.json`

Place it here:

- [google-services.json](c:/Users/PAFF-DADDY/OneDrive/Desktop/Fresh Market/Fresh Market/android/app/google-services.json)

## 4. Add iOS Firebase App

In Firebase Console, create the iOS app with:

- iOS bundle ID: `com.freshmarket.freshmarket`

Then download:

- `GoogleService-Info.plist`

Place it here:

- [GoogleService-Info.plist](c:/Users/PAFF-DADDY/OneDrive/Desktop/Fresh Market/Fresh Market/ios/Runner/GoogleService-Info.plist)

## 5. Enable Firebase Cloud Messaging

In Firebase Console:

1. Open `Project settings`.
2. Open `Cloud Messaging`.
3. Confirm Cloud Messaging is enabled for the project.

## 6. Get Service Account Values For Supabase

In Firebase Console:

1. Open `Project settings`.
2. Open `Service accounts`.
3. Click `Generate new private key`.
4. Download the JSON file.

You will extract these values from that JSON:

- `project_id` -> `FCM_PROJECT_ID`
- `client_email` -> `FCM_CLIENT_EMAIL`
- `private_key` -> `FCM_PRIVATE_KEY`

## 7. Get Supabase Service Role Key

In Supabase:

1. Open your project dashboard.
2. Open `Settings`.
3. Open `API`.
4. Copy the `service_role` key.

That value becomes:

- `SUPABASE_SERVICE_ROLE_KEY`

## 8. Set Supabase Edge Function Secrets

From the repo root:

```powershell
cd "c:\Users\PAFF-DADDY\OneDrive\Desktop\Fresh Market\Fresh Market"
npx supabase login
npx supabase link --project-ref qhpfppsdjmibucurucui
```

Then set secrets:

```powershell
$env:FCM_PROJECT_ID="your-firebase-project-id"
$env:FCM_CLIENT_EMAIL="firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com"
$env:FCM_PRIVATE_KEY=@"
-----BEGIN PRIVATE KEY-----
YOUR_PRIVATE_KEY_CONTENT
-----END PRIVATE KEY-----
"@
$env:SUPABASE_SERVICE_ROLE_KEY="your-supabase-service-role-key"

npx supabase secrets set `
  FCM_PROJECT_ID=$env:FCM_PROJECT_ID `
  FCM_CLIENT_EMAIL=$env:FCM_CLIENT_EMAIL `
  FCM_PRIVATE_KEY="$env:FCM_PRIVATE_KEY" `
  SUPABASE_SERVICE_ROLE_KEY=$env:SUPABASE_SERVICE_ROLE_KEY
```

## 9. Deploy The Edge Functions

From the repo root:

```powershell
cd "c:\Users\PAFF-DADDY\OneDrive\Desktop\Fresh Market\Fresh Market"
npx supabase functions deploy notify-admin-new-order --project-ref qhpfppsdjmibucurucui
npx supabase functions deploy notify-client-event --project-ref qhpfppsdjmibucurucui
npx supabase functions deploy record-order-payment --project-ref qhpfppsdjmibucurucui
```

The function sources are here:

- [index.ts](c:/Users/PAFF-DADDY/OneDrive/Desktop/potato/potato_app/supabase/functions/notify-admin-new-order/index.ts)
- [index.ts](c:/Users/PAFF-DADDY/OneDrive/Desktop/Fresh Market/Fresh Market/supabase/functions/notify-admin-new-order/index.ts)
- [index.ts](c:/Users/PAFF-DADDY/OneDrive/Desktop/Fresh Market/Fresh Market/supabase/functions/notify-client-event/index.ts)
- [index.ts](c:/Users/PAFF-DADDY/OneDrive/Desktop/Fresh Market/Fresh Market/supabase/functions/record-order-payment/index.ts)

## 10. Run The Database SQL

Before testing, run:

- [apply_fixes.sql](c:/Users/PAFF-DADDY/OneDrive/Desktop/potato/potato_app/supabase/apply_fixes.sql)
- [apply_fixes.sql](c:/Users/PAFF-DADDY/OneDrive/Desktop/Fresh Market/Fresh Market/supabase/apply_fixes.sql)

This now includes:

- `admin_tokens`
- `client_tokens`
- `locations`
- payment method fixes
- grouped checkout fixes

## 11. Test Flow

1. Run the app on the admin phone.
2. Sign in as an admin.
3. Allow notification permission on the device.
4. Check Supabase table `admin_tokens`.
5. Confirm the admin device token row appears.
6. Run the app on a client phone.
7. Check Supabase table `client_tokens`.
8. Confirm the client device token row appears.
9. Place an order.
10. Confirm the `notify-admin-new-order` Edge Function runs and the admin phone receives the push.
11. Record a payment as admin.
12. Confirm the `record-order-payment` and `notify-client-event` Edge Functions run and the client phone receives the push.

## 13. iOS Push Capability

For iPhone delivery, also verify in Xcode that the `Runner` target has:

- `Push Notifications` capability enabled
- `Background Modes` enabled with `Remote notifications`

The repo now includes the `Runner.entitlements` file and background mode entry, but the Apple signing profile still needs those capabilities enabled in your Apple Developer account.

## 14. Sound Behavior

Current implementation:

- Foreground admin app: uses your existing asset sound `assets/audio/notification.mpeg`
- Background or terminated app: uses FCM default push sound

If you want the same custom sound while the app is closed, you need to add a native notification sound file under Android `res/raw` and configure iOS notification sound resources too.
