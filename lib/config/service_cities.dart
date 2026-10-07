import 'package:latlong2/latlong.dart';

/// Конфигурация города обслуживания.
///
/// Чтобы добавить новый город, достаточно добавить одну запись в [serviceCities]
/// и затем синхронизировать её с серверным каталогом Cloud Functions.
class ServiceCity {
  const ServiceCity({
    required this.id,
    required this.name,
    required this.center,
    required this.coverageRadiusKm,
  });

  final String id;
  final String name;
  final LatLng center;
  final double coverageRadiusKm;
}

const serviceCities = <ServiceCity>[
  ServiceCity(
    id: 'almaty',
    name: 'Алматы',
    center: LatLng(43.238949, 76.889709),
    coverageRadiusKm: 50,
  ),
];

final serviceCitiesById = <String, ServiceCity>{
  for (final city in serviceCities) city.id: city,
};

ServiceCity serviceCityById(String? id) =>
    serviceCitiesById[id] ?? serviceCities.first;
