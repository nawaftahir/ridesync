class Rider {
  const Rider({required this.id, required this.name});

  final int id;
  final String name;

  String get initial => name.isEmpty ? '?' : name[0].toUpperCase();
}