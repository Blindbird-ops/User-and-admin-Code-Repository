// lib/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _controller = PageController();
  int _page = 0;
  final int _totalPages = 4;

  late final AnimationController _gradientCtrl;

  @override
  void initState() {
    super.initState();
    _gradientCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat();
  }

  Future<void> _complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingCompleted', true);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _next() {
    if (_page < _totalPages - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _complete();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _gradientCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padTop = MediaQuery.of(context).padding.top;
    final padBottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      extendBodyBehindAppBar: true, 
      body: AnimatedBuilder(
        animation: _gradientCtrl,
        builder: (_, __) {
          final anim = _gradientCtrl.value; 
          return Stack(
            children: [
              // 1. Pages
              PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _OnboardPageOne(anim: anim),   
                  _OnboardPageTwo(anim: anim),   
                  _OnboardPageThree(anim: anim), 
                  _OnboardPageFour(anim: anim),  
                ],
              ),

              // 2. Skip Button
              Positioned(
                top: padTop + 8,
                right: 12,
                child: TextButton(
                  onPressed: _complete,
                  child: Text(
                    'Skip',
                    style: GoogleFonts.lato(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      shadows: [
                         const Shadow(blurRadius: 4, color: Colors.black54, offset: Offset(0, 1))
                      ]
                    ),
                  ),
                ),
              ),

              // 3. Navigation (Dots + Button)
              Positioned(
                left: 0,
                right: 0,
                bottom: padBottom + 24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Dots(current: _page, len: _totalPages),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _next,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF7AC8),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 5,
                          ),
                          child: Text(
                            _page == _totalPages - 1 ? 'Get Started' : 'Next',
                            style: GoogleFonts.lato(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int current;
  final int len;
  const _Dots({required this.current, required this.len});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(len, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
          ),
        );
      }),
    );
  }
}

const List<Color> _bwTextColors = [
  Color(0xFF000000),
  Color(0xFF9E9E9E),
  Color(0xFF000000),
];

// --- PAGE 1: TEXT AT TOP, LOGO BELOW ---
class _OnboardPageOne extends StatelessWidget {
  final double anim;
  const _OnboardPageOne({required this.anim});

