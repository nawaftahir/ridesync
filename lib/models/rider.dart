class Rider {
  const Rider({required this.id, required this.name});

  final int id;
  final String name;

  // First letter of the name, shown inside the avatar circle.
  String get initial {
    if (name.isEmpty) {
      return '?';
    }
    return name[0].toUpperCase();
  }
}
