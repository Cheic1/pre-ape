/// Wire DTO dell'API Pre-APE v1.
///
/// **Fonte di verità**: `docs/openapi.snapshot.json` (snapshot di
/// `GET /openapi.json`). Questi tipi specchiano il JSON di rete e *nient'altro*.
///
/// ≠ stato client: `SurveyData` (in `features/onboarding/survey_provider.dart`)
/// è lo stato modificabile della wizard (punteggio derivato, foto data-URL,
/// `locating`...), questi DTO sono il contratto. Mappatura SurveyData → wire:
///
/// | SurveyData            | campo wire            | note                                    |
/// |-----------------------|-----------------------|-----------------------------------------|
/// | `address`             | `address`             |                                         |
/// | `latitude`/`longitude`| `latitude`/`longitude`|                                         |
/// | `squareMeters`        | `square_meters`       |                                         |
/// | `avgHeight`           | `avg_height`          |                                         |
/// | `wallThickness`       | `wall_thickness`      |                                         |
/// | `windowType`          | `window_frame`        | contratto ha anche `window_glass`       |
/// | `heatingType`         | `heating_type`        |                                         |
/// | `generatorType`       | `generator_type`      |                                         |
/// | `currentScore`        | *nessuno*             | `energy_score` è read-only (server)     |
/// | `photos` (slot)       | *nessuno*             | nessun campo foto in `SurveyCreate`     |
/// | *(riserva)* `additionalPhotos` | `additional_photos` | **non ancora nel contratto** – vedi sotto |
///
/// Convenzioni di wire (identiche in tutti gli endpoint, verificate sullo
/// snapshot): chiavi `snake_case`, date ISO 8601 (`date-time`), id UUID come
/// stringa. I `null` **non** vengono mai inviati: `PUT /surveys/{id}` usa
/// `exclude_unset` lato server, quindi un `null` esplicito cancellerebbe il
/// campo – l'update resta parziale e sicuro.
library;

/// Corpo di `POST /api/v1/surveys` e `PUT /api/v1/surveys/{id}`
/// (gli schema contrattuali `SurveyCreate` e `SurveyUpdate` sono identici).
class SurveyCreate {
  const SurveyCreate({
    this.address,
    this.latitude,
    this.longitude,
    this.squareMeters,
    this.avgHeight,
    this.climateZone,
    this.wallThickness,
    this.windowFrame,
    this.windowGlass,
    this.heatingType,
    this.generatorType,
    this.generatorPowerKw,
    this.generatorYear,
    this.additionalPhotos,
  });

  factory SurveyCreate.fromJson(Map<String, dynamic> json) => SurveyCreate(
        address: json['address'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        squareMeters: (json['square_meters'] as num?)?.toDouble(),
        avgHeight: (json['avg_height'] as num?)?.toDouble(),
        climateZone: json['climate_zone'] as String?,
        wallThickness: json['wall_thickness'] as String?,
        windowFrame: json['window_frame'] as String?,
        windowGlass: json['window_glass'] as String?,
        heatingType: json['heating_type'] as String?,
        generatorType: json['generator_type'] as String?,
        generatorPowerKw: (json['generator_power_kw'] as num?)?.toDouble(),
        generatorYear: (json['generator_year'] as num?)?.toInt(),
        additionalPhotos:
            (json['additional_photos'] as List<dynamic>?)?.cast<String>(),
      );

  final String? address;
  final double? latitude;
  final double? longitude;
  final double? squareMeters;
  final double? avgHeight;
  final String? climateZone;
  final String? wallThickness;
  final String? windowFrame;
  final String? windowGlass;
  final String? heatingType;
  final String? generatorType;
  final double? generatorPowerKw;
  final int? generatorYear;

  /// **Riserva contrattuale (M8)**: le foto aggiuntive non esistono ancora in
  /// `SurveyCreate`/`SurveyUpdate` dello snapshot – finché il backend non le
  /// espone (cambio additivo, nessun bump di versione) questo valore va
  /// lasciato `null` e la chiave **non** viene inviata (zero invio oggi).
  final List<String>? additionalPhotos;

  /// Serializzazione a `snake_case`; omette i `null` (update parziale).
  Map<String, Object?> toJson() => <String, Object?>{
        if (address != null) 'address': address,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (squareMeters != null) 'square_meters': squareMeters,
        if (avgHeight != null) 'avg_height': avgHeight,
        if (climateZone != null) 'climate_zone': climateZone,
        if (wallThickness != null) 'wall_thickness': wallThickness,
        if (windowFrame != null) 'window_frame': windowFrame,
        if (windowGlass != null) 'window_glass': windowGlass,
        if (heatingType != null) 'heating_type': heatingType,
        if (generatorType != null) 'generator_type': generatorType,
        if (generatorPowerKw != null) 'generator_power_kw': generatorPowerKw,
        if (generatorYear != null) 'generator_year': generatorYear,
        if (additionalPhotos != null) 'additional_photos': additionalPhotos,
      };
}

/// Corpo di risposta di `GET`/`POST`/`PUT /api/v1/surveys…`
/// (≡ schema `SurveyResponse` del contratto).
class SurveyRead {
  const SurveyRead({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.userId,
    this.address,
    this.latitude,
    this.longitude,
    this.squareMeters,
    this.avgHeight,
    this.climateZone,
    this.wallThickness,
    this.windowFrame,
    this.windowGlass,
    this.heatingType,
    this.generatorType,
    this.generatorPowerKw,
    this.generatorYear,
    this.estimatedClass,
    this.energyScore,
    this.additionalPhotos,
  });

