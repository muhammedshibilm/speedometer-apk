// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'camera_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CameraModelAdapter extends TypeAdapter<CameraModel> {
  @override
  final int typeId = 1;

  @override
  CameraModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CameraModel(
      osmId: fields[0] as String,
      lat: fields[1] as double,
      lon: fields[2] as double,
      type: fields[3] as String,
      maxspeed: fields[4] as int?,
      source: fields[5] as String,
      lastUpdated: fields[6] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, CameraModel obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.osmId)
      ..writeByte(1)
      ..write(obj.lat)
      ..writeByte(2)
      ..write(obj.lon)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.maxspeed)
      ..writeByte(5)
      ..write(obj.source)
      ..writeByte(6)
      ..write(obj.lastUpdated);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
