import 'package:appwrite/appwrite.dart';

// Appwrite client configuration
final Client client = Client()
    .setProject("697035fd003aa22ae623")
    .setEndpoint("https://fra.cloud.appwrite.io/v1");

// Initialize other Appwrite services if needed
final Account account = Account(client);
final Databases databases = Databases(client);
final Storage storage = Storage(client);
final Realtime realtime = Realtime(client);

final String bucketId = '69842ca90032baa373b8';
