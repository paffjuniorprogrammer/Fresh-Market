# Release Checklist

## Must Pass Before Public Release
- Create a real Android release keystore and store it in `android/key.properties`.
- Confirm `android/app/build.gradle.kts` is signing `release` with the release keystore, not the debug keystore.
- Apply the latest Supabase migrations to the live project.
- Verify signup, email confirmation, login, and password reset on a real device.
- Verify the admin role lookup fails closed if the `users` row is missing or the RPC query fails.
- Verify grouped checkout, client discounting, debt recording, and payment recording with real data.
- Run `flutter test` and fix every failing test.
- Build a release APK or App Bundle and install it on a clean device.
- Test push notifications, live location updates, and image uploads outside the debug environment.
- Back up the Supabase database and confirm restore steps before launch.

## Nice To Have Before Scale-Up
- Add crash reporting and analytics.
- Add a simple internal admin audit log for discounts and payment edits.
- Run a small pilot with real users for at least one full business cycle.
