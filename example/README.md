# My Storage Engine Example

A sample Flutter application demonstrating the high-level Document API of `flare_db`.

## Features Demonstrated

- **Database Initialization**: Opening a local B-Tree database.
- **Strong Typing**: Using `withConverter` to work with Dart `User` and `Profile` objects.
- **Nested Structures**: Storing and retrieving objects with nested data.
- **Advanced Types**: Usage of `Timestamp` and `GeoPoint` fields.
- **UI Integration**: Displaying retrieved data in a Flutter view.

## How to Run

1. Ensure you have the Flutter SDK installed.
2. Clone the repository and navigate to the `example` directory.
3. Fetch dependencies:
   ```bash
   flutter pub get
   ```
4. Run the app on a connected device or emulator:
   ```bash
   flutter run
   ```

Note: This package uses FFI and requires a C++ compiler to be available in your environment for building native assets.
