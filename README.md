# Chama360

📱 **[Download the latest Android build](https://github.com/enricoshilisia/chama360/releases/download/android-latest/chama360-android-debug.apk)**
(debug build — enable "install from unknown sources" for whichever app you download it through)

Flutter + Supabase chama (savings group) app. No Django, no VPS — Supabase is
the entire backend (Postgres, auth, realtime, storage), Flutter is the only
client. See `supabase/migrations/` for the full schema and business logic
(loan interest, balances, notifications) implemented as Postgres triggers and
RPC functions.

## What's built so far

- **Auth** — email/password sign up & sign in (Supabase Auth), password
  reset, optional biometric unlock (fingerprint/face) gating an existing
  device session.
- **Chamas** — create a chama (you become chairperson), join one by invite
  code, view your role and balance, member roster.
- **Contributions** — record a contribution; balance and the transaction
  ledger update automatically via a DB trigger. Works offline — queues
  locally and syncs when connectivity returns.
- **Transactions ledger** — auto-populated by triggers on contributions and
  loan repayments/disbursements; read-only from the client.
- **Notifications** — in-app feed backed by a `notifications` table +
  realtime subscription; DB triggers fan out a notification to every member
  when someone contributes, and to a member when their loan status changes.
  (Push notifications via Firebase Cloud Messaging are a later step — this
  covers the in-app feed only.)
- **Offline** — SQLite cache (via `sqflite`) for chamas and transactions, an
  outbox table for writes made offline, auto-sync on reconnect.
- **Theme** — light/dark (follows system by default, switchable in Profile),
  light-green brand palette, glassmorphic cards throughout.
- **Navigation** — bottom nav shell (Home, Chamas, Alerts, Profile) built
  with `go_router`'s `StatefulShellRoute`.

Loans (request/approve/repay UI) and meetings/attendance aren't wired up in
the Flutter app yet — the database schema and RLS policies for both already
exist in the migrations, so it's UI work from here, not backend design.

## One-time setup

### 1. Create the Supabase project

1. Go to [supabase.com](https://supabase.com) → New project.
2. Once it's up, open **SQL Editor** and run, in order:
   - `supabase/migrations/0001_init_schema.sql`
   - `supabase/migrations/0002_notifications.sql`
3. Open **Project Settings → API** and copy the **Project URL** and the
   **anon / public** key.

### 2. Configure the app

Copy `.env.example` to `.env` and fill in the two values from step 1:

```
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=your-anon-public-key
```

`.env` is gitignored — never commit real keys. The anon key is safe to ship
in a client app; every table is protected by Row Level Security, so a user
can only ever read/write what the policies in `0001_init_schema.sql` allow.

### 3. Run it

```
flutter pub get
flutter run
```

Pick your connected Android device or emulator when prompted (`flutter
devices` to list them). First sign-up sends a confirmation email — Supabase's
default email provider works out of the box for testing, so check the inbox
you signed up with.

## Project layout

```
lib/
  core/                    # cross-cutting: config, theme, router, services
    config/                # env.dart, supabase_config.dart
    theme/                 # colors, light/dark ThemeData, glass widgets
    router/                # go_router setup + bottom-nav shell
    services/              # biometrics, SQLite cache, connectivity, sync
  features/
    auth/        (data/ providers/ screens/)
    chama/       (domain/ data/ providers/ screens/)
    contributions logic lives inside chama/ for now — split out if it grows
    notifications/
    dashboard/
    profile/
supabase/
  migrations/              # run these in the Supabase SQL editor, in order
```

Each feature follows `domain → data → presentation(providers/screens)` —
`domain` models are plain Dart, `data` repositories are the only code that
talks to Supabase, `presentation` never calls Supabase directly. This is the
Flutter analogue of Django's `models.py` / `views.py` split.

## Android build note

`local_auth` (biometrics) requires the Android host activity to be a
`FlutterFragmentActivity`, not the default `FlutterActivity` — already
changed in `android/app/src/main/kotlin/.../MainActivity.kt`. If you ever
regenerate that file, redo that change.

## Next steps (not yet built)

- Loan request/approve/repay screens (schema + RLS already in
  `0001_init_schema.sql` — `loans`, `loan_repayments`).
- Meetings & attendance screens (schema already in `0001_init_schema.sql`).
- Push notifications via Firebase Cloud Messaging (needs a Firebase project;
  the in-app notification feed already works without it).
- M-Pesa Daraja integration via a Supabase Edge Function, once you're ready
  to move off manual contribution entry.
- iOS build: once Android is verified, `flutter build ios` from a Mac with
  Xcode, plus enabling `NSFaceIDUsageDescription` in `Info.plist` for
  biometrics.
