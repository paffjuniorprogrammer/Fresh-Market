# Potato App

Potato App is a Flutter customer and admin application for selling potatoes with a Supabase backend.

It supports:

- customer product browsing
- customer order placement
- credit orders with partial payment
- persistent order history lookup by phone number
- admin product management
- admin visibility into recent orders and outstanding debts

## App overview

The app has two main sides:

- Customer view
  Customers can browse available potato categories, check stock and pricing, place orders, and later look up their saved orders using the same phone number they used during checkout.

- Admin view
  Admin users can add, edit, enable, disable, and delete products. The dashboard also shows product stock, recent orders, pending orders, and unpaid balances.

## Current architecture

Frontend:

- Flutter
- single main app entry in [`lib/main.dart`](lib/main.dart)

Backend:

- Supabase database
- Supabase storage bucket for product images
- PostgreSQL function for atomic order placement
- SQL schema in [`supabase/schema.sql`](supabase/schema.sql)
- SQL patch set in [`supabase/apply_fixes.sql`](supabase/apply_fixes.sql)

## Core backend resources

The app expects these Supabase resources:

- `public.products`
- `public.customers`
- `public.orders`
- `public.outstanding_debts`
- `public.place_order(...)`
- storage bucket: `products`

The SQL script creates all of them.

## Data flow

### Products

Products are stored in `public.products`.

Each product contains:

- id
- name
- description
- image URL
- price
- quantity
- availability status
- created timestamp

### Customers

Customers are stored in `public.customers`.

The current design uses phone number as the unique customer identifier for repeat lookups and updates.

### Orders

Orders are stored in `public.orders`.

Each order stores:

- customer details at time of order
- selected product
- quantity
- price per kg
- total price
- paid amount
- credit flag
- order status
- created timestamp

### Debts

Outstanding balances are derived from the `public.outstanding_debts` view.

This view aggregates unpaid amounts across orders and excludes cancelled orders.

### Order placement

Customer checkout does not directly update tables from Flutter one row at a time.

Instead, the app calls `public.place_order(...)`, which:

1. validates the request
2. locks the selected product row
3. checks stock availability
4. creates or updates the customer
5. deducts product stock
6. creates the order
7. returns the saved order result

This avoids partial writes and keeps stock and order records in sync.

## Features

### Customer features

- browse available potato products
- view live stock quantity
- place cash or credit orders
- enter partial payment for credit orders
- look up saved orders by phone number
- receive clearer setup and backend error messages

### Admin features

- create products
- edit products
- upload product images to Supabase Storage
- assign product categories
- set discount price and threshold rules
- enable or disable products
- delete products
- view product stock totals
- view recent orders
- view pending order count
- view outstanding debt balances

## Supabase setup

Run the included SQL before using the app.

### Steps

1. Open your Supabase project.
2. Open `SQL Editor`.
3. Run [`supabase/schema.sql`](supabase/schema.sql).
4. If the database already exists, also run [`supabase/apply_fixes.sql`](supabase/apply_fixes.sql).
5. Wait for execution to complete.
6. Restart the Flutter app.

The script is idempotent and also inserts starter products if the products table is empty.

## Storage setup

The SQL script also creates the public `products` bucket and its policies.

That bucket is used for product image URLs and storage access.

## Running the app

### With custom Supabase values

```bash
flutter run \
  --dart-define=SUPABASE_URL=your-project-url \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

### With current defaults

If your project already uses the hardcoded defaults in `main.dart`, a normal Flutter run is enough:

```bash
flutter run
```

## Project structure

```text
potato_app/
├── lib/
│   └── main.dart
├── supabase/
  schema.sql
  apply_fixes.sql
├── android/
├── ios/
├── web/
├── windows/
├── linux/
├── macos/
└── test/
```

## Important screens

- App bootstrap and setup screens
- Customer catalogue
- Order form
- Saved order lookup dialog
- Admin dashboard

## Error handling

The app includes friendlier setup handling for:

- missing Supabase configuration
- missing database schema
- missing storage bucket
- backend loading failures

Instead of showing raw PostgREST errors directly to the user, the app now explains what resource is missing and points to `supabase/schema.sql` or `supabase/apply_fixes.sql`.

## Release size notes

The project folder can become large after builds because Flutter regenerates:

- `.dart_tool/`
- `build/`

These folders are generated artifacts, not the real source size of your app.

If you want to remove generated output from the workspace:

```bash
flutter clean
```

## Smaller Android releases

This project already enables release shrinking in Android.

For smaller Android outputs:

- build split APKs:

```bash
flutter build apk --release --split-per-abi
```

- or build an app bundle for Play Store delivery:

```bash
flutter build appbundle --release
```

## Smaller web releases

For web, always build a release bundle:

```bash
flutter build web --release
```

Important note:

Flutter web bundles are usually much larger than the raw source code because the Flutter runtime and renderer assets are included in the final output.

## Development commands

Get packages:

```bash
flutter pub get
```

Analyze:

```bash
flutter analyze
```

Run tests:

```bash
flutter test
```

Clean generated files:

```bash
flutter clean
```

## Windows release

This project already has a Windows desktop target, but a release build requires Visual Studio with the `Desktop development with C++` workload installed.

Build the Windows release:

```bash
flutter build windows --release
```

The packaged app will be created under:

```text
build\windows\x64\runner\Release\
```

Main executable:

```text
build\windows\x64\runner\Release\fresh_market.exe
```

## Supabase Auth setup

Email confirmation is handled by Supabase Auth, not by the Flutter app. To receive confirmation emails:

- enable Email Confirmations in Supabase Auth settings
- configure an SMTP sender for the project so Supabase can actually deliver mail
- add `freshmarket://auth-confirmation` to the allowed redirect URLs
- keep the app's deep-link scheme registered on Android and iOS

If sign-up returns an immediate session, the project is currently allowing login without email confirmation.

## Current limitations

This app is much more real than the initial prototype, but it is still not a full production commerce platform.

Current limitations include:

- admin and customer roles are not protected by real authentication yet
- current RLS policies are permissive for demo and development use
- order management is basic and does not yet include payment collection workflows
- there is no reporting export, invoicing, or notification system
- order lookup is based on phone number instead of authenticated customer accounts

## Recommended next steps

If you want to push this toward production, the next upgrades should be:

1. add Supabase Auth for admin access
2. tighten RLS policies
3. separate admin-only write access from customer checkout access
4. add payment tracking and debt settlement flows
5. add order status update actions in the admin dashboard
6. add analytics and reporting

## Testing status

The project has been validated with:

- `flutter analyze`
- `flutter test`

## Summary

Potato App is a Flutter + Supabase inventory and order system for potato sales.

It currently provides:

- persistent products
- persistent customers
- persistent orders
- debt tracking
- admin inventory management
- customer order lookup

The included Supabase SQL file is required for the app to work correctly.





#   F r e s h - M a r k e t  
 #   F r e s h - M a r k e t  
 