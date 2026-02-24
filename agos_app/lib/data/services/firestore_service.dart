import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'websocket_service.dart'
    show AlertItem; // AlertItem defined there; reuse the model

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
  final DateTime? createdAt;

  const UserProfile({
    required this.uid,
    required this.name,
    required this.email,
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
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

// ─── User Thresholds ──────────────────────────────────────────────────────

class UserThresholds {
  final double turbidityMax;  // NTU — above this is warning/critical
  final double phMin;         // pH below this is warning
  final double phMax;         // pH above this is warning
  final double tdsMax;        // ppm — above this is warning/critical
  final double levelMin;      // % — below this is warning

  const UserThresholds({
    this.turbidityMax = 10.0,
    this.phMin = 6.5,
    this.phMax = 8.5,
    this.tdsMax = 400.0,
    this.levelMin = 20.0,
  });

  UserThresholds copyWith({
    double? turbidityMax,
    double? phMin,
    double? phMax,
    double? tdsMax,
    double? levelMin,
  }) =>
      UserThresholds(
        turbidityMax: turbidityMax ?? this.turbidityMax,
        phMin: phMin ?? this.phMin,
        phMax: phMax ?? this.phMax,
        tdsMax: tdsMax ?? this.tdsMax,
        levelMin: levelMin ?? this.levelMin,
      );

  Map<String, dynamic> toMap() => {
        'turbidity_max': turbidityMax,
        'ph_min': phMin,
        'ph_max': phMax,
        'tds_max': tdsMax,
        'level_min': levelMin,
      };

  factory UserThresholds.fromMap(Map<String, dynamic> m) => UserThresholds(
        turbidityMax: (m['turbidity_max'] ?? 10.0).toDouble(),
        phMin: (m['ph_min'] ?? 6.5).toDouble(),
        phMax: (m['ph_max'] ?? 8.5).toDouble(),
        tdsMax: (m['tds_max'] ?? 400.0).toDouble(),
        levelMin: (m['level_min'] ?? 20.0).toDouble(),
      );
}

// ============= Service =============

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Stream of the latest [limit] sensor readings for a device,
  /// ordered by timestamp descending.
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
        .map(
          (snap) => snap.docs.map(SensorReading.fromFirestore).toList(),
        );
  }

  /// Stream of the most-recent single sensor reading for a device.
  Stream<SensorReading?> latestReadingStream(String deviceId) {
    return _db
        .collection('sensor_readings')
        .where('device_id', isEqualTo: deviceId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.isEmpty ? null : SensorReading.fromFirestore(snap.docs.first),
        );
  }

  /// One-shot fetch of sensor readings for a device over the past [days] days.
  Future<List<SensorReading>> fetchReadings(String deviceId,
      {int days = 30}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final snap = await _db
        .collection('sensor_readings')
        .where('device_id', isEqualTo: deviceId)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
        .orderBy('timestamp', descending: false)
        .get();
    return snap.docs.map(SensorReading.fromFirestore).toList();
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


    String deviceId, {
    int hours = 24,
  }) {
    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    return _db
        .collection('sensor_readings')
        .where('device_id', isEqualTo: deviceId)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map(
          (snap) => snap.docs.map(SensorReading.fromFirestore).toList(),
        );
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

/// History stream for chart data: (deviceId, hours).
final readingHistoryProvider =
    StreamProvider.family<List<SensorReading>, (String, int)>((ref, args) {
  final (deviceId, hours) = args;
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
