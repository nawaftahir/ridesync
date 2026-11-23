// Authenticated rider account and bearer token stored on the device.
class AuthUser {
  const AuthUser({required this.id, required this.email, required this.name});

  final int id;
  final String email;
  final String name;

  AuthUser copyWith({String? name}) =>
      AuthUser(id: id, email: email, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'name': name};

  static AuthUser? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final email = json['email'];
    final name = json['name'];
    if (id is! num || email is! String || name is! String) {
      return null;
    }
    return AuthUser(
      id: id.toInt(),
      email: email.trim(),
      name: name.trim().isEmpty ? 'Rider' : name.trim(),
    );
  }
}

class AuthSession {
  const AuthSession({required this.accessToken, required this.user});

  final String accessToken;
  final AuthUser user;

  AuthSession copyWith({AuthUser? user}) =>
      AuthSession(accessToken: accessToken, user: user ?? this.user);

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'user': user.toJson(),
  };

  static AuthSession? fromJson(Map<String, dynamic> json) {
    final token = json['access_token'];
    final rawUser = json['user'];
    if (token is! String ||
        token.trim().isEmpty ||
        rawUser is! Map<String, dynamic>) {
      return null;
    }
    final user = AuthUser.fromJson(rawUser);
    if (user == null) return null;
    return AuthSession(accessToken: token.trim(), user: user);
  }
}
