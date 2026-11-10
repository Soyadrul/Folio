import 'dart:io';

import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException;
import 'package:permission_handler/permission_handler.dart';

const MethodChannel _screenChannel = MethodChannel('folio/screen');

/// Whether the granted permissions are enough to list `.epub` files.
///
/// `READ_EXTERNAL_STORAGE` does not grant direct path access to non-media
/// files once the app targets API 30, even though `permission_handler` keeps
/// reporting it as granted. Only "all files access" works from Android 11.
bool storageAccessSufficient({
  required int sdk,
  required bool manageGranted,
  required bool storageGranted,
}) {
  if (manageGranted) return true;
  if (sdk >= 30) return false;
  return storageGranted;
}

Future<int> androidSdkInt() async {
  if (!Platform.isAndroid) return 0;
  try {
    return await _screenChannel.invokeMethod<int>('sdkInt') ?? 0;
  } on PlatformException {
    return 0;
  } on MissingPluginException {
    return 0;
  }
}

Future<bool> hasStorageAccess() async {
  if (!Platform.isAndroid) return true;
  final sdk = await androidSdkInt();
  return storageAccessSufficient(
    sdk: sdk,
    manageGranted: await Permission.manageExternalStorage.isGranted,
    storageGranted: await Permission.storage.isGranted,
  );
}

Future<bool> requestStorageAccess() async {
  if (!Platform.isAndroid) return true;
  if (await hasStorageAccess()) return true;
  final sdk = await androidSdkInt();
  if (sdk >= 30) {
    return (await Permission.manageExternalStorage.request()).isGranted;
  }
  return (await Permission.storage.request()).isGranted;
}
