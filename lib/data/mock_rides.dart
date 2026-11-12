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

class MockPastRide {
  const MockPastRide({
    required this.destination,
    required this.dateLabel,
    required this.distanceKm,
    required this.durationMinutes,
    required this.riderCount,
  });

  final String destination;
  final String dateLabel;
  final double distanceKm;
  final int durationMinutes;
  final int riderCount;
}

const List<MockPastRide> kMockPastRides = [
  MockPastRide(
    destination: 'Daman-e-Koh, Islamabad',
    dateLabel: '2 days ago',
    distanceKm: 8.2,
    durationMinutes: 22,
    riderCount: 3,
  ),
  MockPastRide(
    destination: 'Lake View Park, Islamabad',
    dateLabel: 'Last week',
    distanceKm: 14.5,
    durationMinutes: 35,
    riderCount: 2,
  ),
  MockPastRide(
    destination: 'Margalla Hills Loop',
    dateLabel: '2 weeks ago',
    distanceKm: 24.0,
    durationMinutes: 48,
    riderCount: 4,
  ),
];
