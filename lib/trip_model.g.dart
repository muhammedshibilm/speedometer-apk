// GENERATED CODE - DO NOT MODIFY BY HAND

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
    );
  }

  @override
  void write(BinaryWriter writer, TripModel obj) {
    writer
      ..writeByte(6)
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
      ..write(obj.name);
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
