# AGiXT Mobile

A Flutter mobile app for interacting with the AGiXT AI assistant.

## Prerequisites for Ubuntu

Before you can build and run the AGiXT mobile app on Ubuntu, you need to set up your development environment.

### 1. Install Flutter

```bash
# Install required dependencies
sudo apt update
sudo apt install -y curl git unzip xz-utils zip libglu1-mesa clang cmake ninja-build pkg-config libgtk-3-dev

# Download Flutter SDK
cd ~/
wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.19.4-stable.tar.xz
tar xf flutter_linux_3.19.4-stable.tar.xz

# Add Flutter to your PATH
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
source ~/.bashrc

# Verify installation
flutter --version
```

### 2. Install Android Studio

```bash
# Download and install Android Studio
sudo snap install android-studio --classic

# Launch Android Studio and complete the setup wizard
# Install Android SDK, Android SDK Platform, and Android Virtual Device
```

### 3. Configure Flutter

```bash
# Accept licenses
flutter doctor --android-licenses

# Run Flutter doctor to verify setup
flutter doctor
```

## Building and Running the App

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/agixt-mobile.git
cd agixt-mobile
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Run the App

#### On an Emulator

```bash
# Start an Android emulator from Android Studio
# or use this command:
flutter emulators --launch <emulator_id>

# Run the app
flutter run
```

#### On a Physical Device

```bash
# Connect your device via USB and enable USB debugging
flutter devices # Check if your device is recognized
flutter run -d <device_id>
```

### 4. Build APK for Distribution

```bash
# Build an APK
flutter build apk --release

# The APK will be available at:
# build/app/outputs/flutter-apk/app-release.apk
```

## Customizing App Configuration

You can customize the app by modifying the environment variables defined in the pubspec.yaml file:

```yaml
define:
  APP_NAME: "AGiXT" # Your custom app name
  AGIXT_SERVER: "https://api.your-server.com" # Your API server URL
  APP_URI: "https://your-website.com" # Your website URL
```

## Troubleshooting

- If you encounter permission issues with the Android SDK, run:
  ```bash
  sudo chown -R $USER:$USER ~/Android
  ```

- For Bluetooth connectivity issues, ensure your device has Bluetooth permissions granted.

- If you face build errors, try running:
  ```bash
  flutter clean
  flutter pub get
  flutter run
  ```

## Additional Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Dart Programming Language](https://dart.dev/guides)
- [AGiXT Documentation](https://agixt.dev/)
