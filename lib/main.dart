import 'dart:io'; 
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:nakama/nakama.dart';

late NakamaBaseClient nakamaClient;
Session? nakamaSession;
late NakamaWebsocketClient nakamaSocket;
String? currentNakamaMatchId;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await CarromSoundManager.initAudioSystem();
  
  try {
    nakamaClient = getNakamaClient(
      host: '10.169.7.239',
      serverKey: 'defaultkey',
    );

    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('nakama_device_id');
    if (deviceId == null) {
      deviceId = 'carrom_player_${Random().nextInt(900000) + 100000}';
      await prefs.setString('nakama_device_id', deviceId);
    }

    nakamaSession = await nakamaClient.authenticateDevice(
      deviceId: deviceId,
      create: true,
    );

    nakamaSocket = NakamaWebsocketClient.init(
      host: '10.169.7.239',
      token: nakamaSession!.token,
      ssl: false,
    );
    
    print("Nakama connected successfully!");
  } catch (e) {
    print("Nakama Server Initialization Error: $e");
  }
  
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: CarromMainMenu(),
  ));
}

bool isSoundOn = true;
bool isVibrationOn = true;
bool isFullScreenBoard = false; 
String currentLanguage = "English";
double globalSpeedMultiplier = 0.16; 
double globalMaxForce = 26.0;       

class CarromSoundManager {
  static final AudioPlayer _boundaryPlayer = AudioPlayer();
  static final AudioPlayer _pocketPlayer = AudioPlayer();
  static final AudioPlayer _startPlayer = AudioPlayer();
  static final AudioPlayer _coinHitPlayer = AudioPlayer();
  static final AudioPlayer _stickerReleasePlayer = AudioPlayer();

  static int _lastBoundaryPlayTime = 0;
  static int _lastCoinHitPlayTime = 0;

  static Future<void> initAudioSystem() async {
    try {
      await _boundaryPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _pocketPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _startPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _coinHitPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _stickerReleasePlayer.setPlayerMode(PlayerMode.lowLatency);
    } catch (e) {
      debugPrint("Audio Init Error: $e");
    }
  }

  static void playBoundaryHit() async {
    if (!isSoundOn) return;
    int currentTime = DateTime.now().millisecondsSinceEpoch;
    if (currentTime - _lastBoundaryPlayTime < 150) return;
    _lastBoundaryPlayTime = currentTime;

    try {
      await _boundaryPlayer.play(AssetSource('sounds/boundary_heat.mp3'));
    } catch (e) {
      debugPrint("Boundary Hit Sound Error: $e");
    }
  }

  static void playPocket() async {
    if (!isSoundOn) return;
    try {
      await _pocketPlayer.stop();
      await _pocketPlayer.play(AssetSource('sounds/carrom_pool_pocket.mp3'));
    } catch (e) {
      debugPrint("Pocket Sound Error: $e");
    }
  }

  static void playStart() async {
    if (!isSoundOn) return;
    try {
      await _startPlayer.stop();
      await _startPlayer.play(AssetSource('sounds/carrom_pool_start.mp3'));
    } catch (e) {
      debugPrint("Start Sound Error: $e");
    }
  }

  static void playCoinHit() async {
    if (!isSoundOn) return;
    int currentTime = DateTime.now().millisecondsSinceEpoch;
    if (currentTime - _lastCoinHitPlayTime < 100) return;
    _lastCoinHitPlayTime = currentTime;

    try {
      await _coinHitPlayer.play(AssetSource('sounds/coin_to_coin_heat.mp3'));
    } catch (e) {
      debugPrint("Coin Hit Sound Error: $e");
    }
  }

  // STICKER RELEASE SOUND: Plays EXACTLY ONCE when striker is released / shot fired
  static void playStickerRelease() async {
    if (!isSoundOn) return;
    try {
      await _stickerReleasePlayer.stop();
      await _stickerReleasePlayer.play(AssetSource('sounds/sticker_move.mp3'));
    } catch (e) {
      debugPrint("Sticker Release Sound Error: $e");
    }
  }
}

class CarromMainMenu extends StatefulWidget {
  const CarromMainMenu({Key? key}) : super(key: key);
  @override
  State<CarromMainMenu> createState() => _CarromMainMenuState();
}

class _CarromMainMenuState extends State<CarromMainMenu> with SingleTickerProviderStateMixin {
  int goldenCoins = 100;
  String username = "Pro_Player_1";
  String avatarPath = ""; 
  File? _imageFile; 
  final ImagePicker _picker = ImagePicker(); 
  Color selectedStrikerColor = Colors.cyanAccent;

  late AnimationController _welcomeController;
  late Animation<double> _fadeAnimation;
  bool showWelcomeOverlay = true;

