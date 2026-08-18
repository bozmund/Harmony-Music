/// Browser downloads are governed by browser permissions, not Android storage
/// permissions.
class PermissionService {
  static Future<bool> getExtStoragePermission() async => true;
}
