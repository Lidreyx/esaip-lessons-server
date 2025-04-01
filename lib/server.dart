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

// Stockage des attributs des capteurs
final Map<String, Map<String, dynamic>> attributesData =
    {}; // ID -> Map des attributs

// Stockage des attributs globaux du serveur
final Map<String, dynamic> serverAttributes = {};

// Stockage des attributs client des capteurs
final Map<String, Map<String, dynamic>> clientAttributesData = {};

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
        ..post('/attributes/<id>', setAttributes)
        ..get('/attributes/<id>', getAttributes)
        ..post('/server/attributes', setServerAttributes)
        ..get('/server/attributes', getServerAttributes)
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
  attributesData.remove(id);
  clientAttributesData.remove(id);

  print('🗑️ Capteur supprimé: ID=$id');
  return Response.ok(jsonEncode({'message': '✅ Capteur supprimé'}));
}

// 🔹 Réception des données de télémétrie
Future<Response> receiveTelemetry(Request request, String id) async {
  final thing = thingsRegistry[id];
  if (thing == null)
    return Response(
      404,
      body: jsonEncode({'error': '❌ Capteur non enregistré'}),
    );

  final apiKeyFromRequest = request.headers['Authorization'];
  if (apiKeyFromRequest == null || thing['apiKey'] != apiKeyFromRequest) {
    return Response(403, body: jsonEncode({'error': '❌ Clé API invalide'}));
  }

  final payload = await request.readAsString();
  final data = jsonDecode(payload);

  final String? type = data['type'];
  final dynamic value = data['value'];

  if (type == null || value == null) {
    return Response(
      400,
      body: jsonEncode({'error': '❌ Type et valeur sont requis'}),
    );
  }

  telemetryData.putIfAbsent(id, () => []);
  telemetryData[id]!.add({
    'type': type,
    'value': value,
    'timestamp': DateTime.now().toIso8601String(),
  });

  print('📊 Télémétrie reçue pour $id: Type=$type, Valeur=$value');
  return Response.ok(jsonEncode({'message': '✅ Télémétrie enregistrée'}));
}

// 🔹 Récupération des données de télémétrie
Response getTelemetryData(Request request, String id) {
  if (!telemetryData.containsKey(id)) {
    return Response(
      404,
      body: jsonEncode({'error': '❌ Aucune donnée trouvée'}),
    );
  }
  return Response.ok(jsonEncode({'id': id, 'telemetry': telemetryData[id]}));
}

// 🔹 Définition des attributs d'un capteur
Future<Response> setAttributes(Request request, String id) async {
  final thing = thingsRegistry[id];
  if (thing == null)
    return Response(
      404,
      body: jsonEncode({'error': '❌ Capteur non enregistré'}),
    );

  final apiKeyFromRequest = request.headers['Authorization'];
  if (apiKeyFromRequest == null || thing['apiKey'] != apiKeyFromRequest) {
    return Response(403, body: jsonEncode({'error': '❌ Clé API invalide'}));
  }

  final payload = await request.readAsString();
  final data = jsonDecode(payload);

  if (data.isEmpty)
    return Response(
      400,
      body: jsonEncode({'error': '❌ Aucun attribut fourni'}),
    );

  attributesData.putIfAbsent(id, () => {});
  attributesData[id]!.addAll(data);

  print('📊 Attributs mis à jour pour $id: $data');
  return Response.ok(jsonEncode({'message': '✅ Attributs mis à jour'}));
}

// 🔹 Récupération des attributs d'un capteur
Response getAttributes(Request request, String id) {
  if (!attributesData.containsKey(id)) {
    return Response(404, body: '❌ Aucun attribut trouvé pour ce capteur.');
  }

  // Récupérer le type d'attribut demandé (client ou serveur)
  final type = request.url.queryParameters['type'];

  if (type == 'client') {
    return Response.ok(
      jsonEncode({'id': id, 'attributes': clientAttributesData[id] ?? {}}),
    );
  } else if (type == 'server') {
    return Response.ok(
      jsonEncode({'id': id, 'attributes': serverAttributes[id] ?? {}}),
    );
  } else {
    // Si aucun type spécifié, on renvoie tous les attributs
    return Response.ok(
      jsonEncode({'id': id, 'attributes': attributesData[id]}),
    );
  }
}

// 🔹 Définition des attributs du serveur
Future<Response> setServerAttributes(Request request) async {
  final payload = await request.readAsString();
  final data = jsonDecode(payload);

  if (data.isEmpty)
    return Response(
      400,
      body: jsonEncode({'error': '❌ Aucun attribut fourni'}),
    );

  serverAttributes.addAll(data);
  print('📊 Attributs du serveur mis à jour: $serverAttributes');

  return Response.ok(
    jsonEncode({'message': '✅ Attributs du serveur mis à jour'}),
  );
}

// 🔹 Récupération des attributs du serveur
Response getServerAttributes(Request request) {
  return Response.ok(jsonEncode({'serverAttributes': serverAttributes}));
}