  factory SurveyRead.fromJson(Map<String, dynamic> json) => SurveyRead(
        id: json['id'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        userId: json['user_id'] as String?,
        address: json['address'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        squareMeters: (json['square_meters'] as num?)?.toDouble(),
        avgHeight: (json['avg_height'] as num?)?.toDouble(),
        climateZone: json['climate_zone'] as String?,
        wallThickness: json['wall_thickness'] as String?,
        windowFrame: json['window_frame'] as String?,
        windowGlass: json['window_glass'] as String?,
        heatingType: json['heating_type'] as String?,
        generatorType: json['generator_type'] as String?,
        generatorPowerKw: (json['generator_power_kw'] as num?)?.toDouble(),
        generatorYear: (json['generator_year'] as num?)?.toInt(),
        estimatedClass: json['estimated_class'] as String?,
        energyScore: (json['energy_score'] as num?)?.toDouble(),
        additionalPhotos:
            (json['additional_photos'] as List<dynamic>?)?.cast<String>(),
      );

  /// UUID del survey (richiesto dal contratto).
  final String id;

  /// `draft` | `completed` | `exported`.
  final String status;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Il contratto v1 **non** espone ancora `user_id` (la proprietà è risolta
  /// solo lato server nei filtri anti-IDOR): campo riservato, popolato solo se
  /// e quando il backend lo aggiungerà in modo additivo.
  final String? userId;

  final String? address;
  final double? latitude;
  final double? longitude;
  final double? squareMeters;
  final double? avgHeight;
  final String? climateZone;
  final String? wallThickness;
  final String? windowFrame;
  final String? windowGlass;
  final String? heatingType;
  final String? generatorType;
  final double? generatorPowerKw;
  final int? generatorYear;

  /// Calcolato dal server: read-only attraverso l'API.
  final String? estimatedClass;
  final double? energyScore;

  /// Riserva (M8): vedi `SurveyCreate.additionalPhotos`.
  final List<String>? additionalPhotos;
}

/// Risposta di `POST /api/v1/auth/register` e `POST /api/v1/auth/login`
/// (schema `SurveyResponse`-equivalente: `TokenResponse`).
class AuthToken {
  const AuthToken({
    required this.accessToken,
    required this.tokenType,
    required this.userId,
    required this.email,
    required this.name,
  });

  factory AuthToken.fromJson(Map<String, dynamic> json) => AuthToken(
        accessToken: json['access_token'] as String,
        tokenType: json['token_type'] as String? ?? 'bearer',
        userId: json['user_id'] as String,
        email: json['email'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );

  final String accessToken;
  final String tokenType;
  final String userId;
  final String email;
  final String name;
}
