import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'websocket_service.dart'
    show AlertItem, alertsProvider, dismissedAlertsProvider; // AlertItem defined there; reuse the model

// ============= Models =============

class SensorReading {
  final String deviceId;
  final DateTime timestamp;
  final double level;
  final double volume;
  final double flowRate;
  final bool pumpActive;
  final double turbidity;
  final double ph;
  final double tds;
  final String status;

  const SensorReading({
    required this.deviceId,
    required this.timestamp,
    required this.level,
    required this.volume,
    required this.flowRate,
    required this.pumpActive,
    required this.turbidity,
    required this.ph,
    required this.tds,
    required this.status,
  });

  factory SensorReading.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    final ts = d['timestamp'];
    return SensorReading(
      deviceId: d['device_id'] ?? '',
      timestamp: ts is Timestamp ? ts.toDate() : DateTime.now(),
      level: (d['level'] ?? 0).toDouble(),
      volume: (d['volume'] ?? 0).toDouble(),
      flowRate: (d['flow_rate'] ?? 0).toDouble(),
      pumpActive: d['pump_active'] ?? false,
      turbidity: (d['turbidity'] ?? 0).toDouble(),
      ph: (d['ph'] ?? 0).toDouble(),
      tds: (d['tds'] ?? 0).toDouble(),
      status: d['status'] ?? 'unknown',
    );
  }
}

class UserProfile {
  final String uid;
  final String name;
  final String email;
  final String location;
  final DateTime? createdAt;

