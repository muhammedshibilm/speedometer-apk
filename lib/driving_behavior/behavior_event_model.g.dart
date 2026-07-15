// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'behavior_event_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BehaviorEventModelAdapter extends TypeAdapter<BehaviorEventModel> {
  @override
  final int typeId = 2;

  @override
  BehaviorEventModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BehaviorEventModel(
      tripKey: fields[0] as int,
      eventType: fields[1] as String,
      timestamp: fields[2] as DateTime,
      severity: fields[3] as double,
    );
  }

  @override
  void write(BinaryWriter writer, BehaviorEventModel obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.tripKey)
      ..writeByte(1)
      ..write(obj.eventType)
      ..writeByte(2)
      ..write(obj.timestamp)
      ..writeByte(3)
      ..write(obj.severity);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BehaviorEventModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
