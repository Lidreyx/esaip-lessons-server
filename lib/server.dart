import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

void main() async {
  final router = Router()
  ..post('/register', registerThing);

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router);

  final server = await shelf_io.serve(handler, 'localhost', 8080);
  print('✅ Serveur démarré sur http://${server.address.host}:${server.port}');
}

// Fonction pour gérer l’enregistrement des things
Future<Response> registerThing(Request request) async {
  final payload = await request.readAsString();
  final data = jsonDecode(payload);

  final String id = data['id'];
  final String type = data['type'];

  if (id.isEmpty || type.isEmpty) {
    return Response.badRequest(body: '❌ ID et Type sont requis');
  }

  print('📌 Nouveau thing enregistré: ID=$id, Type=$type');
  return Response.ok(jsonEncode({'message': '✅ Thing enregistré'}));
}