  const UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    this.location = '',
    this.createdAt,
  });

  factory UserProfile.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    final ts = d['created_at'];
    return UserProfile(
      uid: doc.id,
      name: d['name'] ?? '',
      email: d['email'] ?? '',
      location: d['location'] ?? '',
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

// ─── User Thresholds ──────────────────────────────────────────────────────

class UserThresholds {
  final double turbidityMin;       // NTU — optimal lower bound
  final double turbidityMax;       // NTU — optimal upper bound
  final double turbidityCriticalMin; // NTU — critical lower bound (too clear)
  final double turbidityCriticalMax; // NTU — critical upper bound (very cloudy)
  final double phMin;         // pH below this is warning
  final double phMax;         // pH above this is warning
  final double tdsMax;        // ppm — above this is warning/critical
  final double levelMin;      // % — below this is warning
  final double levelHigh;     // % — above this triggers full-tank alert

  const UserThresholds({
    this.turbidityMin = 10.0,
    this.turbidityMax = 50.0,
    this.turbidityCriticalMin = 5.0,
    this.turbidityCriticalMax = 100.0,
    this.phMin = 6.0,
    this.phMax = 9.5,
    this.tdsMax = 1000.0,
    this.levelMin = 20.0,
    this.levelHigh = 90.0,
  });

  UserThresholds copyWith({
    double? turbidityMin,
    double? turbidityMax,
    double? turbidityCriticalMin,
    double? turbidityCriticalMax,
    double? phMin,
    double? phMax,
    double? tdsMax,
    double? levelMin,
    double? levelHigh,
  }) =>
      UserThresholds(
        turbidityMin: turbidityMin ?? this.turbidityMin,
        turbidityMax: turbidityMax ?? this.turbidityMax,
        turbidityCriticalMin: turbidityCriticalMin ?? this.turbidityCriticalMin,
        turbidityCriticalMax: turbidityCriticalMax ?? this.turbidityCriticalMax,
        phMin: phMin ?? this.phMin,
        phMax: phMax ?? this.phMax,
        tdsMax: tdsMax ?? this.tdsMax,
        levelMin: levelMin ?? this.levelMin,
        levelHigh: levelHigh ?? this.levelHigh,
      );

  Map<String, dynamic> toMap() => {
        'turbidity_min': turbidityMin,
        'turbidity_max': turbidityMax,
        'turbidity_critical_min': turbidityCriticalMin,
        'turbidity_critical_max': turbidityCriticalMax,
        'ph_min': phMin,
        'ph_max': phMax,
        'tds_max': tdsMax,
        'level_min': levelMin,
        'level_high': levelHigh,
      };

  factory UserThresholds.fromMap(Map<String, dynamic> m) => UserThresholds(
        turbidityMin: (m['turbidity_min'] ?? 10.0).toDouble(),
        turbidityMax: (m['turbidity_max'] ?? 50.0).toDouble(),
        turbidityCriticalMin: (m['turbidity_critical_min'] ?? 5.0).toDouble(),
        turbidityCriticalMax: (m['turbidity_critical_max'] ?? 100.0).toDouble(),
        phMin: (m['ph_min'] ?? 6.0).toDouble(),
        phMax: (m['ph_max'] ?? 9.5).toDouble(),
        tdsMax: (m['tds_max'] ?? 1000.0).toDouble(),
        levelMin: (m['level_min'] ?? 20.0).toDouble(),
        levelHigh: (m['level_high'] ?? 90.0).toDouble(),
      );
}

// ============= Service =============

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Stream of the latest [limit] sensor readings for a device,
  /// ordered by timestamp descending.
  /// Uses composite index: device_id ASC + timestamp DESC.
  Stream<List<SensorReading>> latestReadingsStream(
    String deviceId, {
    int limit = 50,
  }) {
    return _db
        .collection('sensor_readings')
        .where('device_id', isEqualTo: deviceId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(SensorReading.fromFirestore).toList());
  }

  /// Stream of the most-recent single sensor reading for a device.
  /// Uses composite index: device_id ASC + timestamp DESC.
  Stream<SensorReading?> latestReadingStream(String deviceId) {
    return _db
        .collection('sensor_readings')
        .where('device_id', isEqualTo: deviceId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
          if (snap.docs.isEmpty) return null;
          return SensorReading.fromFirestore(snap.docs.first);
        });
  }

  /// One-shot fetch of sensor readings for a device within a time window.
  /// [days] and [hours] are added together to form the lookback window.
  /// Uses composite index: device_id ASC + timestamp ASC.
  Future<List<SensorReading>> fetchReadings(String deviceId,
      {int days = 30, int hours = 0}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days, hours: hours));
    try {
      final snap = await _db
          .collection('sensor_readings')
          .where('device_id', isEqualTo: deviceId)
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
          .orderBy('timestamp')
          .get();
      return snap.docs.map(SensorReading.fromFirestore).toList();
    } catch (e, st) {
      debugPrint('[fetchReadings] ERROR: $e\n$st');
      rethrow;
    }
  }

  /// Delete ALL sensor_readings documents for [deviceId].
  /// Only deletes from the sensor_readings collection — no other data is touched.
  Future<void> deleteAllReadings(String deviceId) async {
    const int batchSize = 400; // Firestore batch write limit is 500
    while (true) {
      final snap = await _db
          .collection('sensor_readings')
          .where('device_id', isEqualTo: deviceId)
          .limit(batchSize)
          .get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  /// Save data-logging preferences for a user.
  Future<void> saveDataLoggingPrefs(
      String uid, Map<String, dynamic> prefs) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('dataLogging')
        .set(prefs, SetOptions(merge: true));
  }

  /// Load data-logging preferences for a user (returns defaults if missing).
  Future<Map<String, dynamic>> loadDataLoggingPrefs(String uid) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('dataLogging')
        .get();
    if (!doc.exists || doc.data() == null) {
      return {'automaticLogging': true, 'cloudSync': false, 'retentionDays': 30};
    }
    return doc.data()!;
  }


  /// Sensor readings for the last [hours] hours, suitable for charts.
  /// Reads only the [maxPoints] most-recent documents within the window.
  /// Uses composite index: device_id ASC + timestamp DESC.
  Stream<List<SensorReading>> historyStream(
    String deviceId, {
    int hours = 24,
    int maxPoints = 200,
  }) {
    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    return _db
        .collection('sensor_readings')
        .where('device_id', isEqualTo: deviceId)
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .orderBy('timestamp', descending: true)
        .limit(maxPoints)
        .snapshots()
        .map((snap) {
          // Reverse to get ascending order (oldest first) for chart rendering
          return snap.docs
              .map(SensorReading.fromFirestore)
              .toList()
              .reversed
              .toList();
        });
  }

  /// Fetch user profile from Firestore.
  Future<UserProfile?> getUserProfile(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists || doc.data() == null) return null;
      return UserProfile.fromFirestore(doc);
    } catch (_) {
      return null;
    }
  }

  /// Stream of user profile changes.
  Stream<UserProfile?> userProfileStream(String uid) {
    return _db.collection('users').doc(uid).snapshots().map(
      (doc) {
        if (!doc.exists || doc.data() == null) return null;
        return UserProfile.fromFirestore(doc);
      },
    );
  }

  /// Stream of user threshold settings.
  Stream<UserThresholds> userThresholdsStream(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('thresholds')
        .snapshots()
        .map((doc) {
      if (!doc.exists || doc.data() == null) return const UserThresholds();
      return UserThresholds.fromMap(doc.data()!);
    });
  }

  /// Save user threshold settings.
  Future<void> saveThresholds(String uid, UserThresholds t) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('thresholds')
        .set(t.toMap());
  }

  // ─── Device Setup ─────────────────────────────────────────────────────────

  /// Returns true if the user already has a linked device in Firestore.
  Future<bool> hasLinkedDevice(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists || doc.data() == null) return false;
      final data = doc.data()!;
      final deviceId = data['device_id'];
      return deviceId != null && (deviceId as String).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Save device setup info after pairing completes.
  ///
  /// [uid] is the current user's UID.
  /// [deviceId] is the ESP32 device identifier.
  /// [deviceName] is the user-assigned name (e.g., "Kitchen Tank").
  /// [location] is an optional location/room label.
  /// [connectionType] is 'wifi' or 'bluetooth'.
  /// [ownerName] is the full name from the Device Information form.
  /// [ownerPhone] is the phone number from the Device Information form.
  Future<void> saveDeviceSetup({
    required String uid,
    required String deviceId,
    String deviceName = 'My AGOS Device',
    String location = '',
    String connectionType = 'wifi',
    String ownerName = '',
    String ownerPhone = '',
  }) async {
    final batch = _db.batch();

    // Update user profile with device link + extra info
    final userUpdate = <String, dynamic>{'device_id': deviceId};
    if (ownerName.isNotEmpty) userUpdate['name'] = ownerName;
    if (ownerPhone.isNotEmpty) userUpdate['phone'] = ownerPhone;
    if (location.isNotEmpty) userUpdate['location'] = location;
    batch.set(
      _db.collection('users').doc(uid),
      userUpdate,
      SetOptions(merge: true),
    );

    // Save device record
    batch.set(
      _db.collection('devices').doc(deviceId),
      {
        'name': deviceName,
        'location': location,
        'owner_uid': uid,
        'connection_type': connectionType,
        'created_at': FieldValue.serverTimestamp(),
        'last_seen': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  /// Returns the linked device ID for [uid], or null if none.
  Future<String?> getLinkedDeviceId(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists || doc.data() == null) return null;
      return doc.data()!['device_id'] as String?;
    } catch (_) {
      return null;
    }
  }
}

