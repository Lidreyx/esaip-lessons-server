import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

// Liste pour stocker les capteurs enregistrés
final Map<String, String> thingsRegistry = {}; // Clé = ID, Valeur = Type

String generateApiKey() {
  var uuid = Uuid();
  return uuid.v4(); // Génère un UUID unique
}

void main() async {
  final router =
      Router()
        ..post('/register', registerThing) // Route pour enregistrer un capteur
        ..get(
          '/things',
          getRegisteredThings,
        ) // Route pour voir les capteurs enregistrés
        ..get('/interact/<id>', interactWithThing) // Route d'interaction
        ..delete('/unregister/<id>', unregisterThing);

  final handler = Pipeline().addMiddleware(logRequests()).addHandler(router);

  final server = await shelf_io.serve(handler, 'localhost', 8081);
  print('✅ Serveur démarré sur http://${server.address.host}:${server.port}');
}

// 🔹 Fonction d'enregistrement d'un capteur
Future<Response> registerThing(Request request) async {
  final payload = await request.readAsString();
  final data = jsonDecode(payload);

  final String id = data['id'];
  final String type = data['type'];

  if (id.isEmpty || type.isEmpty) {
    return Response.badRequest(body: '❌ ID et Type sont requis');
  }

  // Vérifie si le capteur est déjà enregistré
  if (thingsRegistry.containsKey(id)) {
    return Response(400, body: '❌ Ce capteur est déjà enregistré');
  }

  // Génère une clé API unique pour ce capteur
  String apiKey = generateApiKey();
  // Ajoute le capteur et sa clé API à la liste
  thingsRegistry[id] = {'type': type, 'apiKey': apiKey};

  print('📌 Nouveau thing enregistré: ID=$id, Type=$type, API Key=$apiKey');

  return Response.ok(jsonEncode({'message': '✅ Thing enregistré'}));
}

// 🔹 Fonction pour récupérer la liste des capteurs enregistrés
Response getRegisteredThings(Request request) {
  return Response.ok(jsonEncode({'things': thingsRegistry}));
}

// 🔹 Fonction pour interagir avec un capteur (exemple)
Response interactWithThing(Request request, String id) {
  if (!thingsRegistry.containsKey(id)) {
    return Response(403, body: '❌ Ce capteur n\'est pas enregistré.');
  }

  return Response.ok('🔹 Interaction réussie avec le capteur $id');
}

// 🔹 Fonction pour désenregistrer un capteur et supprimer ses données
Response unregisterThing(Request request, String id) {
  if (!thingsRegistry.containsKey(id)) {
    return Response(404, body: '❌ Ce capteur n\'existe pas.');
  }

  // Supprime le capteur
  thingsRegistry.remove(id);
  print('🗑️ Capteur supprimé: ID=$id');

  return Response.ok(
    jsonEncode({'message': '✅ Capteur supprimé et données effacées'}),
  );
}
