import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

void main() async {
  // Routeur pour gérer les endpoints
  final router = Router();

  // Endpoint de test
  router.get('/hello', (Request request) {
    return Response.ok('Hello, World! jure ça marche');
  });

  // Middleware pour logger les requêtes
  final handler = Pipeline()
      .addMiddleware(logRequests()) // Affiche les requêtes dans la console
      .addHandler(router);

  // Démarrer le serveur sur localhost:8080
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8080);
  print('Serveur démarré sur http://${server.address.host}:${server.port}');
}