// ============= Providers =============

/// The FirestoreService singleton.
final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  return FirestoreService();
});

/// Emits the current Firebase user whenever auth state changes.
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// Convenience: the currently signed-in user (null if signed out).
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});

/// Latest single reading for [deviceId] — real-time Firestore stream.
final latestReadingProvider =
    StreamProvider.family<SensorReading?, String>((ref, deviceId) {
  final service = ref.watch(firestoreServiceProvider);
  return service.latestReadingStream(deviceId);
});

/// Last [limit] readings for [deviceId] as (deviceId, limit) family.
final recentReadingsProvider =
    StreamProvider.family<List<SensorReading>, (String, int)>((ref, args) {
  final (deviceId, limit) = args;
  final service = ref.watch(firestoreServiceProvider);
  return service.latestReadingsStream(deviceId, limit: limit);
});

/// History stream for chart data: (deviceId, hours, tick).
/// The [tick] parameter is incremented periodically to force a new Firestore
/// subscription with a fresh cutoff timestamp, keeping the chart window current.
final readingHistoryProvider =
    StreamProvider.family<List<SensorReading>, (String, int, int)>((ref, args) {
  final (deviceId, hours, _) = args; // tick is intentionally ignored — only forces new instance
  final service = ref.watch(firestoreServiceProvider);
  return service.historyStream(deviceId, hours: hours);
});

