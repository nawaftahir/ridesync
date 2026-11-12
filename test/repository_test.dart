import 'package:flutter_test/flutter_test.dart';
import 'package:ridesync/repositories/ride_repository.dart';
import 'package:ridesync/repositories/rider_repository.dart';

void main() {
  const rideRepository = RideRepository();
  const riderRepository = RiderRepository();

  test('finds a mock ride without depending on code casing or whitespace', () {
    final ride = rideRepository.findByCode(' moto89 ');

    expect(ride?.code, 'MOTO89');
    expect(ride?.destination, 'Daman-e-Koh, Islamabad');
  });

  test('returns null when a ride code does not exist', () {
    expect(rideRepository.findByCode('UNKNOWN'), isNull);
  });

  test('exposes the centralized rider positions', () {
    expect(riderRepository.positions, hasLength(3));
    expect(riderRepository.positions.first.rider.name, 'Nawaf');
  });

  test('exposes mock past rides for the Rides tab', () {
    expect(rideRepository.pastRides, isNotEmpty);
    expect(
      rideRepository.pastRides.first.destination,
      'Daman-e-Koh, Islamabad',
    );
  });
}
