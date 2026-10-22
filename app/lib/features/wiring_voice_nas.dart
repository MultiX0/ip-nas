// Puts the paired NAS behind the core nasHubProvider (see main.dart).
import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/providers.dart';
import 'nas/nas_service.dart';

List<Override> voiceNasOverrides() => [
      // Null until the user pairs a NAS in onboarding or on /nas.
      nasHubProvider.overrideWith((ref) => ref.watch(activeNasProvider).value),
    ];