/// User profile stream for the signed-in user.
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(null);
  final service = ref.watch(firestoreServiceProvider);
  return service.userProfileStream(user.uid);
});

/// User threshold settings stream for the signed-in user.
final userThresholdsProvider = StreamProvider<UserThresholds>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(const UserThresholds());
  final service = ref.watch(firestoreServiceProvider);
  return service.userThresholdsStream(user.uid);
});

/// Whether the current user has a linked AGOS device.
/// Returns false while loading or if not signed in.
final hasLinkedDeviceProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  final service = ref.watch(firestoreServiceProvider);
  return service.hasLinkedDevice(user.uid);
});

/// The real device ID from Firestore for the signed-in user.
/// Returns null while loading or if no device is linked.
final linkedDeviceIdProvider = FutureProvider<String?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final service = ref.watch(firestoreServiceProvider);
  return service.getLinkedDeviceId(user.uid);
});

// ─── Setup State (transient, lives only during the setup flow) ─────────────

class SetupState {
  final String deviceId;
  final String deviceName;
  final String location;
  final String connectionType;
  final String ownerName;
  final String ownerEmail;
  final String ownerPhone;

  const SetupState({
    this.deviceId = '',
    this.deviceName = 'My AGOS Device',
    this.location = '',
    this.connectionType = 'wifi',
    this.ownerName = '',
    this.ownerEmail = '',
    this.ownerPhone = '',
  });

  SetupState copyWith({
    String? deviceId,
    String? deviceName,
    String? location,
    String? connectionType,
    String? ownerName,
    String? ownerEmail,
    String? ownerPhone,
  }) {
    return SetupState(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      location: location ?? this.location,
      connectionType: connectionType ?? this.connectionType,
      ownerName: ownerName ?? this.ownerName,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      ownerPhone: ownerPhone ?? this.ownerPhone,
    );
  }
}

class SetupStateNotifier extends StateNotifier<SetupState> {
  SetupStateNotifier() : super(const SetupState());

  void setDeviceId(String id) => state = state.copyWith(deviceId: id);
  void setConnectionType(String type) =>
      state = state.copyWith(connectionType: type);
  void setDeviceInfo({
    required String ownerName,
    required String ownerEmail,
    required String ownerPhone,
    required String location,
    String? deviceName,
  }) {
    state = state.copyWith(
      ownerName: ownerName,
      ownerEmail: ownerEmail,
      ownerPhone: ownerPhone,
      location: location,
      deviceName: deviceName ?? state.deviceName,
    );
  }

  void reset() => state = const SetupState();
}

final setupStateProvider =
    StateNotifierProvider<SetupStateNotifier, SetupState>((ref) {
  return SetupStateNotifier();
});

// ============= Alert helpers =============

