class MockRide {
  const MockRide({
    required this.code,
    required this.destination,
    required this.hostName,
    required this.riderNames,
    required this.distanceKm,
  });

  final String code;
  final String destination;
  final String hostName;
  final List<String> riderNames;
  final double distanceKm;
}

const List<MockRide> kMockRides = [
  MockRide(
    code: 'MOTO89',
    destination: 'Daman-e-Koh, Islamabad',
    hostName: 'Nawaf',
    riderNames: ['Nawaf', 'Ahmed', 'Bilal'],
    distanceKm: 8.2,
  ),
  MockRide(
    code: 'RIDE42',
    destination: 'Lake View Park, Islamabad',
    hostName: 'Sara',
    riderNames: ['Sara', 'Zain'],
    distanceKm: 14.5,
  ),
];

// Returns the ride matching [code], or null if not found.
// .toUpperCase() makes it case-insensitive.
MockRide? findMockRide(String code) {
  return kMockRides
      .where((r) => r.code == code.toUpperCase().trim())
      .firstOrNull;
}
