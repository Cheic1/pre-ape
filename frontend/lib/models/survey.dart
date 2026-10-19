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

import 'catasto.dart';
import 'energy.dart';

export 'catasto.dart';

/// Corpo di `POST /api/v1/surveys` e `PUT /api/v1/surveys/{id}`
/// (gli schema contrattuali `SurveyCreate` e `SurveyUpdate` sono identici).
class SurveyCreate {
  const SurveyCreate({
    this.title,
    this.clientName,
    this.notes,
    this.status,
    this.photos,
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
    this.building,
    this.additionalPhotos,
    this.cadastral,
  });

  factory SurveyCreate.fromJson(Map<String, dynamic> json) => SurveyCreate(
        title: json['title'] as String?,
        clientName: json['client_name'] as String?,
        notes: json['notes'] as String?,
        status: json['status'] as String?,
        photos: (json['photos'] as Map<String, dynamic>?)?.cast<String, String>(),
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
        building: (json['building'] as Map<String, dynamic>?),
        additionalPhotos:
            (json['additional_photos'] as List<dynamic>?)?.cast<String>(),
        cadastral: _cadastralFrom(json['cadastral']),
      );

  /// Intestazione della pratica (es. "Pratica 12/2026") e nome del cliente.
  final String? title;
  final String? clientName;

  /// Note libere del tecnico.
  final String? notes;

  /// `draft` | `completed` (il server rifiuta altri valori con 422).
  final String? status;

  /// Foto guidate `{slot: data-URL}` (es. `Facciata`, `Caldaia`).
  final Map<String, String>? photos;

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

  /// Dati per il calcolo energetico (schema `BuildingInputs` del backend:
  /// chiavi snake_case, valori ammessi in `energy_options.dart`).
  final Map<String, Object?>? building;

  /// Foto aggiuntive (data-URL), max 6 lato server.
  final List<String>? additionalPhotos;

  /// Dati catastali (max [kMaxCadastralUnits] unità).
  final List<CadastralUnit>? cadastral;

  /// Serializzazione a `snake_case`; omette i `null` (update parziale).
  Map<String, Object?> toJson() => <String, Object?>{
        if (title != null) 'title': title,
        if (clientName != null) 'client_name': clientName,
        if (notes != null) 'notes': notes,
        if (status != null) 'status': status,
        if (photos != null) 'photos': photos,
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
        if (building != null)
          'building': <String, Object?>{
            for (final e in building!.entries)
              if (e.value != null) e.key: e.value,
          },
        if (additionalPhotos != null) 'additional_photos': additionalPhotos,
        if (cadastral != null)
          'cadastral': [for (final u in cadastral!) u.toJson()],
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
    this.title,
    this.clientName,
    this.notes,
    this.photos,
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
    this.building,
    this.energyResult,
    this.additionalPhotos,
    this.cadastral,
  });

  factory SurveyRead.fromJson(Map<String, dynamic> json) => SurveyRead(
        id: json['id'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        userId: json['user_id'] as String?,
        title: json['title'] as String?,
        clientName: json['client_name'] as String?,
        notes: json['notes'] as String?,
        photos: (json['photos'] as Map<String, dynamic>?)?.cast<String, String>(),
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
        building: (json['building'] as Map<String, dynamic>?),
        energyResult: json['energy_result'] is Map<String, dynamic>
            ? EnergyResult.fromJson(json['energy_result'] as Map<String, dynamic>)
            : null,
        additionalPhotos:
            (json['additional_photos'] as List<dynamic>?)?.cast<String>(),
        cadastral: _cadastralFrom(json['cadastral']),
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

  final String? title;
  final String? clientName;
  final String? notes;
  final Map<String, String>? photos;

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

  /// Input del calcolo energetico salvati col sopralluogo.
  final Map<String, dynamic>? building;

  /// Ultima stima completa calcolata dal server (read-only).
  final EnergyResult? energyResult;

  /// Foto aggiuntive (data-URL).
  final List<String>? additionalPhotos;

  /// Dati catastali.
  final List<CadastralUnit>? cadastral;
}

List<CadastralUnit>? _cadastralFrom(Object? json) => json is List
    ? json
        .whereType<Map<String, dynamic>>()
        .map(CadastralUnit.fromJson)
        .toList(growable: false)
    : null;

/// Riga di `GET /api/v1/surveys` (nessun payload foto, solo il conteggio).
class SurveySummary {
  const SurveySummary({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.clientName,
    this.address,
    this.squareMeters,
    this.estimatedClass,
    this.energyScore,
    this.photoCount = 0,
    this.comune,
  });

  factory SurveySummary.fromJson(Map<String, dynamic> json) => SurveySummary(
        id: json['id'] as String,
        status: json['status'] as String? ?? 'draft',
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        title: json['title'] as String?,
        clientName: json['client_name'] as String?,
        address: json['address'] as String?,
        squareMeters: (json['square_meters'] as num?)?.toDouble(),
        estimatedClass: json['estimated_class'] as String?,
        energyScore: (json['energy_score'] as num?)?.toDouble(),
        photoCount: (json['photo_count'] as num?)?.toInt() ?? 0,
        comune: json['comune'] as String?,
      );

  final String id;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? title;
  final String? clientName;
  final String? address;
  final double? squareMeters;
  final String? estimatedClass;
  final double? energyScore;
  final int photoCount;

  /// Comune individuato dal calcolo energetico (per la lista).
  final String? comune;

  bool get isCompleted => status == 'completed';
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
    this.isAdmin = false,
    this.termsAccepted = false,
  });

  factory AuthToken.fromJson(Map<String, dynamic> json) => AuthToken(
        accessToken: json['access_token'] as String,
        tokenType: json['token_type'] as String? ?? 'bearer',
        userId: json['user_id'] as String,
        email: json['email'] as String? ?? '',
        name: json['name'] as String? ?? '',
        isAdmin: json['is_admin'] as bool? ?? false,
        termsAccepted: json['terms_accepted'] as bool? ?? false,
      );

  final String accessToken;
  final String tokenType;
  final String userId;
  final String email;
  final String name;

  /// Email in `ADMIN_EMAILS` lato server (pannello amministrazione).
  final bool isAdmin;
  /// L'utente ha accettato la versione corrente di Termini d'uso + DPA.
  final bool termsAccepted;
}
