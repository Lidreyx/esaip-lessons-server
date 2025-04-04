import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

// Stockage des capteurs enregistrés
final Map<String, Map<String, String>> thingsRegistry =
    {}; // ID -> {Type, API Key}

// Stockage des données de télémétrie
final Map<String, List<Map<String, dynamic>>> telemetryData =
    {}; // ID -> Liste des données

// Stockage des attributs des capteurs (client et serveur séparés)
final Map<String, Map<String, dynamic>> clientAttributesData =
    {}; // ID -> Attributs Client
final Map<String, dynamic> serverAttributes =
    {}; // Attributs globaux du serveur

String generateApiKey() {
  return Uuid().v4();
}

void main() async {
  final router =
      Router()
        ..post('/register', registerThing)
        ..get('/things', getRegisteredThings)
        ..post('/telemetry/<id>', receiveTelemetry)
        ..get('/telemetry/<id>', getTelemetryData)
        ..post('/attributes/<id>', updateAttributes)
        ..get('/attributes/<id>', getAttributes)
        ..delete('/attributes/<id>', deleteAttributes)
        ..delete('/unregister/<id>', unregisterThing);

  final handler = Pipeline().addMiddleware(logRequests()).addHandler(router);
  final server = await shelf_io.serve(handler, 'localhost', 8081);
  print('✅ Serveur démarré sur http://${server.address.host}:${server.port}');
}

// 🔹 Enregistrement d'un capteur
Future<Response> registerThing(Request request) async {
  try {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);

    final String? id = data['id'];
    final String? type = data['type'];

    if (id == null || type == null || id.isEmpty || type.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error': '❌ ID et Type sont requis'}),
      );
    }

    if (thingsRegistry.containsKey(id)) {
      return Response(
        400,
        body: jsonEncode({'error': '❌ Ce capteur est déjà enregistré'}),
      );
    }

    String apiKey = generateApiKey();
    thingsRegistry[id] = {'type': type, 'apiKey': apiKey};

    print('📌 Thing enregistré: ID=$id, Type=$type, API Key=$apiKey');
    return Response.ok(
      jsonEncode({'message': '✅ Thing enregistré', 'apiKey': apiKey}),
    );
  } catch (e) {
    return Response(500, body: jsonEncode({'error': '❌ Erreur interne'}));
  }
}

// 🔹 Récupération des capteurs enregistrés
Response getRegisteredThings(Request request) {
  return Response.ok(jsonEncode({'things': thingsRegistry}));
}

// 🔹 Désenregistrement d'un capteur
Response unregisterThing(Request request, String id) {
  if (!thingsRegistry.containsKey(id)) {
    return Response(
      404,
      body: jsonEncode({'error': '❌ Ce capteur n\'existe pas.'}),
    );
  }

  thingsRegistry.remove(id);
  telemetryData.remove(id);
  clientAttributesData.remove(id);

  print('🗑️ Capteur supprimé: ID=$id');
  return Response.ok(jsonEncode({'message': '✅ Capteur supprimé'}));
}

// 🔹 Réception des données de télémétrie
// 🔹 Réception des données de télémétrie avec timestamp
Future<Response> receiveTelemetry(Request request, String id) async {
  if (!thingsRegistry.containsKey(id)) {
    return Response(
      404,
      body: jsonEncode({'error': '❌ Capteur non enregistré'}),
    );
  }

  final payload = await request.readAsString();
  final data = jsonDecode(payload);

  if (data.isEmpty) {
    return Response(
      400,
      body: jsonEncode({'error': '❌ Données de télémétrie invalides'}),
    );
  }

  final timestamp = DateTime.now().toIso8601String();
  final telemetryEntry = {'data': data, 'timestamp': timestamp};

  telemetryData.putIfAbsent(id, () => []);
  telemetryData[id]!.add(telemetryEntry);

  print('📡 Télémétrie reçue pour $id: $telemetryEntry');
  return Response.ok(jsonEncode({'message': '✅ Télémétrie enregistrée'}));
}

