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
  bool _hasAccess = false;
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
    _fetchImages();
  }

  void _initHeartAnimation() {
    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _heartScale = Tween<double>(begin: 0.6, end: 1.3).animate(
      CurvedAnimation(parent: _heartAnimController, curve: Curves.easeOutBack),
    );
    _heartOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _heartAnimController, curve: const Interval(0.5, 1.0, curve: Curves.easeIn)),
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

  Future<void> _fetchImages() async {
    // Android 14/15/16 supports limited or full access
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    
    if (ps.isAuth || ps.hasAccess) {
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );

      if (albums.isNotEmpty) {
        final List<AssetEntity> media = await albums[0].getAssetListRange(
          start: 0,
          end: 500, // Load initial chunk for top performance
        );
        setState(() {
          _images = media;
          _hasAccess = true;
          _isLoading = false;
        });
        return;
      }
    }

    setState(() {
      _hasAccess = ps.isAuth || ps.hasAccess;
      _isLoading = false;
    });
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

    // Under modern Android, PhotoManager triggers the mandatory OS deletion dialog
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

  @override
  void dispose() {
    _heartAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5),
        ),
      );
    }

    if (!_hasAccess) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'STORAGE ACCESS REQUIRED',
                style: TextStyle(color: Colors.white, letterSpacing: 1.5, fontSize: 13),
              ),
              const SizedBox(height: 12),
              const Text(
                'Select "Allow all" in Android settings.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white38),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                onPressed: () => PhotoManager.openSetting(),
                child: const Text('OPEN SETTINGS', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
        ),
      );
    }

    if (_images.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('NO PHOTOS FOUND', style: TextStyle(color: Colors.white24, letterSpacing: 2.0)),
        ),
      );
    }

    final currentAsset = _images[_currentIndex];
    final isFav = _favorites.contains(currentAsset.id);

    return Scaffold(
      body: Stack(
        children: [
          // Vertical Reels-Style Snap
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
                // Optimized image loader: does not crash RAM on 50MP shots
                child: AssetEntityImage(
                  _images[index],
                  isOriginal: false,
                  thumbnailSize: const ThumbnailSize(1080, 2400),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white10, strokeWidth: 1.0),
                    );
                  },
                ),
              );
            },
          ),

          // Nothing Red Animated Heart
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
                      color: Color(0xFFD71921), // Nothing Red
                      size: 90,
                    ),
                  ),
                );
              },
            ),
          ),

          // Top Info Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(_currentIndex + 1).toString().padLeft(2, '0')} / ${_images.length.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: Colors.white60,
                      letterSpacing: 2.5,
                      fontSize: 12,
                    ),
                  ),
                  Row(
                    children: [
                      if (isFav)
                        const Padding(
                          padding: EdgeInsets.only(right: 14),
                          child: Icon(Icons.favorite, color: Color(0xFFD71921), size: 18),
                        ),
                      GestureDetector(
                        onTap: _deleteCurrentImage,
                        child: const Icon(Icons.delete_outline, color: Colors.white60, size: 20),
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
