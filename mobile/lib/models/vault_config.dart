class VaultConfig {
  const VaultConfig({required this.coupleNames, required this.startDate, required this.updatedAt});

  final String coupleNames;
  final String startDate;
  final int updatedAt;

  VaultConfig copyWith({String? coupleNames, String? startDate, int? updatedAt}) => VaultConfig(
        coupleNames: coupleNames ?? this.coupleNames,
        startDate: startDate ?? this.startDate,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => {
        'coupleNames': coupleNames,
        'startDate': startDate,
        'updatedAt': updatedAt,
      };
}
