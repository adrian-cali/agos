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

  /// Sensor readings for the last [hours] hours, suitable for charts.
  Stream<List<SensorReading>> historyStream(
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

// ============= Alert helpers =============

/// Converts recent SensorReadings into AlertItems based on threshold rules.
/// This lets the notifications screen show historical alerts even when the
/// WebSocket is offline or a fresh session just started.
List<AlertItem> _alertsFromReadings(List<SensorReading> readings) {
  final alerts = <AlertItem>[];
  for (final r in readings) {
    final id = '${r.deviceId}_${r.timestamp.millisecondsSinceEpoch}';
    final ts = r.timestamp.toIso8601String();

    if (r.turbidity > 10) {
      alerts.add(AlertItem(
        id: '${id}_turbidity',
        type: 'water_quality',
        title: 'High Turbidity Detected',
        description:
            'Turbidity is ${r.turbidity.toStringAsFixed(1)} NTU — exceeds 10 NTU limit.',
        timestamp: ts,
        severity: r.turbidity > 15 ? 'critical' : 'warning',
      ));
    }

    if (r.ph < 6.5 || r.ph > 8.5) {
      final low = r.ph < 6.5;
      alerts.add(AlertItem(
        id: '${id}_ph',
        type: 'water_quality',
        title: low ? 'pH Too Low' : 'pH Too High',
        description:
            'pH level is ${r.ph.toStringAsFixed(1)} — outside safe range 6.5–8.5.',
        timestamp: ts,
        severity: (r.ph < 5.5 || r.ph > 9.0) ? 'critical' : 'warning',
      ));
    }

    if (r.tds > 400) {
      alerts.add(AlertItem(
        id: '${id}_tds',
        type: 'water_quality',
        title: 'High TDS Detected',
        description:
            'TDS is ${r.tds.toStringAsFixed(0)} ppm — exceeds 400 ppm limit.',
        timestamp: ts,
        severity: r.tds > 450 ? 'critical' : 'warning',
      ));
    }

    if (r.level < 20) {
      alerts.add(AlertItem(
        id: '${id}_level',
        type: 'system',
        title: 'Low Water Level',
        description:
            'Tank level is ${r.level.toStringAsFixed(0)}% — consider refilling.',
        timestamp: ts,
        severity: r.level < 10 ? 'critical' : 'warning',
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
/// deviceId defaults to 'esp32-sim-001'.
final firestoreAlertsProvider =
    StreamProvider.family<List<AlertItem>, String>((ref, deviceId) {
  final service = ref.watch(firestoreServiceProvider);
  return service
      .latestReadingsStream(deviceId, limit: 50)
      .map(_alertsFromReadings);
});
