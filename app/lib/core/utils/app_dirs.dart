import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The folder for Nur's own files: the database, attachments, skills and voice messages. On Linux that is
/// ~/.local/share/app.nur.nur, because the Documents folder there needs the xdg-user-dir tool and belongs to the user.
Future<Directory> appFilesDir() => Platform.isLinux ? getApplicationSupportDirectory() : getApplicationDocumentsDirectory();
