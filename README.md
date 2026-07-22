# Gym / Prayer / Weight Tracker (Flutter + Firebase)

## What's included
- `lib/screens/auth/` — Login & Sign Up screens (Firebase Auth, email+password).
- `lib/screens/home/` — Home screen with the 4 square icons (GYM, Prayer, Weight, Coming Soon).
- `lib/screens/gym/` — Gym menu (Chest, Bi's & Tri's, Back, Leg, Shoulder) + a table
  screen per muscle group that stores exercise name, weight, reps, and date, newest first.
- `lib/screens/prayer/` — Today's 5 prayer times computed from your GPS location, with
  "On time" / "Delayed" checkboxes per prayer, saved per calendar day.
- `lib/screens/weight/` — Log your weight for any date + a line graph you can toggle
  between Weekly / Monthly / Yearly.
- `firestore.rules` — locks every user's data to that user only.

## 1. Create the Flutter project shell
These files assume a standard Flutter app skeleton (created via `flutter create`).
If you don't have one yet:

```bash
flutter create gym_app
```

Then copy all the files from this delivery into that project, overwriting
`lib/main.dart`, `pubspec.yaml`, etc., and merging the `lib/` folder.

## 2. Install dependencies
```bash
flutter pub get
```

## 3. Connect Firebase (REQUIRED — the app will not build without this)
`lib/firebase_options.dart` in this delivery is a **placeholder**. Generate the real one:

```bash
dart pub global activate flutterfire_cli
firebase login          # if you haven't already
flutterfire configure
```

Pick/create your Firebase project and the platforms you need (Android/iOS).
This automatically overwrites `lib/firebase_options.dart` with real keys and
drops `google-services.json` / `GoogleService-Info.plist` into place.

In the Firebase Console, enable:
- **Authentication → Sign-in method → Email/Password**
- **Firestore Database** (start in production mode, then publish the rules below)

Deploy the included security rules:
```bash
firebase deploy --only firestore:rules
```
(or paste the contents of `firestore.rules` into the Firestore console's Rules tab).

## 4. Location permission (needed for prayer times)
**Android** — add to `android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

**iOS** — add to `ios/Runner/Info.plist`:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We use your location to calculate accurate prayer times.</string>
```

Also make sure `minSdkVersion` in `android/app/build.gradle` is at least 21
(required by Firebase).

## 5. Run it
```bash
flutter run
```

## Firestore data shape
```
users/{uid}
  name, email, createdAt

users/{uid}/exercises/{autoId}
  muscleGroup, exerciseName, weight, reps, date

users/{uid}/prayers/{yyyy-MM-dd}
  fajr:    { onTime: bool, delayed: bool }
  dhuhr:   { onTime: bool, delayed: bool }
  asr:     { onTime: bool, delayed: bool }
  maghrib: { onTime: bool, delayed: bool }
  isha:    { onTime: bool, delayed: bool }

users/{uid}/weights/{yyyy-MM-dd}
  date, weight
```

## Notes / things you may want to tweak
- Prayer calculation method defaults to **Muslim World League**. `adhan_dart`'s
  `CalculationMethod` also offers `egyptian()`, `karachi()`, `northAmerica()`,
  `ummAlQura()`, etc. — swap it in `prayer_screen.dart` if you prefer a different one.
- Weight is stored in kg; change the label/conversion in `weight_screen.dart` if you want lb.
- The "Coming Soon" tile is inert on purpose — wire it up whenever you decide the 4th feature.
