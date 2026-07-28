/// API models mirroring `backend/app/api/v1/schemas.py`.
///
/// Hand-written rather than generated from `contracts/openapi.yaml`. Codegen
/// is the right call once the schema settles, but while routes are still
/// moving, a build_runner step between every backend edit and a working app
/// costs more than it saves. The field names here match the JSON exactly, so
/// swapping in a generated client later is mechanical.
library;

class Species {
  const Species({required this.id, required this.scientificName, this.commonName});

  final String id;
  final String scientificName;
  final String? commonName;

  factory Species.fromJson(Map<String, dynamic> json) => Species(
        id: json['id'] as String,
        scientificName: json['scientific_name'] as String,
        commonName: json['common_name'] as String?,
      );

  String get displayName => commonName ?? scientificName;
}

class Pot {
  const Pot({
    required this.id,
    required this.name,
    this.deviceId,
    this.photoUrl,
    this.identifyConfidence,
    this.autoWaterEnabled = false,
    this.autoWaterThresholdPct = 25,
    this.species,
  });

  final String id;
  final String name;
  final String? deviceId;
  final String? photoUrl;
  final double? identifyConfidence;
  final bool autoWaterEnabled;
  final double autoWaterThresholdPct;
  final Species? species;

  bool get hasDevice => deviceId != null;

  factory Pot.fromJson(Map<String, dynamic> json) => Pot(
        id: json['id'] as String,
        name: json['name'] as String,
        deviceId: json['device_id'] as String?,
        photoUrl: json['photo_url'] as String?,
        identifyConfidence: (json['identify_confidence'] as num?)?.toDouble(),
        autoWaterEnabled: json['auto_water_enabled'] as bool? ?? false,
        autoWaterThresholdPct:
            (json['auto_water_threshold_pct'] as num?)?.toDouble() ?? 25,
        species: json['species'] == null
            ? null
            : Species.fromJson(json['species'] as Map<String, dynamic>),
      );
}

class Reading {
  const Reading({
    required this.time,
    this.tempC,
    this.rh,
    this.soilPct,
    this.lux,
    this.battMv,
    this.flags = 0,
  });

  final DateTime time;
  final double? tempC;
  final double? rh;
  final double? soilPct;
  final double? lux;
  final int? battMv;
  final int flags;

  factory Reading.fromJson(Map<String, dynamic> json) => Reading(
        time: DateTime.parse(json['time'] as String),
        tempC: (json['temp_c'] as num?)?.toDouble(),
        rh: (json['rh'] as num?)?.toDouble(),
        soilPct: (json['soil_pct'] as num?)?.toDouble(),
        lux: (json['lux'] as num?)?.toDouble(),
        battMv: json['batt_mv'] as int?,
        flags: json['flags'] as int? ?? 0,
      );
}

class IdealRange {
  const IdealRange({
    required this.min,
    required this.max,
    this.idealMin,
    this.idealMax,
    this.unit = '',
  });

  final double min;
  final double max;
  final double? idealMin;
  final double? idealMax;
  final String unit;

  factory IdealRange.fromJson(Map<String, dynamic> json) => IdealRange(
        min: (json['min'] as num).toDouble(),
        max: (json['max'] as num).toDouble(),
        idealMin: (json['ideal_min'] as num?)?.toDouble(),
        idealMax: (json['ideal_max'] as num?)?.toDouble(),
        unit: json['unit'] as String? ?? '',
      );
}

class HealthParameter {
  const HealthParameter({
    required this.parameter,
    required this.label,
    required this.status,
    required this.message,
    this.value,
    this.idealRange,
  });

  /// One of: soil_pct, temp_c, rh, lux
  final String parameter;
  final String label;

  /// One of: good, warning, bad, unknown
  final String status;
  final String message;
  final double? value;
  final IdealRange? idealRange;

  factory HealthParameter.fromJson(Map<String, dynamic> json) => HealthParameter(
        parameter: json['parameter'] as String,
        label: json['label'] as String,
        status: json['status'] as String,
        message: json['message'] as String,
        value: (json['value'] as num?)?.toDouble(),
        idealRange: json['ideal_range'] == null
            ? null
            : IdealRange.fromJson(json['ideal_range'] as Map<String, dynamic>),
      );

  /// Normalised 0..1 position within the acceptable band, for gauges.
  /// Null when there is no value or no guidance to place it against.
  double? get normalised {
    final r = idealRange;
    final v = value;
    if (r == null || v == null) return null;
    final span = r.max - r.min;
    if (span <= 0) return null;
    return ((v - r.min) / span).clamp(0.0, 1.0);
  }
}

class Health {
  const Health({
    required this.status,
    required this.confidence,
    required this.profileSource,
    required this.parameters,
    required this.issues,
    required this.recommendations,
    required this.notes,
    this.score,
  });

  final String status;

  /// species | genus | default — how much to trust the thresholds.
  /// Surfaced in the UI: "we know this plant needs 40-60%" and "we are
  /// guessing from the genus" should not look the same.
  final String confidence;
  final String profileSource;
  final List<HealthParameter> parameters;
  final List<String> issues;
  final List<String> recommendations;
  final List<String> notes;

  /// Null when nothing could be assessed — distinct from a score of 0.
  final int? score;

  bool get isGuess => confidence == 'default';

  factory Health.fromJson(Map<String, dynamic> json) => Health(
        status: json['status'] as String,
        confidence: json['confidence'] as String,
        profileSource: json['profile_source'] as String,
        score: json['score'] as int?,
        parameters: (json['parameters'] as List<dynamic>)
            .map((e) => HealthParameter.fromJson(e as Map<String, dynamic>))
            .toList(),
        issues: (json['issues'] as List<dynamic>).cast<String>(),
        recommendations: (json['recommendations'] as List<dynamic>).cast<String>(),
        notes: (json['notes'] as List<dynamic>).cast<String>(),
      );
}

class PotSnapshot {
  const PotSnapshot({
    required this.potId,
    required this.online,
    this.deviceId,
    this.reading,
    this.health,
  });

  final String potId;
  final String? deviceId;
  final bool online;
  final Reading? reading;
  final Health? health;

  factory PotSnapshot.fromJson(Map<String, dynamic> json) => PotSnapshot(
        potId: json['pot_id'] as String,
        deviceId: json['device_id'] as String?,
        online: json['online'] as bool? ?? false,
        reading: json['reading'] == null
            ? null
            : Reading.fromJson(json['reading'] as Map<String, dynamic>),
        health: json['health'] == null
            ? null
            : Health.fromJson(json['health'] as Map<String, dynamic>),
      );
}

class SeriesPoint {
  const SeriesPoint({
    required this.bucket,
    this.tempC,
    this.rh,
    this.soilPct,
    this.lux,
    this.samples = 0,
  });

  final DateTime bucket;
  final double? tempC;
  final double? rh;
  final double? soilPct;
  final double? lux;
  final int samples;

  factory SeriesPoint.fromJson(Map<String, dynamic> json) => SeriesPoint(
        bucket: DateTime.parse(json['bucket'] as String),
        tempC: (json['temp_c'] as num?)?.toDouble(),
        rh: (json['rh'] as num?)?.toDouble(),
        soilPct: (json['soil_pct'] as num?)?.toDouble(),
        lux: (json['lux'] as num?)?.toDouble(),
        samples: json['samples'] as int? ?? 0,
      );
}