// 🔹 Récupération des données de télémétrie
Response getTelemetryData(Request request, String id) {
  if (!thingsRegistry.containsKey(id)) {
    return Response(
      404,
      body: jsonEncode({'error': '❌ Capteur non enregistré'}),
    );
  }

  final data = telemetryData[id] ?? [];
  return Response.ok(jsonEncode({'id': id, 'telemetry': data}));
}

// 🔹 Mise à jour des attributs (client ou serveur) d'un capteur
Future<Response> updateAttributes(Request request, String id) async {
  final thing = thingsRegistry[id];
  if (thing == null) {
    return Response(
      404,
      body: jsonEncode({'error': '❌ Capteur non enregistré'}),
    );
  }

  final apiKeyFromRequest = request.headers['Authorization'];
  if (apiKeyFromRequest == null || thing['apiKey'] != apiKeyFromRequest) {
    return Response(403, body: jsonEncode({'error': '❌ Clé API invalide'}));
  }

  final payload = await request.readAsString();
  final data = jsonDecode(payload);
  final type = request.url.queryParameters['type']; // "server" ou "client"

  if (data.isEmpty) {
    return Response(
      400,
      body: jsonEncode({'error': '❌ Aucun attribut fourni'}),
    );
  }

  final timestamp = DateTime.now().toIso8601String();

  if (type == 'server') {
    data.forEach((key, value) {
      serverAttributes[key] = {'value': value, 'timestamp': timestamp};
    });

    print('📊 Attributs serveur mis à jour: $serverAttributes');
    return Response.ok(
      jsonEncode({'message': '✅ Attributs serveur mis à jour'}),
    );
  } else {
    clientAttributesData.putIfAbsent(id, () => {});
    data.forEach((key, value) {
      clientAttributesData[id]![key] = {'value': value, 'timestamp': timestamp};
    });

    print(
      '📊 Attributs client mis à jour pour $id: ${clientAttributesData[id]}',
    );
    return Response.ok(
      jsonEncode({'message': '✅ Attributs client mis à jour'}),
    );
  }
}

// 🔹 Récupération des attributs d'un capteur
Response getAttributes(Request request, String id) {
  if (!thingsRegistry.containsKey(id)) {
    return Response(
      404,
      body: jsonEncode({'error': '❌ Capteur non enregistré'}),
    );
  }

  final type = request.url.queryParameters['type']; // "server" ou "client"

  if (type == 'server') {
    return Response.ok(jsonEncode({'id': id, 'attributes': serverAttributes}));
  } else if (type == 'client') {
    return Response.ok(
      jsonEncode({'id': id, 'attributes': clientAttributesData[id] ?? {}}),
    );
  } else {
    return Response.ok(
      jsonEncode({
        'id': id,
        'serverAttributes': serverAttributes,
        'clientAttributes': clientAttributesData[id] ?? {},
      }),
    );
  }
}

// 🔹 Suppression des attributs d'un capteur
Response deleteAttributes(Request request, String id) {
  if (!thingsRegistry.containsKey(id)) {
    return Response(
      404,
      body: jsonEncode({'error': '❌ Capteur non enregistré'}),
    );
  }

  final type = request.url.queryParameters['type']; // "server" ou "client"

  if (type == 'server') {
    serverAttributes.clear();
    print('🗑️ Tous les attributs serveur supprimés');
    return Response.ok(
      jsonEncode({'message': '✅ Tous les attributs serveur supprimés'}),
    );
  } else if (type == 'client') {
    clientAttributesData.remove(id);
    print('🗑️ Attributs client supprimés pour $id');
    return Response.ok(jsonEncode({'message': '✅ Attributs client supprimés'}));
  } else {
    return Response(
      400,
      body: jsonEncode({
        'error':
            '❌ Spécifier le type d\'attribut à supprimer (server ou client)',
      }),
    );
  }
}
