class PhoneModel {
  const PhoneModel({
    required this.provider,
    required this.id,
    required this.name,
    this.contextWindow,
  });

  factory PhoneModel.fromJson(Object? value) {
    if (value is! Map ||
        value['provider'] is! String ||
        value['id'] is! String ||
        value['name'] is! String ||
        (value['contextWindow'] != null &&
            (value['contextWindow'] is! int ||
                (value['contextWindow'] as int) <= 0))) {
      throw const FormatException('Invalid model catalog entry');
    }
    return PhoneModel(
      provider: value['provider'] as String,
      id: value['id'] as String,
      name: value['name'] as String,
      contextWindow: value['contextWindow'] as int?,
    );
  }

  final String provider;
  final String id;
  final String name;
  final int? contextWindow;
  String get reference => '$provider/$id';
}