/// Converts recent SensorReadings into AlertItems based on threshold rules.
/// This lets the notifications screen show historical alerts even when the
/// WebSocket is offline or a fresh session just started.
List<AlertItem> _alertsFromReadings(
    List<SensorReading> readings, UserThresholds t) {
  final alerts = <AlertItem>[];
  for (final r in readings) {
    final id = '${r.deviceId}_${r.timestamp.millisecondsSinceEpoch}';
    final ts = r.timestamp.toIso8601String();

    if (r.turbidity > t.turbidityMax) {
      final criticalThreshold = t.turbidityMax * 1.5;
      alerts.add(AlertItem(
        id: '${id}_turbidity',
        type: 'water_quality',
        title: 'High Turbidity Detected',
        description:
            'Turbidity is ${r.turbidity.toStringAsFixed(1)} NTU — exceeds ${t.turbidityMax.toStringAsFixed(0)} NTU limit.',
        timestamp: ts,
        severity: r.turbidity > criticalThreshold ? 'critical' : 'warning',
      ));
    }

    if (r.ph < t.phMin || r.ph > t.phMax) {
      final low = r.ph < t.phMin;
      final criticalLow = t.phMin - 1.0;
      final criticalHigh = t.phMax + 0.5;
      alerts.add(AlertItem(
        id: '${id}_ph',
        type: 'water_quality',
        title: low ? 'pH Too Low' : 'pH Too High',
        description:
            'pH level is ${r.ph.toStringAsFixed(1)} — outside safe range ${t.phMin}–${t.phMax}.',
        timestamp: ts,
        severity: (r.ph < criticalLow || r.ph > criticalHigh) ? 'critical' : 'warning',
      ));
    }

    if (r.tds > t.tdsMax) {
      final criticalThreshold = t.tdsMax * 1.125;
      alerts.add(AlertItem(
        id: '${id}_tds',
        type: 'water_quality',
        title: 'High TDS Detected',
        description:
            'TDS is ${r.tds.toStringAsFixed(0)} ppm — exceeds ${t.tdsMax.toStringAsFixed(0)} ppm limit.',
        timestamp: ts,
        severity: r.tds > criticalThreshold ? 'critical' : 'warning',
      ));
    }

    if (r.level < t.levelMin) {
      alerts.add(AlertItem(
        id: '${id}_level',
        type: 'system',
        title: 'Low Water Level',
        description:
            'Tank level is ${r.level.toStringAsFixed(0)}% — consider refilling.',
        timestamp: ts,
        severity: r.level < (t.levelMin / 2) ? 'critical' : 'warning',
      ));
    }

    if (r.pumpActive) {
      alerts.add(AlertItem(
        id: '${id}_pump',
        type: 'system',
        title: 'Pump Activated',
        description: 'Automatic pump turned on at ${_fmtDt(r.timestamp)}.',
        timestamp: ts,
        severity: 'info',
      ));
    }
  }

  // Sort newest-first
  alerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return alerts;
}

String _fmtDt(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Stream of [AlertItem]s derived from the last 50 Firestore readings.
/// Thresholds are loaded from the current user's settings.
final firestoreAlertsProvider =
    StreamProvider.family<List<AlertItem>, String>((ref, deviceId) {
  final service = ref.watch(firestoreServiceProvider);
  final thresholds = ref.watch(userThresholdsProvider).valueOrNull ??
      const UserThresholds();
  return service
      .latestReadingsStream(deviceId, limit: 50)
      .map((readings) => _alertsFromReadings(readings, thresholds));
});

/// True when there is at least one alert (Firestore-derived or WebSocket)
/// that has not been dismissed by the user.
/// Returns false (no dot) until the dismissed-IDs set has loaded from prefs.
final hasUnreadAlertsProvider = Provider<bool>((ref) {
  final deviceId =
      ref.watch(linkedDeviceIdProvider).valueOrNull ?? '';
  if (deviceId.isEmpty) return false;
  final dismissedState = ref.watch(dismissedAlertsProvider);
  // Don't show dot until we know which IDs are already dismissed
  if (!dismissedState.loaded) return false;
  final dismissed = dismissedState.ids;
  final fsAlerts =
      ref.watch(firestoreAlertsProvider(deviceId)).valueOrNull ?? [];
  final wsAlerts = ref.watch(alertsProvider);
  final allIds = {...fsAlerts.map((a) => a.id), ...wsAlerts.map((a) => a.id)};
  return allIds.any((id) => !dismissed.contains(id));
});
