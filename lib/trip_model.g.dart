// GENERATED CODE - DO NOT MODIFY BY HAND
// (Hand-updated to add fields 9-13 for behavior tracking)

part of 'trip_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TripModelAdapter extends TypeAdapter<TripModel> {
  @override
  final int typeId = 0;

  @override
  TripModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TripModel(
      startTime: fields[0] as DateTime,
      durationSeconds: fields[1] as int,
      distanceKm: fields[2] as double,
      avgSpeed: fields[3] as double,
      maxSpeed: fields[4] as double,
      name: fields[5] as String,
      speedReadings: (fields[6] as List).cast<double>(),
      latitudes: (fields[7] as List).cast<double>(),
      longitudes: (fields[8] as List).cast<double>(),
      // New fields – safe defaults for old records that lack them
      harshBrakeCount: (fields[9] as int?) ?? 0,
      harshAccelCount: (fields[10] as int?) ?? 0,
      sharpCornerCount: (fields[11] as int?) ?? 0,
      timeOverLimitPct: (fields[12] as double?) ?? 0.0,
      driveScore: (fields[13] as int?) ?? 100,
    );
  }

  @override
  void write(BinaryWriter writer, TripModel obj) {
    writer
      ..writeByte(14) // total fields
      ..writeByte(0)
      ..write(obj.startTime)
      ..writeByte(1)
      ..write(obj.durationSeconds)
      ..writeByte(2)
      ..write(obj.distanceKm)
      ..writeByte(3)
      ..write(obj.avgSpeed)
      ..writeByte(4)
      ..write(obj.maxSpeed)
      ..writeByte(5)
      ..write(obj.name)
      ..writeByte(6)
      ..write(obj.speedReadings)
      ..writeByte(7)
      ..write(obj.latitudes)
      ..writeByte(8)
      ..write(obj.longitudes)
      ..writeByte(9)
      ..write(obj.harshBrakeCount)
      ..writeByte(10)
      ..write(obj.harshAccelCount)
      ..writeByte(11)
      ..write(obj.sharpCornerCount)
      ..writeByte(12)
      ..write(obj.timeOverLimitPct)
      ..writeByte(13)
      ..write(obj.driveScore);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
