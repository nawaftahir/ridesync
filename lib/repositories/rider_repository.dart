import 'package:ridesync/data/mock_map_data.dart';
import 'package:ridesync/models/rider_position.dart';

class RiderRepository {
  const RiderRepository({this.positions = kMockRiderPositions});

  final List<RiderPosition> positions;
}