  @override
  void initState() {
    super.initState();
    _welcomeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _welcomeController, curve: Curves.easeOut),
    );
    
    _checkExistingUser();
  }

  Future<void> _checkExistingUser() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('username');
    final savedImgPath = prefs.getString('avatar_file_path');

    if (savedName != null) {
      setState(() {
        username = savedName;
        if (savedImgPath != null && savedImgPath.isNotEmpty) {
          _imageFile = File(savedImgPath);
          avatarPath = "custom";
        }
      });

      if (nakamaSession != null) {
        try {
          await nakamaClient.updateAccount(
            session: nakamaSession!,
            username: username,
            displayName: username,
          );
        } catch (e) {
          print("Error updating Nakama username: $e");
        }
      }

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _welcomeController.forward().then((_) {
            setState(() { showWelcomeOverlay = false; });
          });
        }
      });
    } else {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _welcomeController.forward().then((_) {
            setState(() { showWelcomeOverlay = false; });
            _editProfileDialog();
          });
        }
      });
    }
  }

  Future<void> _saveProfileToLocal(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', name);
    if (_imageFile != null) {
      await prefs.setString('avatar_file_path', _imageFile!.path);
    }
    if (nakamaSession != null) {
      try {
        await nakamaClient.updateAccount(
          session: nakamaSession!,
          username: name, 
          displayName: name,
        );
      } catch (e) {
        print("Nakama Profile Update Error: $e");
      }
    }
  }

  @override
  void dispose() {
    _welcomeController.dispose();
    super.dispose();
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85, 
      );
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          avatarPath = "custom";
        });
      }
    } catch (e) {
      print("Error picking image: $e");
    }
  }

  void _openSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSettingsState) {
            return AlertDialog(
              backgroundColor: Colors.grey[950],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.cyanAccent, width: 1.5)),
              title: const Text("⚙️ GAME SETTINGS", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Language:", style: TextStyle(color: Colors.white, fontSize: 14)),
                      DropdownButton<String>(
                        dropdownColor: Colors.grey[900],
                        value: currentLanguage,
                        style: const TextStyle(color: Colors.cyanAccent),
                        items: ["English", "Hindi", "Burmese", "Shan"]
                            .map((lang) => DropdownMenuItem(value: lang, child: Text(lang)))
                            .toList(),
                        onChanged: (val) {
                          setSettingsState(() => currentLanguage = val!);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Full Screen Board:", style: TextStyle(color: Colors.white, fontSize: 14)),
                      Switch(
                        activeColor: Colors.cyanAccent,
                        value: isFullScreenBoard,
                        onChanged: (val) {
                          setSettingsState(() {
                            isFullScreenBoard = val;
                          });
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24),
                  SwitchListTile(
                    title: const Text("Sound Effect", style: TextStyle(color: Colors.white, fontSize: 14)),
                    activeColor: Colors.cyanAccent,
                    value: isSoundOn,
                    onChanged: (val) {
                      setSettingsState(() => isSoundOn = val);
                      setState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text("Vibration", style: TextStyle(color: Colors.white, fontSize: 14)),
                    activeColor: Colors.cyanAccent,
                    value: isVibrationOn,
                    onChanged: (val) {
                      setSettingsState(() => isVibrationOn = val);
                      setState(() {});
                    },
                  ),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 10),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Striker Speed / Power Factor:", style: TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                  Slider(
                    activeColor: Colors.amber,
                    inactiveColor: Colors.white24,
                    min: 0.08,
                    max: 0.25,
                    divisions: 4,
                    label: globalSpeedMultiplier == 0.08 ? "Soft" : (globalSpeedMultiplier <= 0.15 ? "Normal" : "Super Power 🔥"),
                    value: globalSpeedMultiplier,
                    onChanged: (val) {
                      setSettingsState(() {
                        globalSpeedMultiplier = val;
                        globalMaxForce = val * 166.0; 
                      });
                      setState(() {});
                    },
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan[700]),
                  onPressed: () => Navigator.pop(context),
                  child: const Text("DONE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                )
              ],
            );
          },
        );
      },
    );
  }

  void _simulateWatchAdVideo() {
    int timeLeft = 5;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setAdState) {
            Future.delayed(const Duration(seconds: 1), () {
              if (timeLeft > 0 && context.mounted) {
                setAdState(() { timeLeft--; });
              }
            });

            return WillPopScope(
              onWillPop: () async => false,
              child: AlertDialog(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.amber, width: 2)),
                content: SizedBox(
                  width: double.maxFinite,
                  height: 300,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(5)),
                            child: const Text("SPONSORED AD", style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                          Text(timeLeft > 0 ? "Skip in ${timeLeft}s" : "Reward Ready!", style: const TextStyle(color: Colors.white60, fontSize: 12)),
                        ],
                      ),
                      const Spacer(),
                      const Icon(Icons.play_circle_filled, size: 70, color: Colors.cyanAccent),
                      const SizedBox(height: 15),
                      const Text("COMMERCIAL VIDEO AD RUNNING", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("Watch completely to claim 20 Golden Coins", style: TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center),
                      const Spacer(),
                      timeLeft > 0 
                        ? const CircularProgressIndicator(color: Colors.cyanAccent)
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green[600], minimumSize: const Size(180, 40)),
                            onPressed: () {
                              Navigator.pop(context);
                              setState(() { goldenCoins += 20; });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("🎉 +20 Golden Coins credited successfully!", style: TextStyle(fontWeight: FontWeight.bold)),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            },
                            child: const Text("CLAIM +20 COINS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _editProfileDialog() {
    TextEditingController nameController = TextEditingController(text: username);
    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.cyanAccent, width: 1)),
          title: const Text("SET YOUR PLAYER ID", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Choose Photo & Nickname to enter the game", style: TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () async {
                  Navigator.pop(context); 
                  await _pickImageFromGallery(); 
                  _editProfileDialog(); 
                },
                child: CircleAvatar(
                  radius: 45,
                  backgroundColor: Colors.cyanAccent,
                  backgroundImage: avatarPath == "custom" && _imageFile != null ? FileImage(_imageFile!) : null,
                  child: avatarPath != "custom" ? const Icon(Icons.add_a_photo, size: 35, color: Colors.black) : null,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Enter Your Nickname",
                  labelStyle: TextStyle(color: Colors.white60),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
                ),
              )
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan[700], minimumSize: const Size(double.infinity, 45)),
              onPressed: () async {
                setState(() { 
                  username = nameController.text.isNotEmpty ? nameController.text : username; 
                });
                await _saveProfileToLocal(username);
                Navigator.pop(context);
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("✅ Your profile is saved successfully!", style: TextStyle(fontWeight: FontWeight.bold)),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text("SAVE & ENTER GAME", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        );
      },
    );
  }

  void _showTwoPlayerNamesDialog() {
    TextEditingController p1Controller = TextEditingController(text: username);
    TextEditingController p2Controller = TextEditingController(text: "Player 2");

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text("ENTER PLAYERS NAME", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: p1Controller,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Player 1 Name (White)",
                  labelStyle: TextStyle(color: Colors.white60),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: p2Controller,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Player 2 Name (Black)",
                  labelStyle: TextStyle(color: Colors.white60),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan[700]),
              onPressed: () {
                Navigator.pop(context);
                CarromSoundManager.playStart();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CarromGameScreen(
                      gameMode: 'local_2p',
                      strikerColor: selectedStrikerColor,
                      playerName: p1Controller.text.isNotEmpty ? p1Controller.text : username,
                      player2Name: p2Controller.text.isNotEmpty ? p2Controller.text : "Player 2",
                      userImage: _imageFile, 
                    ),
                  ),
                );
              },
              child: const Text("START MATCH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        );
      },
    );
  }

  void _openOnlineFriendLobby() {
    if (goldenCoins < 50) {
      _showInsufficientCoinsDialog(50);
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[950],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("ONLINE MULTIPLAYER", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Play with friends or online players (Entry: 50 GC)", style: TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.flash_on, color: Colors.black),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, minimumSize: const Size(220, 45)),
                label: const Text("AUTO MATCH (NO CODE)", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.pop(context);
                  _startAutoMatchmaking();
                },
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, color: Colors.black),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, minimumSize: const Size(220, 45)),
                label: const Text("CREATE 6-DIGIT CODE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.pop(context);
                  _createNakamaMatchRoom();
                },
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.login, color: Colors.white),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple[800], minimumSize: const Size(220, 45)),
                label: const Text("JOIN WITH 6-DIGIT CODE", style: TextStyle(color: Colors.white)),
                onPressed: () {
                  Navigator.pop(context);
                  _showJoinRoomInput();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _startAutoMatchmaking() async {
    setState(() { goldenCoins -= 50; });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.cyanAccent, width: 1.5)),
        title: const Text("FINDING OPPONENT...", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(color: Colors.cyanAccent),
            SizedBox(height: 15),
            Text("Searching for available online players...", style: TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
      ),
    );

    try {
      final ticket = await nakamaSocket.addMatchmaker(minCount: 2, maxCount: 2);
      nakamaSocket.onMatchmakerMatched.listen((matched) {
        if (mounted) {
          Navigator.pop(context); 
          currentNakamaMatchId = matched.matchId;
          bool isHost = matched.users.first.presence.userId == nakamaSession?.userId;
          _launchGameArena('online', matched.matchId, isHost);
        }
      });
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Matchmaking Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  void _createNakamaMatchRoom() async {
    setState(() { goldenCoins -= 50; });
    try {
      final match = await nakamaSocket.createMatch();
      currentNakamaMatchId = match.matchId; 
      
      String shortRoomCode = match.matchId.replaceAll('-', '').substring(0, 6).toUpperCase();

      bool hasNavigated = false;
      showDialog(
        context: context,
        barrierDismissible: false, 
        builder: (context) {
          return AlertDialog(
            backgroundColor: Colors.grey[900],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.amber, width: 1.5)),
            title: const Text("ROOM CREATED 🎯", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Share this 6-Digit CODE with your friend:", style: TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                const SizedBox(height: 15),
                SelectableText(
                  shortRoomCode, 
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 3),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text("(Tap & Hold to Copy Code)", style: TextStyle(color: Colors.white38, fontSize: 11)),
                const SizedBox(height: 25),
                const CircularProgressIndicator(color: Colors.amber),
                const SizedBox(height: 15),
                const Text("Waiting for friend to join...", style: TextStyle(color: Colors.white38, fontSize: 13)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text("CANCEL", style: TextStyle(color: Colors.redAccent)),
              )
            ],
          );
        },
      );

      nakamaSocket.onMatchPresence.listen((event) {
        if (event.matchId == match.matchId) {
          if (event.joins != null && event.joins!.isNotEmpty && !hasNavigated) {
            bool isRealOpponent = false;
            for (var presence in event.joins!) {
              if (presence.userId != nakamaSession?.userId) {
                isRealOpponent = true;
                break;
              }
            }

            if (isRealOpponent) {
              hasNavigated = true;
              Navigator.pop(context); 
              _launchGameArena('online', match.matchId, true); 
            }
          }
        }
      });
    } catch (e) {
      print("Nakama Room Creation Failure: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Server Connect Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  void _showJoinRoomInput() {
    TextEditingController codeController = TextEditingController();
    bool isConnecting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: const BorderSide(color: Colors.purpleAccent, width: 1.5),
              ),
              title: const Text(
                "ENTER 6-DIGIT CODE", 
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeController,
                    maxLength: 6,
                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      hintText: "EX: A1B2C3", 
                      hintStyle: TextStyle(color: Colors.white24, fontSize: 16),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
                    ),
                  ),
                  if (isConnecting) ...[
                    const SizedBox(height: 15),
                    const CircularProgressIndicator(color: Colors.cyanAccent),
                    const SizedBox(height: 8),
                    const Text("Connecting & Verifying Room...", style: TextStyle(color: Colors.white60, fontSize: 12)),
                  ]
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isConnecting ? null : () => Navigator.pop(context),
                  child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple[800]),
                  onPressed: isConnecting ? null : () async {
                    String code = codeController.text.trim().toLowerCase();
                    
                    if (code.length < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("⚠️ Please enter a valid 6-Digit Code!"), backgroundColor: Colors.orange),
                      );
                      return;
                    }

                    setDialogState(() { isConnecting = true; });

                    try {
                      final matchIdToJoin = currentNakamaMatchId ?? code;
                      final match = await nakamaSocket.joinMatch(matchIdToJoin);
                      
                      currentNakamaMatchId = match.matchId;
                      setState(() { goldenCoins -= 50; });
                      
                      Navigator.pop(context);
                      _launchGameArena('online', match.matchId, false);

                    } catch (e) {
                      try {
                        final match = await nakamaSocket.joinMatch(code);
                        currentNakamaMatchId = match.matchId;
                        setState(() { goldenCoins -= 50; });
                        Navigator.pop(context);
                        _launchGameArena('online', match.matchId, false);
                      } catch (err) {
                        setDialogState(() { isConnecting = false; });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("❌ Room Not Found or Expired!"), 
                            backgroundColor: Colors.red
                          ),
                        );
                      }
                    }
                  },
                  child: const Text("CONNECT"),
                )
              ],
            );
          }
        );
      },
    );
  }

  void _showInsufficientCoinsDialog(int required) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[950],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.redAccent, width: 1.5)),
          title: const Text("OUT OF COINS!", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          content: Text("You need $required Coins for this match. You currently have $goldenCoins. Watch a short ad to earn +20 coins!", style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white30))),
            ElevatedButton.icon(
              icon: const Icon(Icons.ondemand_video, color: Colors.black),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              label: const Text("WATCH AD (+20)", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.pop(context);
                _simulateWatchAdVideo();
              },
            )
          ],
        );
      },
    );
  }

  void _launchGameArena(String mode, [String? roomId, bool isHost = true]) {
    CarromSoundManager.playStart();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CarromGameScreen(
          gameMode: mode,
          strikerColor: selectedStrikerColor,
          playerName: username,
          roomId: roomId,
          isHost: isHost,
          userImage: _imageFile, 
          onMatchFinished: (bool userWon) {
            if (userWon && mode == 'online') {
              setState(() { goldenCoins += 100; });
            }
          },
        ),
      ),
    );
  }

  void _openWhatsAppStyleChatScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const WhatsAppInboxScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF04060F), Color(0xFF0C061A), Color(0xFF020205)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0.08,
              child: CustomPaint(painter: GridBackgroundPainter()),
            ),
          ),
          Positioned(
            top: 45,
            right: 20,
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(30)),
                  child: IconButton(
                    icon: const Icon(Icons.chat_bubble_outline, color: Colors.cyanAccent, size: 26),
                    onPressed: _openWhatsAppStyleChatScreen,
                    tooltip: "Chats",
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(30)),
                  child: IconButton(
                    icon: const Icon(Icons.settings, color: Colors.cyanAccent, size: 26),
                    onPressed: _openSettingsDialog,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(30)),
                  child: IconButton(
                    icon: Icon(
                      isSoundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      color: isSoundOn ? Colors.cyanAccent : Colors.grey,
                      size: 26,
                    ),
                    onPressed: () {
                      setState(() { isSoundOn = !isSoundOn; });
                    },
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _editProfileDialog, 
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.symmetric(horizontal: 30),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.4), width: 1.5),
                      boxShadow: [
                        BoxShadow(color: Colors.cyanAccent.withOpacity(0.05), blurRadius: 10, spreadRadius: 1)
                      ]
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24, 
                          backgroundColor: Colors.amber, 
                          backgroundImage: avatarPath == "custom" && _imageFile != null ? FileImage(_imageFile!) : null,
                          child: avatarPath != "custom" ? const Icon(Icons.person, color: Colors.black) : null,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(username, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                            const Text("Tap to edit profile ID", style: TextStyle(color: Colors.white30, fontSize: 11)),
                          ],
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            const Icon(Icons.monetization_on, color: Colors.amber, size: 22),
                            const SizedBox(width: 4),
                            Text("$goldenCoins", style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                Container(
                  width: 280,
                  decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.2), blurRadius: 15, spreadRadius: 2)]),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.ondemand_video_rounded, color: Colors.black, size: 24),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white, width: 1.5)),
                    ),
                    label: const Text("🎥 WATCH AD (GET +20 COINS)", style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    onPressed: _simulateWatchAdVideo,
                  ),
                ),
                const SizedBox(height: 30),
                const Text('CARROM POOL PRO', style: TextStyle(color: Colors.cyanAccent, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 3)),
                const SizedBox(height: 30),
                _menuButton(context, '⚡ ONLINE WITH FRIEND (50 GC) ⚡', 'online_lobby'),
                const SizedBox(height: 12),
                _menuButton(context, '👥 2 PLAYERS (LOCAL MATCH)', 'local_2p'),
                const SizedBox(height: 12),
                _menuButton(context, '🤖 VS COMPUTER (AI BOT - 20 GC)', 'ai'),
                const SizedBox(height: 12),
                _menuButton(context, '🎯 FREE PRACTICE MODE', 'practice'),
                const SizedBox(height: 12),
                SizedBox(
                  width: 310,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[800],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    icon: const Icon(Icons.message, color: Colors.white, size: 20),
                    label: const Text("💬 WHATSAPP CHAT WITH FRIENDS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: _openWhatsAppStyleChatScreen,
                  ),
                ),
              ],
            ),
          ),
          if (showWelcomeOverlay)
            FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.gavel_rounded, size: 80, color: Colors.cyanAccent),
                    SizedBox(height: 30),
                    Text("WELCOME TO CARROM POOL", style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    SizedBox(height: 10),
                    Text("PREMIUM CYBER MATCHMAKING ARENA", style: TextStyle(color: Colors.amber, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _menuButton(BuildContext context, String title, String mode) {
    bool isOnline = mode == 'online_lobby';
    return SizedBox(
      width: 310,
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isOnline ? Colors.purple[800] : Colors.grey[900],
          side: BorderSide(color: isOnline ? Colors.purpleAccent : Colors.cyanAccent, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        onPressed: () {
          if (isOnline) {
            _openOnlineFriendLobby();
          } else if (mode == 'local_2p') {
            _showTwoPlayerNamesDialog();
          } else if (mode == 'ai') {
            if (goldenCoins < 20) {
              _showInsufficientCoinsDialog(20);
            } else {
              setState(() { goldenCoins -= 20; });
              _launchGameArena(mode);
            }
          } else {
            _launchGameArena(mode);
          }
        },
        child: Text(title, style: TextStyle(color: isOnline ? Colors.white : Colors.cyanAccent, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class WhatsAppInboxScreen extends StatelessWidget {
  const WhatsAppInboxScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final chatList = [
      {"name": "Pro_Friend_99", "lastMsg": "Bro, next match kab khelega?", "time": "10:45 AM"},
      {"name": "CyberKing", "lastMsg": "Awesome striker shot!", "time": "Yesterday"},
      {"name": "CarromMaster", "lastMsg": "Invite me to your 6-digit room", "time": "2 days ago"},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Chats", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
      ),
      body: ListView.builder(
        itemCount: chatList.length,
        itemBuilder: (context, index) {
          final chat = chatList[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.cyanAccent,
              child: Text(chat["name"]![0], style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
            title: Text(chat["name"]!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text(chat["lastMsg"]!, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            trailing: Text(chat["time"]!, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => WhatsAppChatRoomScreen(friendName: chat["name"]!)),
              );
            },
          );
        },
      ),
    );
  }
}

class WhatsAppChatRoomScreen extends StatefulWidget {
  final String friendName;
  const WhatsAppChatRoomScreen({Key? key, required this.friendName}) : super(key: key);

  @override
  State<WhatsAppChatRoomScreen> createState() => _WhatsAppChatRoomScreenState();
}

class _WhatsAppChatRoomScreenState extends State<WhatsAppChatRoomScreen> {
  final TextEditingController _controller = TextEditingController();
  final _messages = [
    {"text": "Hey! Ready for a match?", "isMe": false},
    {"text": "Haan bilkul, room code bhejta hu!", "isMe": true},
  ];

  void _send() {
    if (_controller.text.trim().isEmpty) return;
    setState(() {
      _messages.add({"text": _controller.text.trim(), "isMe": true});
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            CircleAvatar(radius: 16, backgroundColor: Colors.cyanAccent, child: Text(widget.friendName[0], style: const TextStyle(color: Colors.black))),
            const SizedBox(width: 10),
            Text(widget.friendName, style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                bool isMe = msg["isMe"] as bool;
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.teal[800] : Colors.grey[800],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(msg["text"] as String, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF1E293B),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: "Type a message...",
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.cyanAccent),
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GridBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.cyanAccent..strokeWidth = 1.0;
    double step = 30.0;
    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += step) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CarromGameScreen extends StatefulWidget {
  final String gameMode;
  final Color strikerColor;
  final String playerName;
  final String player2Name; 
  final String? roomId;   
  final bool isHost;
  final File? userImage; 
  final Function(bool)? onMatchFinished;

  const CarromGameScreen({
    Key? key,
    required this.gameMode,
    required this.strikerColor,
    required this.playerName,
    this.player2Name = "Player 2",
    this.roomId,
    this.isHost = true,
    this.userImage,
    this.onMatchFinished,
  }) : super(key: key);

  @override
  _CarromGameScreenState createState() => _CarromGameScreenState();
}

class _CarromGameScreenState extends State<CarromGameScreen> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double boardSize = 400.0; 
  final double pocketOffset = 35.0;  
  final double pocketRadius = 16.0;  
  final double boardMargin = 35.0;
  Offset strikerPos = const Offset(200, 322); 
  double sliderVal = 200.0;
  Offset strikerVelocity = Offset.zero;
  
  Offset? dragStart;
  Offset? dragUpdate;
  bool isDragging = false;
  
  List<Coin> coins = [];
  bool isPlayerTurn = true;
  bool isMoving = false;
  bool shotExecuted = false;
  bool hasScoredInThisTurn = false; 

  int playerScores = 0;
  int secondaryScores = 0; 
  String comboMessage = "";
  double messageOpacity = 0.0;

  String oppName = "Online Friend";
  String oppAvatarPath = "";

  ui.Image? blackCoinImg;
  ui.Image? whiteCoinImg;
  ui.Image? redCoinImg;
  ui.Image? stickerCoinImg;
  bool imagesLoaded = false;

  @override
  void initState() {
    super.initState();
    oppName = widget.player2Name;
    _loadCustomCoinImages();
    _initCarromSet();
    if (widget.gameMode == 'online' && widget.roomId != null) {
      _listenNakamaNetworkData();
    }
    _ticker = createTicker(_updatePhysics)..start();
  }

  Future<ui.Image> _loadSingleImage(String path) async {
    final data = await rootBundle.load(path);
    final bytes = data.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  void _loadCustomCoinImages() async {
    try {
      blackCoinImg = await _loadSingleImage('assets/images/black coin.png');
      whiteCoinImg = await _loadSingleImage('assets/images/white coin.png');
      redCoinImg = await _loadSingleImage('assets/images/red coin.png');
      stickerCoinImg = await _loadSingleImage('assets/images/sticker.png');
      setState(() {
        imagesLoaded = true;
      });
    } catch (e) {
      print("Error loading custom coin images: $e");
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _listenNakamaNetworkData() {
    nakamaSocket.onMatchData.listen((MatchData data) {
      if (data.matchId != widget.roomId || data.data == null) return;
      if (!mounted) return;
      
      final String content = String.fromCharCodes(data.data!);
      final List<String> segments = content.split(";");

      if (segments[0] == "SLIDER") {
        double remoteSlider = double.parse(segments[1]);
        bool myTurn = (isPlayerTurn == widget.isHost);
        
        if (!myTurn) {
          double newSliderVal = boardSize - remoteSlider;
          if ((sliderVal - newSliderVal).abs() > 0.5) { 
            setState(() {
              sliderVal = newSliderVal;
              strikerPos = Offset(sliderVal, 78.0);
            });
          }
        }
      }

      if (segments[0] == "TURN") {
        bool hostSaysTurn = segments[1] == "true";
        if (isPlayerTurn != hostSaysTurn) {
          setState(() {
            isPlayerTurn = hostSaysTurn;
            bool myTurn = (isPlayerTurn == widget.isHost);
            sliderVal = boardSize / 2;
            strikerPos = Offset(sliderVal, myTurn ? boardSize - 78.0 : 78.0);
          });
        }
      }

      if (segments[0] == "SHOT") {
        bool myTurn = (isPlayerTurn == widget.isHost);
        if (!myTurn) {
          double vx = double.parse(segments[1]);
          double vy = double.parse(segments[2]);
          double force = double.parse(segments[3]);

          setState(() {
            strikerVelocity = Offset(-vx, -vy) * force; 
            shotExecuted = true;
            isDragging = false; 
            isMoving = true; 
          });
          CarromSoundManager.playStickerRelease();
        }
      }
    });
  }

  void _initCarromSet() {
    double cx = boardSize / 2;
    double cy = boardSize / 2;
    coins.clear();
    playerScores = 0;
    secondaryScores = 0;
    shotExecuted = false;
    isMoving = false;
    isDragging = false; 
    sliderVal = cx;
    strikerPos = Offset(cx, boardSize - 78.0);
    isPlayerTurn = true;
    coins.add(Coin(pos: Offset(cx, cy), color: Colors.pinkAccent, isQueen: true)); 

    for (int i = 0; i < 6; i++) {
      double angle = i * (pi / 3);
      coins.add(Coin(pos: Offset(cx + cos(angle) * 16.0, cy + sin(angle) * 16.0), color: i % 2 == 0 ? Colors.white : Colors.black));
    }
    for (int i = 0; i < 12; i++) {
      double angle = i * (pi / 6) + (pi / 12);
      coins.add(Coin(pos: Offset(cx + cos(angle) * 32.0, cy + sin(angle) * 32.0), color: i % 2 == 0 ? Colors.black : Colors.white));
    }
  }

  void _triggerComboFlash(String msg) {
    setState(() {
      comboMessage = msg;
      messageOpacity = 1.0;
    });
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => messageOpacity = 0.0);
    });
  }

  void _updatePhysics(Duration elapsed) {
    if (!mounted) return;
    bool componentsMoving = false;
    double friction = 0.98; 
    bool boundaryHitOccurred = false;

    if (strikerVelocity.distance > 0.3) {
      componentsMoving = true;
      strikerPos += strikerVelocity;
      strikerVelocity *= friction;

      if (strikerPos.dx < boardMargin || strikerPos.dx > boardSize - boardMargin) {
        strikerVelocity = Offset(-strikerVelocity.dx, strikerVelocity.dy);
        strikerPos = Offset(strikerPos.dx.clamp(boardMargin, boardSize - boardMargin), strikerPos.dy);
        boundaryHitOccurred = true;
      }
      if (strikerPos.dy < boardMargin || strikerPos.dy > boardSize - boardMargin) {
        strikerVelocity = Offset(strikerVelocity.dx, -strikerVelocity.dy);
        strikerPos = Offset(strikerPos.dx, strikerPos.dy.clamp(boardMargin, boardSize - boardMargin));
        boundaryHitOccurred = true;
      }
    } else {
      strikerVelocity = Offset.zero; 
    }

    for (var coin in coins) {
      if (coin.velocity.distance > 0.2) {
        componentsMoving = true;
        coin.pos += coin.velocity;
        coin.velocity *= friction;

        if (coin.pos.dx < boardMargin || coin.pos.dx > boardSize - boardMargin) {
          coin.velocity = Offset(-coin.velocity.dx, coin.velocity.dy);
          coin.pos = Offset(coin.pos.dx.clamp(boardMargin, boardSize - boardMargin), coin.pos.dy);
          boundaryHitOccurred = true;
        }
        if (coin.pos.dy < boardMargin || coin.pos.dy > boardSize - boardMargin) {
          coin.velocity = Offset(coin.velocity.dx, -coin.velocity.dy);
          coin.pos = Offset(coin.pos.dx, coin.pos.dy.clamp(boardMargin, boardSize - boardMargin));
          boundaryHitOccurred = true;
        }
      } else {
        coin.velocity = Offset.zero;
      }
    }

    if (boundaryHitOccurred) {
      CarromSoundManager.playBoundaryHit();
    }

    for (var coin in coins) {
      double dist = (strikerPos - coin.pos).distance;
      if (dist <= 26.0 && strikerVelocity.distance > 0.5) {
        Offset normal = (coin.pos - strikerPos).normalize();
        coin.pos = strikerPos + (normal * 26.0);
        double dynamicForce = strikerVelocity.distance;
        coin.velocity = normal * (dynamicForce * 0.90);
        strikerVelocity = -normal * (dynamicForce * 0.20);
        componentsMoving = true;
        
        if (dynamicForce > 1.0) {
          CarromSoundManager.playCoinHit();
        }
      }
    }

    for (int i = 0; i < coins.length; i++) {
      for (int j = i + 1; j < coins.length; j++) {
        double dist = (coins[i].pos - coins[j].pos).distance;
        if (dist < 23.0) {
          Offset normal = (coins[j].pos - coins[i].pos).normalize();
          coins[j].pos = coins[i].pos + (normal * 23.0);
          Offset relativeVelocity = coins[i].velocity - coins[j].velocity;
          double speed = relativeVelocity.dx * normal.dx + relativeVelocity.dy * normal.dy;
          if (speed > 0) {
            Offset impulse = normal * speed;
            coins[i].velocity -= impulse * 0.9;
            coins[j].velocity += impulse * 0.9;
            componentsMoving = true;
            
            if (speed > 0.5) {
              CarromSoundManager.playCoinHit();
            }
          }
        }
      }
    }

    List<Offset> pockets = [
      Offset(pocketOffset, pocketOffset),
      Offset(boardSize - pocketOffset, pocketOffset),
      Offset(pocketOffset, boardSize - pocketOffset),
      Offset(boardSize - pocketOffset, boardSize - pocketOffset),
    ];
    coins.removeWhere((coin) {
      for (var pocket in pockets) {
        if ((coin.pos - pocket).distance < pocketRadius) {
          hasScoredInThisTurn = true;
          CarromSoundManager.playPocket();
          _triggerComboFlash(coin.isQueen ? "👑 QUEEN SINK!" : "💥 POINT SCORED!");
          if (isPlayerTurn) {
            playerScores += coin.isQueen ? 3 : 1;
          } else {
            secondaryScores += coin.isQueen ? 3 : 1;
          }
          return true;
        }
      }
      return false;
    });
    
    isMoving = componentsMoving;

    if (!isMoving && strikerVelocity == Offset.zero && shotExecuted) {
      shotExecuted = false;
      isDragging = false; 
      dragStart = null;   
      dragUpdate = null;  
      double cx = boardSize / 2;

      if (widget.gameMode == 'practice') {
        isPlayerTurn = true;
        hasScoredInThisTurn = false;
        sliderVal = cx;
        strikerPos = Offset(sliderVal, boardSize - 78.0);
      } 
      else if (widget.gameMode == 'local_2p') {
        if (!hasScoredInThisTurn) {
          isPlayerTurn = !isPlayerTurn;
        }
        hasScoredInThisTurn = false;
        sliderVal = cx;
        strikerPos = Offset(sliderVal, isPlayerTurn ? boardSize - 78.0 : 78.0);
      } 
      else if (widget.gameMode == 'online') {
        if (widget.isHost) {
          if (!hasScoredInThisTurn) {
            isPlayerTurn = !isPlayerTurn;
          }
          hasScoredInThisTurn = false;
          sliderVal = cx;
          
          bool myTurn = isPlayerTurn;
          strikerPos = Offset(sliderVal, myTurn ? boardSize - 78.0 : 78.0);

          if (widget.roomId != null) {
            nakamaSocket.sendMatchData(
              matchId: widget.roomId!,
              opCode: 2,
              data: "TURN;$isPlayerTurn".codeUnits,
            );
          }
        } else {
          hasScoredInThisTurn = false;
        }
      } else if (widget.gameMode == 'ai') {
        if (!hasScoredInThisTurn) {
          isPlayerTurn = !isPlayerTurn;
        }
        hasScoredInThisTurn = false;
        sliderVal = cx;
        strikerPos = Offset(sliderVal, isPlayerTurn ? boardSize - 78.0 : 78.0);
      }
    }

    if (coins.isEmpty && !isMoving) {
      _ticker.stop();
      bool userWon = playerScores >= secondaryScores;
      if (widget.gameMode == 'online' && widget.onMatchFinished != null) {
        widget.onMatchFinished!(userWon);
      }
      String winnerName = userWon ? widget.playerName : widget.player2Name;
      _showGameOverModal(userWon, winnerName);
    }

    if (!isMoving && strikerVelocity == Offset.zero && !isPlayerTurn && widget.gameMode == 'ai' && !shotExecuted) {
      _runAiSimulationTurn();
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _runAiSimulationTurn() {
    if (coins.isEmpty) return;
    int targetIndex = Random().nextInt(coins.length);
    Offset targetCoin = coins[targetIndex].pos;
    
    setState(() {
      strikerPos = Offset(boardSize / 2, 78.0);
    });

    Offset aiAimVector = (targetCoin - strikerPos).normalize();
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          strikerVelocity = aiAimVector * (6.0 + Random().nextDouble() * 6.0);
          shotExecuted = true;
          isDragging = false;
          isMoving = true;
        });
        CarromSoundManager.playStickerRelease();
      }
    });
  }

  void _shootStriker() {
    final start = dragStart;
    final update = dragUpdate;
    if (isMoving || start == null || update == null || shotExecuted) return;
    if (widget.gameMode == 'online' && widget.roomId != null) {
      bool myTurn = (isPlayerTurn == widget.isHost);
      if (!myTurn) return;
    }

    Offset shootVector = start - update;
    double force = (shootVector.distance * globalSpeedMultiplier).clamp(3.0, globalMaxForce); 
    
    if (widget.gameMode == 'online' && widget.roomId != null) {
      Offset normalizedVec = shootVector.normalize();
      nakamaSocket.sendMatchData(
        matchId: widget.roomId!,
        opCode: 3,
        data: "SHOT;${normalizedVec.dx};${normalizedVec.dy};$force".codeUnits,
      );
    }

    setState(() {
      strikerVelocity = shootVector.normalize() * force;
      dragStart = null;
      dragUpdate = null;
      isDragging = false;
      shotExecuted = true;
      isMoving = true; 
    });

    // FIXED: Play sound EXACTLY ONCE when striker is released / shot fired
    CarromSoundManager.playStickerRelease();
  }

  void _showGameOverModal(bool userWon, String winnerName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[950],
          title: Text(
            "🏆 CONGRATULATIONS $winnerName!", 
            style: const TextStyle(color: Colors.greenAccent), 
            textAlign: TextAlign.center,
          ),
          content: const Text("Winner has pocketed all coins successfully!", style: TextStyle(color: Colors.white70), textAlign: TextAlign.center),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text("Main Menu"),
            )
          ],
        );
      },
    );
  }

  Widget _buildSmartScroller() {
    if (shotExecuted || isMoving) return const SizedBox(height: 44);
    if (widget.gameMode == 'practice') return _scrollerUI(isTopSlider: false);
    if (widget.gameMode == 'ai' && !isPlayerTurn) return const SizedBox(height: 44); 

    if (widget.gameMode == 'local_2p') {
      return _scrollerUI(isTopSlider: !isPlayerTurn);
    }

    bool myTurn = (isPlayerTurn == widget.isHost);
    if (!myTurn) {
      return const SizedBox(height: 44); 
    }

    return _scrollerUI(isTopSlider: false);
  }

  Widget _scrollerUI({required bool isTopSlider}) {
    return Container(
      width: boardSize * 0.85,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isTopSlider ? Colors.purpleAccent.withOpacity(0.6) : Colors.cyanAccent.withOpacity(0.6), 
          width: 2
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          double minSliderLimit = 95.0;
          double maxSliderLimit = boardSize - 95.0;
          double maxWidth = constraints.maxWidth - 40; 
          double currentX = ((sliderVal - minSliderLimit) / (maxSliderLimit - minSliderLimit)) * maxWidth;

          return GestureDetector(
            onPanUpdate: (details) {
              if (shotExecuted || isMoving) return;
              if (widget.gameMode == 'online' && widget.roomId != null) {
                bool myTurn = (isPlayerTurn == widget.isHost);
                if (!myTurn) return;
              }

              setState(() {
                double localX = details.localPosition.dx.clamp(0.0, maxWidth);
                sliderVal = minSliderLimit + (localX / maxWidth) * (maxSliderLimit - minSliderLimit);
                strikerPos = Offset(sliderVal, isTopSlider ? 78.0 : boardSize - 78.0);
              });

              if (widget.gameMode == 'online' && widget.roomId != null) {
                nakamaSocket.sendMatchData(
                  matchId: widget.roomId!,
                  opCode: 1,
                  data: "SLIDER;$sliderVal".codeUnits,
                );
              }
            },
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(15, (index) => Container(width: 2, height: 8, color: Colors.white24)),
                ),
                Positioned(
                  left: currentX,
                  child: Container(
                    width: 40,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isTopSlider ? Colors.purpleAccent : widget.strikerColor, 
                      borderRadius: BorderRadius.circular(8)
                    ),
                    child: const Icon(Icons.unfold_more, color: Colors.black, size: 16),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _proScoreBadge(String name, int score, Color neonColor, bool isActive, bool isCurrentUser, String optionalImagePath) {
    ImageProvider? finalImage;
    if (isCurrentUser && widget.userImage != null) {
      finalImage = FileImage(widget.userImage!);
    } else if (!isCurrentUser && optionalImagePath.isNotEmpty) {
      finalImage = FileImage(File(optionalImagePath));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(15),
        border: isActive ? Border.all(color: neonColor, width: 2) : Border.all(color: Colors.grey[800]!, width: 1.5),
        boxShadow: isActive ? [BoxShadow(color: neonColor.withOpacity(0.15), blurRadius: 8)] : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: neonColor.withOpacity(0.3),
            backgroundImage: finalImage,
            child: finalImage == null ? Icon(isCurrentUser ? Icons.person : Icons.blur_on, color: Colors.white70, size: 18) : null,
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.length > 10 ? "${name.substring(0, 9)}.." : name, 
                style: TextStyle(color: isActive ? Colors.white : Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)
              ),
              Text("$score PTS", style: TextStyle(color: neonColor, fontSize: 16, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    if (isFullScreenBoard) {
      boardSize = screenWidth.clamp(320.0, 500.0);
    } else {
      boardSize = 400.0; 
    }

    String secondPlayerName = widget.gameMode == 'online' ? oppName : (widget.gameMode == 'ai' ? "AI Bot" : widget.player2Name);
    bool currentIsMyTurn = (widget.gameMode == 'local_2p') ? isPlayerTurn : (isPlayerTurn == widget.isHost);
    bool alignTopLayout = (widget.gameMode == 'local_2p' && !isPlayerTurn);

    return Scaffold(
      floatingActionButton: widget.gameMode == 'online' && widget.roomId != null
          ? FloatingActionButton(
              backgroundColor: Colors.cyanAccent,
              child: const Icon(Icons.chat, color: Colors.black),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (context) => InGameChatWidget(
                    socket: nakamaSocket,
                    matchId: widget.roomId!,
                    currentUserName: widget.playerName,
                  ),
                );
              },
            )
          : null,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF050714), Color(0xFF110720), Color(0xFF020207)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                      Text(widget.gameMode.toUpperCase(), style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      IconButton(icon: const Icon(Icons.refresh, color: Colors.cyanAccent), onPressed: () => _initCarromSet()),
                    ],
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _proScoreBadge(widget.playerName, playerScores, Colors.cyanAccent, currentIsMyTurn, true, ""),
                    if (widget.gameMode != 'practice') 
                      _proScoreBadge(secondPlayerName, secondaryScores, Colors.purpleAccent, !currentIsMyTurn, false, oppAvatarPath),
                  ],
                ),
                const SizedBox(height: 15),
                
                if (alignTopLayout) _buildSmartScroller() else const SizedBox(height: 44),
                const SizedBox(height: 10),

                GestureDetector(
                  onPanStart: (details) {
                    if (isMoving || shotExecuted) return;
                    if (widget.gameMode == 'online' && widget.roomId != null) {
                      bool myTurn = (isPlayerTurn == widget.isHost);
                      if (!myTurn) return;
                    }

                    if ((details.localPosition - strikerPos).distance < 35) {
                      setState(() {
                        dragStart = details.localPosition;
                        dragUpdate = details.localPosition;
                        isDragging = true;
                      });
                    }
                  },
                  onPanUpdate: (details) { 
                    if (isDragging) {
                      setState(() => dragUpdate = details.localPosition);
                    } 
                  },
                  onPanEnd: (details) { if (isDragging) _shootStriker(); },
                  child: Container(
                    width: boardSize,
                    height: boardSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.cyanAccent.withOpacity(0.12), blurRadius: 35, spreadRadius: 4)],
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.asset(
                            'assets/board.png', 
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(color: const Color(0xFF140D07)),
                          ),
                        ),
                        Positioned.fill(
                          child: CustomPaint(
                            child: const SizedBox.expand(),
                            painter: ProBoardEnginePainter(
                              strikerPos: strikerPos,
                              dragStart: isDragging ? dragStart : null,
                              dragUpdate: isDragging ? dragUpdate : null,
                              coins: coins,
                              strikerColor: widget.strikerColor,
                              blackCoinImg: blackCoinImg,
                              whiteCoinImg: whiteCoinImg,
                              redCoinImg: redCoinImg,
                              stickerCoinImg: stickerCoinImg,
                            ),
                          ),
                        ),
                        
                        AnimatedOpacity(
                          opacity: messageOpacity,
                          duration: const Duration(milliseconds: 300),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.amber, width: 2),
                              ),
                              child: Text(
                                comboMessage,
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                
                if (!alignTopLayout) _buildSmartScroller() else const SizedBox(height: 44),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InGameChatWidget extends StatefulWidget {
  final NakamaWebsocketClient socket;
  final String matchId;
  final String currentUserName;

  const InGameChatWidget({Key? key, required this.socket, required this.matchId, required this.currentUserName}) : super(key: key);

  @override
  State<InGameChatWidget> createState() => _InGameChatWidgetState();
}

class _InGameChatWidgetState extends State<InGameChatWidget> {
  final TextEditingController _msgController = TextEditingController();
  final List<String> _messages = [];

  @override
  void initState() {
    super.initState();
    widget.socket.onMatchData.listen((MatchData data) {
      if (data.matchId == widget.matchId && data.data != null) {
        final content = String.fromCharCodes(data.data!);
        if (content.startsWith("CHAT;")) {
          final parts = content.split(";");
          if (parts.length >= 3 && mounted) {
            setState(() => _messages.add("${parts[1]}: ${parts[2]}"));
          }
        }
      }
    });
  }

  void _sendMessage() {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    widget.socket.sendMatchData(
      matchId: widget.matchId,
      opCode: 4,
      data: "CHAT;${widget.currentUserName};$text".codeUnits,
    );
    setState(() {
      _messages.add("You: $text");
      _msgController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 320,
      decoration: const BoxDecoration(color: Color(0xFF121420), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          const Text("💬 LIVE MATCH CHAT", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
          const Divider(color: Colors.white24),
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(_messages[index], style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _msgController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(hintText: "Type message...", hintStyle: TextStyle(color: Colors.white38)),
                ),
              ),
              IconButton(icon: const Icon(Icons.send, color: Colors.cyanAccent), onPressed: _sendMessage),
            ],
          ),
        ],
      ),
    );
  }
}

class ProBoardEnginePainter extends CustomPainter {
  final Offset strikerPos;
  final Offset? dragStart;
  final Offset? dragUpdate;
  final List<Coin> coins;
  final Color strikerColor;
  final ui.Image? blackCoinImg;
  final ui.Image? whiteCoinImg;
  final ui.Image? redCoinImg;
  final ui.Image? stickerCoinImg;

  ProBoardEnginePainter({
    required this.strikerPos, 
    this.dragStart, 
    this.dragUpdate, 
    required this.coins, 
    required this.strikerColor,
    this.blackCoinImg,
    this.whiteCoinImg,
    this.redCoinImg,
    this.stickerCoinImg,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;

    for (var coin in coins) {
      ui.Image? imgToDraw;
      if (coin.isQueen) {
        imgToDraw = redCoinImg;
      } else if (coin.color == Colors.white) {
        imgToDraw = whiteCoinImg;
      } else {
        imgToDraw = blackCoinImg;
      }

      Rect rect = Rect.fromCircle(center: coin.pos, radius: 12.0);

      if (imgToDraw != null) {
        paint.filterQuality = FilterQuality.high;
        canvas.drawImageRect(
          imgToDraw,
          Rect.fromLTWH(0, 0, imgToDraw.width.toDouble(), imgToDraw.height.toDouble()),
          rect,
          paint,
        );
      } else {
        paint.color = Colors.black87;
        canvas.drawCircle(coin.pos + const Offset(1.0, 1.0), 12.5, paint);
        paint.color = coin.isQueen ? Colors.pinkAccent : coin.color;
        canvas.drawCircle(coin.pos, 12.0, paint);
      }
    }

    if (stickerCoinImg != null) {
      Rect strikerRect = Rect.fromCircle(center: strikerPos, radius: 14.0);
      paint.filterQuality = FilterQuality.high;
      canvas.drawImageRect(
        stickerCoinImg!,
        Rect.fromLTWH(0, 0, stickerCoinImg!.width.toDouble(), stickerCoinImg!.height.toDouble()),
        strikerRect,
        paint,
      );
    } else {
      paint.color = strikerColor;
      canvas.drawCircle(strikerPos, 14, paint);
    }

    final startPoint = dragStart;
    final updatePoint = dragUpdate;
    if (startPoint != null && updatePoint != null) {
      Offset forceVector = startPoint - updatePoint;
      Offset targetAimPoint = strikerPos + (forceVector * 0.75);

      paint.color = Colors.greenAccent.withOpacity(0.25);
      paint.strokeWidth = 6.0;
      canvas.drawLine(strikerPos, targetAimPoint, paint);

      paint.color = Colors.greenAccent;
      paint.strokeWidth = 2.0;
      canvas.drawLine(strikerPos, targetAimPoint, paint);

      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 1.5;
      canvas.drawCircle(targetAimPoint, 6.0, paint);
      
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(targetAimPoint, 2.0, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) =>true;
}

class Coin {
  Offset pos;
  Offset velocity;
  Color color;
  bool isQueen;
  Coin({required this.pos, required this.color, this.velocity = Offset.zero, this.isQueen = false});
}

extension OffsetExtension on Offset {
  Offset normalize() {
    double len = distance;
    if (len == 0) return Offset.zero;
    return Offset(dx / len, dy / len);
  }
}