// Saved local riding crew (e.g. "Margalla Dawn Riders") for quick convoy starts.
class RidingCrew {
  const RidingCrew({
    required this.id,
    required this.name,
    required this.members,
  });

  final String id;
  final String name;
  final List<String> members;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'members': members};

  static RidingCrew? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final rawMembers = json['members'];
    if (id is! String ||
        id.trim().isEmpty ||
        name is! String ||
        name.trim().isEmpty) {
      return null;
    }
    final members = rawMembers is List
        ? rawMembers
              .whereType<String>()
              .map((m) => m.trim())
              .where((m) => m.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    return RidingCrew(id: id.trim(), name: name.trim(), members: members);
  }
}