  @override
  Widget build(BuildContext context) {
    final double topGap = MediaQuery.of(context).padding.top + 60;
    const double opticalShift = 6;

    return _LeftBottomOblongScene(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: topGap),
            Align(
              alignment: Alignment.center,
              child: Transform.translate(
                offset: const Offset(opticalShift, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AnimatedGradientText(
                      'Welcome',
                      anim: anim,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.lato(
                        fontSize: 40,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _AnimatedGradientText(
                      'Barangay Services App',
                      anim: anim,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.lato(
                        fontSize: 18,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
           
// --- REPLACE THIS SECTION IN _OnboardPageOne ---

Expanded(
  child: Stack(
    alignment: Alignment.center,
    children: [
      // 1. THE GLOW EFFECT (The "Complimentary" Fix)
      // This creates a soft light behind the logo so the dark text pops
      Container(
        width: 160, 
        height: 160,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent, 
          boxShadow: [
            BoxShadow(
              color: Colors.white.withOpacity(0.5), // Adjust opacity for intensity
              blurRadius: 80, // High blur makes it look like a light source, not a shadow
              spreadRadius: 10,
            ),
            BoxShadow(
              color: Colors.purple.shade100.withOpacity(0.3), // A hint of purple to blend
              blurRadius: 60,
              spreadRadius: 20,
            ),
          ],
        ),
      ),
      
      // 2. YOUR ACTUAL LOGO
      Builder(
        builder: (context) {
          return Image.asset(
            'assets/images/LOGO transparent.png', 
            fit: BoxFit.contain,
            alignment: Alignment.center,
            // Basic error handling if image isn't found
            errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 100, color: Color.fromARGB(255, 255, 255, 255)),
          );
        },
      ),
    ],
  ),
),

// --- END OF REPLACEMENT ---
            Text(
              'Easily request documents and\nservices!',
              style: GoogleFonts.lato(
                fontSize: 16,
                color: const Color.fromARGB(255, 144, 5, 172),
                height: 1.3,
                shadows: const [
                  Shadow(blurRadius: 5, color: Colors.black38, offset: Offset(0, 2))
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 120), 
          ],
        ),
      ),
    );
  }
}

// --- PAGE 2: HALL FIRST, THEN TAGS ---
class _OnboardPageTwo extends StatelessWidget {
  final double anim;
  const _OnboardPageTwo({required this.anim});

  @override
  Widget build(BuildContext context) {
    final double topGap = MediaQuery.of(context).padding.top + 56;
    const double opticalShift = 6;
    final double logoHeight = MediaQuery.of(context).size.height * 0.45;
    const taglineColors = [Color.fromARGB(255, 7, 7, 7), Colors.grey, Color.fromARGB(255, 0, 0, 0)];

    return _LeftBottomOblongScene(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: topGap),
            SizedBox(
              height: logoHeight,
              child: Image.asset(
                'assets/images/barangay_hall.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(Icons.apartment, size: logoHeight * 0.6, color: Colors.white),
              ),
            ),
            const SizedBox(height: 30),
            Align(
              alignment: Alignment.center,
              child: Transform.translate(
                offset: const Offset(opticalShift, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AnimatedTagStrip(text: '“Serving the Community”', anim: anim, colors: taglineColors),
                    const SizedBox(height: 12),
                    _AnimatedTagStrip(text: 'with Care and Commitment”', anim: anim, colors: taglineColors),
                  ],
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

// --- PAGE 3: REQUEST DOCS ---
class _OnboardPageThree extends StatelessWidget {
  final double anim;
  const _OnboardPageThree({required this.anim});

  @override
  Widget build(BuildContext context) {
    final double topGap = MediaQuery.of(context).padding.top + 56;
    final double logoHeight = MediaQuery.of(context).size.height * 0.45;

    return _LeftBottomOblongScene(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: topGap),
            SizedBox(
              height: logoHeight,
              child: Image.asset(
                'assets/images/request_documents.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(Icons.description_outlined, size: logoHeight * 0.6, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AnimatedGradientText(
                    'Request Documents',
                    anim: anim,
                    colors: _bwTextColors,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lato(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  _AnimatedGradientText(
                    'Request and track your documents online!',
                    anim: anim,
                    colors: _bwTextColors,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lato(fontSize: 14, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ],
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

// --- PAGE 4: VIDEO TUTORIAL (PURPLE BG + NO CROP) ---
class _OnboardPageFour extends StatefulWidget {
  final double anim;
  const _OnboardPageFour({required this.anim});

  @override
  State<_OnboardPageFour> createState() => _OnboardPageFourState();
}

class _OnboardPageFourState extends State<_OnboardPageFour> {
  late VideoPlayerController _videoController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.asset('assets/videos/tutorial.mp4')
      ..initialize().then((_) {
        setState(() {
          _initialized = true;
        });
        _videoController.setVolume(0.0);
        _videoController.setLooping(true);
        _videoController.play();
      });
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Replaced "Colors.black" with the App's Gradient
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade500, Colors.deepPurple.shade700],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          // 2. VIDEO PLAYER (Uncropped)
          if (_initialized)
            Center(
              child: AspectRatio(
                aspectRatio: _videoController.value.aspectRatio,
                child: VideoPlayer(_videoController),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // 3. Optional: Subtle overlay to make text readable 
          // (Can remove if you want pure video and background)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black26, 
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black45, 
                ],
                stops: [0.0, 0.2, 0.7, 1.0],
              ),
            ),
          ),

          // 4. Text Overlay
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.of(context).size.height * 0.15,
            child: Column(
              children: [
                Text(
                  'Quick Tutorial',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.lato(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    shadows: [
                      const Shadow(blurRadius: 8, color: Colors.black, offset: Offset(0, 2))
                    ],
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// --- HELPERS ---

class _AnimatedTagStrip extends StatelessWidget {
  final String text;
  final double anim;
  final List<Color> colors;
  const _AnimatedTagStrip({required this.text, required this.anim, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFC9F7F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF8FE1DD)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: _AnimatedGradientText(
        text,
        anim: anim,
        colors: colors,
        stops: const [0.25, 0.5, 0.75],
        style: GoogleFonts.lato(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black),
      ),
    );
  }
}

class _AnimatedGradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double anim; 
  final List<Color>? colors;
  final List<double>? stops;
  final TextAlign textAlign;

  const _AnimatedGradientText(
    this.text, {
    required this.style,
    required this.anim,
    this.colors,
    this.stops,
    this.textAlign = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    final double shift = anim * 2 - 1; 
    final List<Color> usedColors = colors ?? [Colors.white.withOpacity(0.65), Colors.white, Colors.white.withOpacity(0.65)];
    final List<double> usedStops = stops ?? const [0.25, 0.5, 0.75];

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: Alignment(-1.5 + shift, 0),
          end: Alignment(1.5 + shift, 0),
          colors: usedColors,
          stops: usedStops,
        ).createShader(bounds);
      },
      child: Text(text, style: style, textAlign: textAlign),
    );
  }
}

class _LeftBottomOblongScene extends StatelessWidget {
  final Widget child;
  const _LeftBottomOblongScene({required this.child});

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final double oblongHeight = h * 1.18;
    final double oblongWidth = oblongHeight * 0.75;
    const double leftMargin = 1;
    final double bottomOffset = -h * 0.48;

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.deepPurple.shade500, Colors.deepPurple.shade700],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Positioned(
          left: leftMargin,
          bottom: bottomOffset,
          child: ClipOval(
            child: Container(width: oblongWidth, height: oblongHeight, color: Colors.white),
          ),
        ),
        IgnorePointer(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color.fromARGB(41, 0, 0, 0), Colors.transparent],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}