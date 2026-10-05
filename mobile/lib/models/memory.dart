import 'dart:typed_data';

class Memory {
  final String id;
  final String caption;
  final String date;
  final String? location;
  final Uint8List? imageBytes;
  final String mime;
  final int width;
  final int height;
  final int updatedAt;
  final bool deleted;

  Memory({
    required this.id,
    required this.caption,
    required this.date,
    this.location,
    this.imageBytes,
    this.mime = 'image/webp',
    this.width = 0,
    this.height = 0,
    required this.updatedAt,
    this.deleted = false,
  });

  factory Memory.fromMap(Map<String, dynamic> map, {Uint8List? imageBytes}) {
    return Memory(
      id: map['id'] as String,
      caption: map['caption'] as String? ?? '',
      date: map['date'] as String? ?? '',
      location: map['location'] as String?,
      imageBytes: imageBytes,
      mime: map['mime'] as String? ?? 'image/webp',
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
      deleted: map['deleted'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'caption': caption,
      'date': date,
      'location': location,
      'mime': mime,
      'width': width,
      'height': height,
      'updatedAt': updatedAt,
      'deleted': deleted,
    };
  }

  Memory copyWith({
    String? caption,
    String? date,
    String? location,
    Uint8List? imageBytes,
    String? mime,
    int? width,
    int? height,
    int? updatedAt,
    bool? deleted,
  }) {
    return Memory(
      id: id,
      caption: caption ?? this.caption,
      date: date ?? this.date,
      location: location ?? this.location,
      imageBytes: imageBytes ?? this.imageBytes,
      mime: mime ?? this.mime,
      width: width ?? this.width,
      height: height ?? this.height,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }
}
