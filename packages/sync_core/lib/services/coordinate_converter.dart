import 'dart:math' as math;

class CoordinateConverter {
  static const double _pi = 3.1415926535897932384626;
  static const double _a = 6378245.0;
  static const double _ee = 0.00669342162296594323;
  static const double _threshold = 1e-6;

  static (double, double) gcj02ToWgs84Exact(double latitude, double longitude) {
    if (_isOutOfChina(latitude, longitude)) {
      return (latitude, longitude);
    }

    double minLatitude = latitude - 0.5;
    double maxLatitude = latitude + 0.5;
    double minLongitude = longitude - 0.5;
    double maxLongitude = longitude + 0.5;
    double resultLatitude = latitude;
    double resultLongitude = longitude;

    for (int i = 0; i < 30; i++) {
      resultLatitude = (minLatitude + maxLatitude) / 2;
      resultLongitude = (minLongitude + maxLongitude) / 2;

      final (double transformedLatitude, double transformedLongitude) =
          _wgs84ToGcj02(resultLatitude, resultLongitude);
      final double latitudeDelta = transformedLatitude - latitude;
      final double longitudeDelta = transformedLongitude - longitude;

      if (latitudeDelta.abs() < _threshold &&
          longitudeDelta.abs() < _threshold) {
        return (resultLatitude, resultLongitude);
      }

      if (latitudeDelta > 0) {
        maxLatitude = resultLatitude;
      } else {
        minLatitude = resultLatitude;
      }

      if (longitudeDelta > 0) {
        maxLongitude = resultLongitude;
      } else {
        minLongitude = resultLongitude;
      }
    }

    return (resultLatitude, resultLongitude);
  }

  static bool _isOutOfChina(double latitude, double longitude) {
    return longitude < 72.004 ||
        longitude > 137.8347 ||
        latitude < 0.8293 ||
        latitude > 55.8271;
  }

  static (double, double) _wgs84ToGcj02(double latitude, double longitude) {
    if (_isOutOfChina(latitude, longitude)) {
      return (latitude, longitude);
    }

    final (double latitudeDelta, double longitudeDelta) = _coordinateDelta(
      latitude,
      longitude,
    );
    return (latitude + latitudeDelta, longitude + longitudeDelta);
  }

  static (double, double) _coordinateDelta(double latitude, double longitude) {
    double latitudeTransform = _transformLatitude(
      longitude - 105.0,
      latitude - 35.0,
    );
    double longitudeTransform = _transformLongitude(
      longitude - 105.0,
      latitude - 35.0,
    );
    final double radians = latitude / 180.0 * _pi;
    double magic = math.sin(radians);
    magic = 1 - _ee * magic * magic;
    final double sqrtMagic = math.sqrt(magic);

    latitudeTransform =
        (latitudeTransform * 180.0) /
        (((_a * (1 - _ee)) / (magic * sqrtMagic)) * _pi);
    longitudeTransform =
        (longitudeTransform * 180.0) /
        ((_a / sqrtMagic) * math.cos(radians) * _pi);

    return (latitudeTransform, longitudeTransform);
  }

  static double _transformLatitude(double x, double y) {
    double result =
        -100.0 +
        2.0 * x +
        3.0 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * math.sqrt(x.abs());
    result +=
        (20.0 * math.sin(6.0 * x * _pi) + 20.0 * math.sin(2.0 * x * _pi)) *
        2.0 /
        3.0;
    result +=
        (20.0 * math.sin(y * _pi) + 40.0 * math.sin(y / 3.0 * _pi)) * 2.0 / 3.0;
    result +=
        (160.0 * math.sin(y / 12.0 * _pi) + 320.0 * math.sin(y * _pi / 30.0)) *
        2.0 /
        3.0;
    return result;
  }

  static double _transformLongitude(double x, double y) {
    double result =
        300.0 +
        x +
        2.0 * y +
        0.1 * x * x +
        0.1 * x * y +
        0.1 * math.sqrt(x.abs());
    result +=
        (20.0 * math.sin(6.0 * x * _pi) + 20.0 * math.sin(2.0 * x * _pi)) *
        2.0 /
        3.0;
    result +=
        (20.0 * math.sin(x * _pi) + 40.0 * math.sin(x / 3.0 * _pi)) * 2.0 / 3.0;
    result +=
        (150.0 * math.sin(x / 12.0 * _pi) + 300.0 * math.sin(x / 30.0 * _pi)) *
        2.0 /
        3.0;
    return result;
  }
}
