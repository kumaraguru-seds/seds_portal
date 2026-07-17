import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'main.dart'; // To access apiBaseUrl and UserData
import 'crypto_helper.dart';

class ChatTab extends StatefulWidget {
  final UserData? userData;

  const ChatTab({super.key, this.userData});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  bool _isLoading = true;
  List<dynamic> _rooms = [];
  final Map<String, String> _decryptedRoomKeys = {}; // room_id -> plaintext AES key
  String _myPublicKeyPem = '';
  String _myPrivateKeyPem = '';
  io.Socket? _socket;
  
  @override
  void initState() {
    super.initState();
    _initChatSystem();
  }

  @override
  void dispose() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.destroy();
    }
    super.dispose();
  }

  // Initialize E2EE Keys, upload public key, fetch rooms and connect socket
  Future<void> _initChatSystem() async {
    if (widget.userData == null) return;
    setState(() => _isLoading = true);
    try {
      // 1. Get/Generate RSA Key Pair
      final keys = await CryptoHelper.getOrGenerateKeys();
      _myPrivateKeyPem = keys['private']!;
      _myPublicKeyPem = keys['public']!;

      // 2. Upload public key to server
      final url = Uri.parse('$apiBaseUrl/api/chat/public-key');
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': widget.userData!.email,
          'public_key': _myPublicKeyPem,
        }),
      );

      // 3. Connect Chat Socket
      _initSocket();

      // 4. Fetch Rooms
      await _fetchRooms();
    } catch (e) {
      debugPrint('[Chat Tab] Error initializing: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _initSocket() {
    _socket = io.io(
      apiBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[Chat Socket] Connected successfully.');
      _socket!.emit('join_chat_rooms', widget.userData!.email);
    });

    _socket!.on('receive_chat_message', (data) {
      if (data == null) return;
      
      // Update room list with last message
      _fetchRooms(silent: true);
    });

    _socket!.on('message_read_receipt', (data) {
      // Refresh rooms to update read receipt indicators
      _fetchRooms(silent: true);
    });
  }

  // Fetch rooms list and decrypt keys
  Future<void> _fetchRooms({bool silent = false}) async {
    if (widget.userData == null) return;
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final url = Uri.parse('$apiBaseUrl/api/chat/rooms?email=${Uri.encodeComponent(widget.userData!.email)}');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final fetchedRooms = data['rooms'] as List;

          // Decrypt room keys for any new rooms
          for (var r in fetchedRooms) {
            final roomId = r['id'];
            if (!_decryptedRoomKeys.containsKey(roomId)) {
              await _loadAndDecryptRoomKey(roomId);
            }
          }

          if (mounted) {
            setState(() {
              _rooms = fetchedRooms;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[Chat Tab] Error fetching rooms: $e');
    } finally {
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  // Load encrypted room key from server and decrypt it using RSA private key
  Future<void> _loadAndDecryptRoomKey(String roomId) async {
    try {
      final url = Uri.parse('$apiBaseUrl/api/chat/room-key?room_id=$roomId&email=${Uri.encodeComponent(widget.userData!.email)}');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final String encryptedKey = data['encrypted_key'];
          final String decryptedKey = CryptoHelper.rsaDecrypt(encryptedKey, _myPrivateKeyPem);
          _decryptedRoomKeys[roomId] = decryptedKey;
        }
      }
    } catch (e) {
      debugPrint('[Chat Tab] Decryption key load failed for room $roomId: $e');
    }
  }

  // Handle room creation modal triggering permission-restricted user lookup
  void _showNewChatDialog() async {
    if (widget.userData == null) return;
    
    // Fetch all users to chat with
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => _NewChatDialog(
        userData: widget.userData!,
        existingRooms: _rooms,
        myPublicKeyPem: _myPublicKeyPem,
        myPrivateKeyPem: _myPrivateKeyPem,
        onChatCreated: () {
          _fetchRooms();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;

    return Scaffold(
      backgroundColor: const Color(0xFF101D35),
      appBar: AppBar(
        backgroundColor: const Color(0xFF162544),
        elevation: 0,
        title: Text(
          'SEDS Chat',
          style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Color(0xFF4DA6FF)),
            onPressed: _showNewChatDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () => _fetchRooms(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4DA6FF))))
          : _rooms.isEmpty
              ? _buildEmptyState(poppins)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _rooms.length,
                  separatorBuilder: (c, i) => Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
                  itemBuilder: (context, index) {
                    final room = _rooms[index];
                    final bool isGroup = room['is_group'] ?? false;
                    final String roomId = room['id'];

                    // Display details
                    String chatTitle = 'SEDS Channel';
                    String subtitle = 'End-to-End Encrypted';
                    String avatarLetter = 'S';
                    String? imageUrl;

                    if (isGroup) {
                      chatTitle = room['name'] ?? 'SEDS Group';
                      avatarLetter = chatTitle.isNotEmpty ? chatTitle[0].toUpperCase() : 'G';
                    } else {
                      final otherUser = room['other_user'];
                      if (otherUser != null) {
                        chatTitle = otherUser['name'] ?? 'SEDS Member';
                        imageUrl = otherUser['image_url'];
                        avatarLetter = chatTitle.isNotEmpty ? chatTitle[0].toUpperCase() : 'M';
                        subtitle = '${otherUser['role']} • ${otherUser['team'] ?? ''}';
                      }
                    }

                    return ListTile(
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFF4DA6FF).withValues(alpha: 0.15),
                        backgroundImage: (imageUrl != null && imageUrl.isNotEmpty) ? NetworkImage(imageUrl) : null,
                        child: (imageUrl == null || imageUrl.isEmpty)
                            ? Text(avatarLetter, style: poppins(color: const Color(0xFF4DA6FF), fontWeight: FontWeight.bold, fontSize: 18))
                            : null,
                      ),
                      title: Text(
                        chatTitle,
                        style: poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      subtitle: Text(
                        subtitle,
                        style: poppins(color: Colors.white60, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
                      onTap: () {
                        // Open Chat Window
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatRoomScreen(
                              userData: widget.userData!,
                              roomId: roomId,
                              roomTitle: chatTitle,
                              isGroup: isGroup,
                              roomKey: _decryptedRoomKeys[roomId] ?? '',
                              socket: _socket,
                            ),
                          ),
                        ).then((_) => _fetchRooms(silent: true));
                      },
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState(TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline_rounded, size: 64, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            'No secure conversations yet',
            style: poppins(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Search and start E2EE chats with SEDS members.',
            style: poppins(color: Colors.white30, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4DA6FF),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.search, color: Colors.white),
            label: Text('New Chat', style: poppins(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: _showNewChatDialog,
          ),
        ],
      ),
    );
  }
}

// ── Search & Room Creation Dialog ──
class _NewChatDialog extends StatefulWidget {
  final UserData userData;
  final List<dynamic> existingRooms;
  final String myPublicKeyPem;
  final String myPrivateKeyPem;
  final VoidCallback onChatCreated;

  const _NewChatDialog({
    required this.userData,
    required this.existingRooms,
    required this.myPublicKeyPem,
    required this.myPrivateKeyPem,
    required this.onChatCreated,
  });

  @override
  State<_NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<_NewChatDialog> {
  bool _loading = true;
  List<dynamic> _users = [];
  List<dynamic> _filteredUsers = [];
  final TextEditingController _searchCtrl = TextEditingController();

  // Group creation states
  bool _isCreatingGroup = false;
  final TextEditingController _groupNameCtrl = TextEditingController();
  final Set<String> _selectedEmails = {};

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _searchCtrl.addListener(_filterList);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _groupNameCtrl.dispose();
    super.dispose();
  }

  // Load and apply search permissions to users
  Future<void> _fetchUsers() async {
    try {
      final url = Uri.parse('$apiBaseUrl/api/admin/users');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final allUsers = data['users'] as List;

          // Filter list based on E2EE search dropdown rules
          final String myEmail = widget.userData.email.toLowerCase();
          final String myRole = widget.userData.role.toLowerCase();
          final String? myTeam = widget.userData.team;
          final List<String> myTeams = widget.userData.teams; // multiple teams support

          List<dynamic> allowedUsers = [];

          if (myRole == 'admin' || myRole == 'superadmin' || myRole == 'lead') {
            // Admins and Leads can search and chat with anyone!
            allowedUsers = allUsers.where((u) => u['email'].toString().toLowerCase() != myEmail).toList();
          } else {
            // Members can ONLY search/chat with users in their team (or Admins)
            allowedUsers = allUsers.where((u) {
              final String uEmail = u['email'].toString().toLowerCase();
              if (uEmail == myEmail) return false;

              final String uRole = u['role'].toString().toLowerCase();
              final String? uTeam = u['team'];

              // Allow if participant is Admin
              if (uRole == 'admin' || uRole == 'superadmin' || uRole == 'moderator') {
                return true;
              }

              // Allow if participant shares a team with member
              if (uTeam != null && (myTeams.contains(uTeam) || uTeam == myTeam)) {
                return true;
              }

              return false;
            }).toList();
          }

          if (mounted) {
            setState(() {
              _users = allowedUsers;
              _filteredUsers = allowedUsers;
              _loading = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[Chat Search] Error fetching users: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filterList() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filteredUsers = _users.where((u) {
        final name = (u['name'] ?? '').toString().toLowerCase();
        final email = (u['email'] ?? '').toString().toLowerCase();
        final roll = (u['roll_number'] ?? '').toString().toLowerCase();
        final team = (u['team'] ?? '').toString().toLowerCase();
        return name.contains(query) || email.contains(query) || roll.contains(query) || team.contains(query);
      }).toList();
    });
  }

  // Create Direct 1-to-1 Room
  Future<void> _startDirectChat(Map<String, dynamic> targetUser) async {
    setState(() => _loading = true);
    try {
      final String myEmail = widget.userData.email.toLowerCase().trim();
      final String otherEmail = targetUser['email'].toString().toLowerCase().trim();

      // Create a deterministic roomId by sorting emails
      final sortedEmails = [myEmail, otherEmail]..sort();
      final String roomId = 'dm_${base64Url.encode(utf8.encode(sortedEmails.join('_'))).replaceAll('=', '')}';

      // Check if room already exists in current list
      final exists = widget.existingRooms.any((r) => r['id'] == roomId);
      if (exists) {
        Navigator.pop(context);
        return;
      }

      // Fetch other user's public key
      final keyUrl = Uri.parse('$apiBaseUrl/api/chat/public-keys?emails=$otherEmail');
      final keyRes = await http.get(keyUrl);
      if (keyRes.statusCode != 200) throw Exception('Failed to fetch public key');
      final keyData = jsonDecode(keyRes.body);
      final keysList = keyData['keys'] as List;
      if (keysList.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recipient has not configured E2EE keys yet. Please ask them to log in to Chat.')),
          );
        }
        if (mounted) setState(() => _loading = false);
        return;
      }

      final String otherPublicKeyPem = keysList[0]['public_key'];

      // Generate AES Symmetric Key for this room
      final String plaintextRoomKey = CryptoHelper.generateRandomAESKey();

      // Encrypt room key for self and other
      final String encryptedSelfKey = CryptoHelper.rsaEncrypt(plaintextRoomKey, widget.myPublicKeyPem);
      final String encryptedOtherKey = CryptoHelper.rsaEncrypt(plaintextRoomKey, otherPublicKeyPem);

      // Create room API
      final roomUrl = Uri.parse('$apiBaseUrl/api/chat/rooms');
      await http.post(
        roomUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': roomId,
          'created_by': myEmail,
          'is_group': false,
          'members': [myEmail, otherEmail],
        }),
      );

      // Upload room keys
      final keysUrl = Uri.parse('$apiBaseUrl/api/chat/room-keys');
      await http.post(
        keysUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'room_id': roomId,
          'keys': [
            {'email': myEmail, 'encrypted_key': encryptedSelfKey},
            {'email': otherEmail, 'encrypted_key': encryptedOtherKey},
          ]
        }),
      );

      widget.onChatCreated();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('[Chat Setup] Direct room creation failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
        setState(() => _loading = false);
      }
    }
  }

  // Create E2EE Group Channel
  Future<void> _createGroupChat() async {
    final String gName = _groupNameCtrl.text.trim();
    if (gName.isEmpty) return;
    if (_selectedEmails.isEmpty) return;

    setState(() => _loading = true);
    try {
      final String myEmail = widget.userData.email.toLowerCase().trim();
      final String roomId = 'group_${DateTime.now().millisecondsSinceEpoch}';

      // Add self to group members
      final allEmails = [myEmail, ..._selectedEmails];

      // Fetch public keys of all group members
      final emailsQuery = allEmails.join(',');
      final keyUrl = Uri.parse('$apiBaseUrl/api/chat/public-keys?emails=${Uri.encodeComponent(emailsQuery)}');
      final keyRes = await http.get(keyUrl);
      if (keyRes.statusCode != 200) throw Exception('Failed to fetch public keys');
      final keyData = jsonDecode(keyRes.body);
      final keysList = keyData['keys'] as List;

      // Ensure all members have keys uploaded
      if (keysList.length < allEmails.length) {
        final foundEmails = keysList.map((k) => k['user_email'].toString().toLowerCase()).toList();
        final missing = allEmails.where((e) => !foundEmails.contains(e)).toList();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Some members have not initialized chats yet: ${missing.join(', ')}')),
          );
        }
        if (mounted) setState(() => _loading = false);
        return;
      }

      // Generate AES Key for Group
      final String plaintextRoomKey = CryptoHelper.generateRandomAESKey();

      // Encrypt key for all participants
      final List<Map<String, String>> encryptedKeysPayload = [];
      for (var userKey in keysList) {
        final email = userKey['user_email'];
        final pubKey = userKey['public_key'];
        final encKey = CryptoHelper.rsaEncrypt(plaintextRoomKey, pubKey);
        encryptedKeysPayload.add({
          'email': email,
          'encrypted_key': encKey,
        });
      }

      // Create Group Room API
      final roomUrl = Uri.parse('$apiBaseUrl/api/chat/rooms');
      await http.post(
        roomUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': roomId,
          'name': gName,
          'is_group': true,
          'team': widget.userData.team,
          'created_by': myEmail,
          'members': allEmails,
        }),
      );

      // Upload room keys
      final keysUrl = Uri.parse('$apiBaseUrl/api/chat/room-keys');
      await http.post(
        keysUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'room_id': roomId,
          'keys': encryptedKeysPayload,
        }),
      );

      widget.onChatCreated();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('[Chat Setup] Group room creation failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating group: ${e.toString()}')),
        );
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;

    // Check if creator is Admin or Lead (only they can create groups)
    final bool canCreateGroup = widget.userData.role.toLowerCase() == 'admin' ||
        widget.userData.role.toLowerCase() == 'superadmin' ||
        widget.userData.role.toLowerCase() == 'lead';

    return Dialog(
      backgroundColor: const Color(0xFF162544),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 450,
        height: 600,
        padding: const EdgeInsets.all(20),
        child: _loading
            ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4DA6FF))))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _isCreatingGroup ? 'Create Group Room' : 'Start Secure Chat',
                        style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      if (canCreateGroup && !_isCreatingGroup)
                        TextButton(
                          onPressed: () => setState(() => _isCreatingGroup = true),
                          child: Text('New Group', style: poppins(color: const Color(0xFF4DA6FF), fontWeight: FontWeight.bold)),
                        ),
                      if (_isCreatingGroup)
                        TextButton(
                          onPressed: () => setState(() => _isCreatingGroup = false),
                          child: Text('Cancel', style: poppins(color: Colors.white54)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  if (_isCreatingGroup) ...[
                    // Group name text field
                    TextField(
                      controller: _groupNameCtrl,
                      style: poppins(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Enter Group Name',
                        hintStyle: poppins(color: Colors.white30),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Search Field
                  TextField(
                    controller: _searchCtrl,
                    style: poppins(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, color: Colors.white30),
                      hintText: _isCreatingGroup ? 'Add Members' : 'Search by Name, Roll No, Team',
                      hintStyle: poppins(color: Colors.white30),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Expanded(
                    child: _filteredUsers.isEmpty
                        ? Center(child: Text('No users found', style: poppins(color: Colors.white30)))
                        : ListView.builder(
                            itemCount: _filteredUsers.length,
                            itemBuilder: (ctx, idx) {
                              final user = _filteredUsers[idx];
                              final String email = user['email'];
                              final String name = user['name'] ?? 'SEDS User';
                              final String roll = user['roll_number'] ?? 'N/A';
                              final String team = user['team'] ?? '';
                              final String role = user['role'] ?? 'Member';

                              final isSelected = _selectedEmails.contains(email);

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF4DA6FF).withValues(alpha: 0.1),
                                  child: Text(name[0].toUpperCase(), style: poppins(color: const Color(0xFF4DA6FF), fontWeight: FontWeight.bold)),
                                ),
                                title: Text(name, style: poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                                subtitle: Text('$roll • $role • $team', style: poppins(color: Colors.white30, fontSize: 11)),
                                trailing: _isCreatingGroup
                                    ? Checkbox(
                                        value: isSelected,
                                        activeColor: const Color(0xFF4DA6FF),
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) {
                                              _selectedEmails.add(email);
                                            } else {
                                              _selectedEmails.remove(email);
                                            }
                                          });
                                        },
                                      )
                                    : const Icon(Icons.chat_bubble_outline, color: Color(0xFF4DA6FF), size: 18),
                                onTap: () {
                                  if (_isCreatingGroup) {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedEmails.remove(email);
                                      } else {
                                        _selectedEmails.add(email);
                                      }
                                    });
                                  } else {
                                    _startDirectChat(user);
                                  }
                                },
                              );
                            },
                          ),
                  ),

                  if (_isCreatingGroup) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4DA6FF),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _selectedEmails.isNotEmpty ? _createGroupChat : null,
                        child: Text(
                          'Create Group (${_selectedEmails.length})',
                          style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

// ── Conversation Screen ──
class ChatRoomScreen extends StatefulWidget {
  final UserData userData;
  final String roomId;
  final String roomTitle;
  final bool isGroup;
  final String roomKey;
  final io.Socket? socket;

  const ChatRoomScreen({
    super.key,
    required this.userData,
    required this.roomId,
    required this.roomTitle,
    required this.isGroup,
    required this.roomKey,
    this.socket,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  bool _loading = true;
  List<dynamic> _messages = [];
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _setupSocketListeners();
  }

  @override
  void dispose() {
    if (widget.socket != null) {
      widget.socket!.off('receive_chat_message');
      widget.socket!.off('message_read_receipt');
      widget.socket!.emit('leave_room', widget.roomId);
    }
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _setupSocketListeners() {
    if (widget.socket != null) {
      widget.socket!.emit('join_room', widget.roomId);

      widget.socket!.on('receive_chat_message', (data) {
        if (data == null) return;
        final msg = data;
        if (msg['room_id'] == widget.roomId) {
          if (mounted) {
            setState(() {
              _messages.add(msg);
            });
            _scrollToBottom();
            _markAsSeen(msg);
          }
        }
      });

      widget.socket!.on('message_read_receipt', (data) {
        if (data == null) return;
        final String mId = data['message_id'].toString();
        
        if (mounted) {
          setState(() {
            for (var m in _messages) {
              if (m['id'].toString() == mId) {
                m['status'] = 'read';
              }
            }
          });
        }
      });
    }
  }

  Future<void> _fetchMessages() async {
    try {
      final url = Uri.parse('$apiBaseUrl/api/chat/messages?room_id=${widget.roomId}');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final fetched = data['messages'] as List;
          if (mounted) {
            setState(() {
              _messages = fetched;
              _loading = false;
            });
            _scrollToBottom();
            
            // Mark all unread messages as seen
            for (var m in fetched) {
              if (m['sender_email'].toString().toLowerCase() != widget.userData.email.toLowerCase() && m['status'] != 'read') {
                _markAsSeen(m);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[Chat Log] Error loading messages: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // Record read receipt
  Future<void> _markAsSeen(dynamic msg) async {
    final String myEmail = widget.userData.email.toLowerCase().trim();
    if (msg['sender_email'].toString().toLowerCase() == myEmail) return;

    try {
      // 1. Emit read socket notification
      if (widget.socket != null) {
        widget.socket!.emit('mark_message_read', {
          'room_id': widget.roomId,
          'message_id': msg['id'],
          'user_email': myEmail,
          'user_name': widget.userData.name,
        });
      }

      // 2. Call REST endpoint
      final url = Uri.parse('$apiBaseUrl/api/chat/messages/seen');
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message_id': msg['id'],
          'user_email': myEmail,
          'user_name': widget.userData.name,
        }),
      );
    } catch (e) {
      debugPrint('[Chat Seen] Failed recording seen status: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Send Encrypted Message
  Future<void> _sendMessage({String? mediaUrl}) async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty && mediaUrl == null) return;

    _msgCtrl.clear();

    // E2E Encrypt message content locally
    String encryptedText = '';
    if (text.isNotEmpty) {
      encryptedText = CryptoHelper.aesEncrypt(text, widget.roomKey);
    }

    final messagePayload = {
      'room_id': widget.roomId,
      'sender_email': widget.userData.email,
      'sender_name': widget.userData.name,
      'sender_roll_number': widget.userData.rollNumber,
      'encrypted_content': encryptedText,
      'media_url': mediaUrl,
      'sender_ip': 'Client Device',
    };

    if (widget.socket != null) {
      widget.socket!.emit('send_chat_message', messagePayload);
    }
  }

  // Pick and upload image
  Future<void> _shareImage() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result == null || result.files.single.path == null) return;

      setState(() => _loading = true);

      final File file = File(result.files.single.path!);

      // SEDS Portal upload logic (POST /api/upload)
      final request = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/api/upload'));
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final String fileUrl = data['fileUrl'];
          await _sendMessage(mediaUrl: fileUrl);
        }
      }
    } catch (e) {
      debugPrint('[Chat Image Share] Image upload failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Seen-by / Message details Dialog
  void _showMessageDetails(dynamic msg) async {
    final poppins = GoogleFonts.poppins;
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => _MessageDetailsDialog(messageId: msg['id'], poppins: poppins),
    );
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;
    final myEmail = widget.userData.email.toLowerCase();

    return Scaffold(
      backgroundColor: const Color(0xFF101D35),
      appBar: AppBar(
        backgroundColor: const Color(0xFF162544),
        title: Text(
          widget.roomTitle,
          style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4DA6FF))))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, idx) {
                      final msg = _messages[idx];
                      final bool isMe = msg['sender_email'].toString().toLowerCase() == myEmail;
                      final String encryptedContent = msg['encrypted_content'] ?? '';
                      final String? mediaUrl = msg['media_url'];

                      // Decrypt locally
                      String plaintext = '[Media Attachment]';
                      if (encryptedContent.isNotEmpty) {
                        plaintext = CryptoHelper.aesDecrypt(encryptedContent, widget.roomKey);
                      }

                      final String senderLabel = isMe ? 'You' : '${msg['sender_name']} (${msg['sender_roll_number']})';

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isMe ? const Color(0xFF4DA6FF).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                              bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                            ),
                            border: Border.all(
                              color: isMe ? const Color(0xFF4DA6FF).withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: GestureDetector(
                            onLongPress: () => _showMessageDetails(msg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  senderLabel,
                                  style: poppins(color: isMe ? const Color(0xFF4DA6FF) : Colors.white60, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                if (mediaUrl != null && mediaUrl.isNotEmpty) ...[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      mediaUrl,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return const SizedBox(
                                          height: 150,
                                          child: Center(child: CircularProgressIndicator()),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                if (encryptedContent.isNotEmpty)
                                  Text(
                                    plaintext,
                                    style: poppins(color: Colors.white, fontSize: 13.5),
                                  ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      msg['created_at'] != null
                                          ? DateTime.parse(msg['created_at']).toLocal().toString().substring(11, 16)
                                          : '',
                                      style: poppins(color: Colors.white24, fontSize: 9),
                                    ),
                                    if (isMe) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.done_all,
                                        size: 12,
                                        color: msg['status'] == 'read' ? const Color(0xFF4DA6FF) : Colors.white24,
                                      ),
                                    ]
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                _buildInputBar(poppins),
              ],
            ),
    );
  }

  Widget _buildInputBar(TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF162544),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.image_outlined, color: Color(0xFF4DA6FF)),
              onPressed: _shareImage,
            ),
            Expanded(
              child: TextField(
                controller: _msgCtrl,
                style: poppins(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '🔒 Send encrypted message...',
                  hintStyle: poppins(color: Colors.white24),
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send_rounded, color: Color(0xFF4DA6FF)),
              onPressed: () => _sendMessage(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Viewed-By Dialog ──
class _MessageDetailsDialog extends StatefulWidget {
  final int messageId;
  final TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins;

  const _MessageDetailsDialog({required this.messageId, required this.poppins});

  @override
  State<_MessageDetailsDialog> createState() => _MessageDetailsDialogState();
}

class _MessageDetailsDialogState extends State<_MessageDetailsDialog> {
  bool _loading = true;
  List<dynamic> _viewsList = [];

  @override
  void initState() {
    super.initState();
    _fetchSeenBy();
  }

  Future<void> _fetchSeenBy() async {
    try {
      final url = Uri.parse('$apiBaseUrl/api/chat/messages/seen-by?message_id=${widget.messageId}');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            setState(() {
              _viewsList = data['seen_by'];
              _loading = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[Chat Views] Error fetching viewed-by list: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF162544),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 320,
        height: 350,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Message Info', style: widget.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Text('Seen by:', style: widget.poppins(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _viewsList.isEmpty
                      ? Center(child: Text('No one has seen this message yet.', style: widget.poppins(color: Colors.white30, fontSize: 12)))
                      : ListView.builder(
                          itemCount: _viewsList.length,
                          itemBuilder: (ctx, idx) {
                            final view = _viewsList[idx];
                            final String name = view['user_name'] ?? '';
                            final String timeStr = DateTime.parse(view['viewed_at']).toLocal().toString().substring(11, 16);
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF4DA6FF).withValues(alpha: 0.1),
                                radius: 16,
                                child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: widget.poppins(color: const Color(0xFF4DA6FF), fontSize: 12)),
                              ),
                              title: Text(name, style: widget.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                              trailing: Text(timeStr, style: widget.poppins(color: Colors.white30, fontSize: 11)),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
