import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NothingGalleryApp());
}

class NothingGalleryApp extends StatelessWidget {
  const NothingGalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.black,
        brightness: Brightness.dark,
        fontFamily: 'monospace',
      ),
      home: const GalleryScreen(),
    );
  }
}

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> with SingleTickerProviderStateMixin {
  List<AssetEntity> _images = [];
  bool _isLoading = true;
  bool _permissionDenied = false;
  int _currentIndex = 0;
  Set<String> _favorites = {};

  late AnimationController _heartAnimController;
  late Animation<double> _heartScale;
  late Animation<double> _heartOpacity;

  @override
  void initState() {
    super.initState();
    _initHeartAnimation();
    _loadFavorites();
    _fetchLocalImages();
  }

  void _initHeartAnimation() {
    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _heartScale = Tween<double>(begin: 0.6, end: 1.3).animate(
      CurvedAnimation(parent: _heartAnimController, curve: Curves.easeOutBack),
    );
    _heartOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _heartAnimController, curve: const Interval(0.6, 1.0, curve: Curves.easeIn)),
    );
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _favorites = (prefs.getStringList('favorite_ids') ?? []).toSet();
    });
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorite_ids', _favorites.toList());
  }

  Future<void> _fetchLocalImages() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth && !ps.hasAccess) {
      setState(() {
        _permissionDenied = true;
        _isLoading = false;
      });
      return;
    }

    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );

    if (albums.isNotEmpty) {
      final List<AssetEntity> media = await albums[0].getAssetListRange(
        start: 0,
        end: 1000,
      );
      setState(() {
        _images = media;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _toggleFavorite(String id) {
    setState(() {
      if (_favorites.contains(id)) {
        _favorites.remove(id);
      } else {
        _favorites.add(id);
      }
    });
    _saveFavorites();
    _heartAnimController.forward(from: 0.0);
  }

  Future<void> _deleteCurrentImage() async {
    if (_images.isEmpty) return;
    final currentAsset = _images[_currentIndex];

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: Colors.white24, width: 1),
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        title: const Text('DELETE PHOTO?', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          'This will permanently remove the file from your device.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE', style: TextStyle(color: Color(0xFFD71921), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final List<String> result = await PhotoManager.editor.deleteWithIds([currentAsset.id]);
      if (result.isNotEmpty) {
        setState(() {
          _images.removeAt(_currentIndex);
          if (_currentIndex >= _images.length && _images.isNotEmpty) {
            _currentIndex = _images.length - 1;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _heartAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionDenied) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('STORAGE PERMISSION NEEDED', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white)),
                onPressed: () => PhotoManager.openSetting(),
                child: const Text('OPEN SETTINGS', style: TextStyle(color: Colors.white)),
              )
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5),
        ),
      );
    }

    if (_images.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('NO PHOTOS FOUND', style: TextStyle(color: Colors.white38)),
        ),
      );
    }

    final currentAsset = _images[_currentIndex];
    final isFav = _favorites.contains(currentAsset.id);

    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            scrollDirection: Axis.vertical,
            itemCount: _images.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return GestureDetector(
                onDoubleTap: () => _toggleFavorite(_images[index].id),
                child: Center(
                  child: FutureBuilder<File?>(
                    future: _images[index].file,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
                        return Image.file(
                          snapshot.data!,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                        );
                      }
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white12, strokeWidth: 1.0),
                      );
                    },
                  ),
                ),
              );
            },
          ),
          Center(
            child: AnimatedBuilder(
              animation: _heartAnimController,
              builder: (context, child) {
                return Opacity(
                  opacity: _heartOpacity.value,
                  child: Transform.scale(
                    scale: _heartScale.value,
                    child: const Icon(
                      Icons.favorite,
                      color: Color(0xFFD71921),
                      size: 90,
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(_currentIndex + 1).toString().padLeft(2, '0')} / ${_images.length.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: Colors.white70,
                      letterSpacing: 2.0,
                      fontSize: 12,
                    ),
                  ),
                  Row(
                    children: [
                      if (isFav)
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Icon(Icons.favorite, color: Color(0xFFD71921), size: 18),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.white70, size: 20),
                        onPressed: _deleteCurrentImage,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
