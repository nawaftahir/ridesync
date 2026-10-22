import 'package:ridesync/data/mock_rides.dart';

class RideRepository {
  const RideRepository({this.rides = kMockRides});

  final List<MockRide> rides;

  MockRide? findByCode(String code) {
    final normalizedCode = code.trim().toUpperCase();
    for (int i = 0; i < rides.length; i++) {
      if (rides[i].code == normalizedCode) {
        return rides[i];
      }
    }
    return null;
  }
}
