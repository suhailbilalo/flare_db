import 'package:flare_db/flare.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flare Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FlareDatabase? _db;
  bool _isInitialized = false;
  String _status = 'Opening Flare database...';
  List<DocumentSnapshot<User>> _users = [];
  List<DocumentSnapshot<User>> _admins = [];

  final List<int> _encryptionKey = List.generate(32, (i) => i + 1);

  @override
  void initState() {
    super.initState();
    _initDb();
  }

  Future<void> _initDb() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/flare_demo_v1.db';

      // 1. Initialize Flare with Encryption
      _db = FlareDatabase(path, encryptionKey: _encryptionKey);

      // 2. Register Secondary Index
      _db!.createIndex('users', 'role');

      setState(() {
        _isInitialized = true;
        _status = 'Flare ready (Encrypted & Thread-Safe)';
      });

      _refreshData();
    } catch (e) {
      setState(() => _status = 'Flare Init Error: $e');
    }
  }

  Future<void> _refreshData() async {
    if (_db == null) return;

    // 3. Collection with Converter (Typed Flare API)
    final usersCol = _db!
        .collection('users')
        .withConverter<User>(
          fromFirestore: (snap) => User.fromMap(snap.data()!),
          toFirestore: (u) => u.toMap(),
        );

    // 4. Advanced Querying (where clause)
    final admins = usersCol.where('role', isEqualTo: 'admin').get();

    // 5. Fetch All (Full collection scan)
    final all = usersCol.get();

    setState(() {
      _users = all;
      _admins = admins;
    });
  }

  void _addUser(String role) {
    if (_db == null) return;

    final usersCol = _db!
        .collection('users')
        .withConverter<User>(
          fromFirestore: (snap) => User.fromMap(snap.data()!),
          toFirestore: (u) => u.toMap(),
        );

    // 6. Auto-generated UUIDs
    final ref = usersCol.doc();

    // 7. Nested Objects & Advanced Types (Timestamp, GeoPoint)
    final newUser = User(
      name: 'User ${ref.id.substring(0, 5)}',
      role: role,
      createdAt: Timestamp.now(),
      profile: Profile(
        bio: 'I am a $role powered by Flare.',
        location: const GeoPoint(40.7128, -74.0060),
      ),
    );

    ref.set(newUser);

    // 8. Explicit Persistence (ACID sync)
    _db!.sync();

    _refreshData();
  }

  void _deleteUser(String id) {
    _db?.collection('users').doc(id).delete();
    _db?.sync();
    _refreshData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔥 Flare'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshData),
        ],
      ),
      body: !_isInitialized
          ? Center(child: Text(_status))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader('High-Performance Features'),
                  _buildFeatureList(),
                  const Divider(height: 32),
                  _buildHeader('Query Results (role == admin)'),
                  if (_admins.isEmpty)
                    const Text('No admins found.')
                  else
                    _buildUserList(_admins),
                  const Divider(height: 32),
                  _buildHeader('All Flare Documents (${_users.length})'),
                  _buildUserList(_users),
                  const SizedBox(height: 80),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addUser('user'),
        label: const Text('Add Random User'),
        icon: const Icon(Icons.person_add),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              onPressed: () => _addUser('admin'),
              icon: const Icon(Icons.admin_panel_settings),
              label: const Text('Add Admin'),
            ),
            TextButton.icon(
              onPressed: () {
                _db?.close();
                _initDb();
              },
              icon: const Icon(Icons.restart_alt),
              label: const Text('Re-open'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildFeatureList() {
    final features = [
      '✅ AES-256 at Rest',
      '✅ WAL Crash Recovery',
      '✅ 16KB Android 15 Opt',
      '✅ B-Tree Search',
      '✅ Multi-Isolate Safe',
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: features
          .map(
            (f) => Chip(label: Text(f, style: const TextStyle(fontSize: 11))),
          )
          .toList(),
    );
  }

  Widget _buildUserList(List<DocumentSnapshot<User>> snapshots) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: snapshots.length,
      itemBuilder: (context, index) {
        final snap = snapshots[index];
        final user = snap.data()!;
        return Card(
          child: ListTile(
            title: Text('${user.name} (${user.role})'),
            subtitle: Text(
              'ID: ${snap.id}\n'
              'Bio: ${user.profile.bio}\n'
              'Created: ${user.createdAt.toDate().toLocal().toString().split('.')[0]}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _deleteUser(snap.id),
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}

/// --- Flare Schemas ---

class User {
  final String name;
  final String role;
  final Timestamp createdAt;
  final Profile profile;

  User({
    required this.name,
    required this.role,
    required this.createdAt,
    required this.profile,
  });

  factory User.fromMap(Map<String, dynamic> map) => User(
    name: map['name'] as String,
    role: map['role'] as String,
    createdAt: Timestamp.fromMap(map['createdAt'] as Map<String, dynamic>),
    profile: Profile.fromMap(map['profile'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'role': role,
    'createdAt': createdAt.toMap(),
    'profile': profile.toMap(),
  };
}

class Profile {
  final String bio;
  final GeoPoint location;

  Profile({required this.bio, required this.location});

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
    bio: map['bio'] as String,
    location: GeoPoint.fromMap(map['location'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toMap() => {'bio': bio, 'location': location.toMap()};
}
