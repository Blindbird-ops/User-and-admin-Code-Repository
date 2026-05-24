// lib/services/python_service.dart

import 'dart:io';
// For SystemEncoding
import 'package:flutter/foundation.dart'; // For kReleaseMode, kDebugMode
import 'package:path/path.dart' as p;

class PythonBackendService {
  static Process? _process;
  static bool _isRunning = false;
  static DateTime? _startTime;
  static int _documentCount = 0;

  /// Starts the Python backend.
  static Future<void> start() async {
    if (_isRunning) {
      print('⚠️  Python backend already running');
      return;
    }

    try {
      String executable;
      List<String> arguments = [];
      String workingDir;

      // =======================================================================
      // 1. DETERMINE PATHS BASED ON MODE
      // =======================================================================
      if (kReleaseMode) {
        // ---------------------------------------------------------------------
        // 🚀 PRODUCTION MODE (Installed App)
        // ---------------------------------------------------------------------
        final exeDir = p.dirname(Platform.resolvedExecutable);
        final bundledExePath = p.join(exeDir, 'bin', 'doc_generator.exe');

        if (!File(bundledExePath).existsSync()) {
          print('❌ CRITICAL ERROR: Python EXE not found at: $bundledExePath');
          return;
        }

        executable = bundledExePath;
        workingDir = p.dirname(bundledExePath);
        print('🚀 STARTING PRODUCTION BACKEND (EXE): $bundledExePath');

      } else {
        // ---------------------------------------------------------------------
        // 🐛 DEBUG MODE (Development)
        // ---------------------------------------------------------------------
        final projectRoot = Directory.current.path;
        final pythonFolder = p.join(projectRoot, 'python_backend'); 
        final scriptPath = p.join(pythonFolder, 'barangay_generation.py');

        if (!File(scriptPath).existsSync()) {
          print('❌ DEBUG ERROR: Python script not found at: $scriptPath');
          return;
        }

        executable = Platform.isWindows ? 'python' : 'python3';
        arguments = [scriptPath];
        workingDir = pythonFolder;
        print('🐛 STARTING DEBUG BACKEND (SCRIPT): $scriptPath');
      }

      // =======================================================================
      // 2. START THE PROCESS
      // =======================================================================
      
      final environment = <String, String>{
        'PYTHONIOENCODING': 'utf-8',
        'PYTHONUNBUFFERED': '1', 
      };

      _process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDir,
        mode: ProcessStartMode.normal,
        environment: environment,
      );

      _isRunning = true;
      _startTime = DateTime.now();
      _documentCount = 0;

      print('✅ Python backend started successfully (PID: ${_process!.pid})');

      // =======================================================================
      // 3. LISTEN TO OUTPUT LOGS
      // =======================================================================

      _process!.stdout.transform(const SystemEncoding().decoder).listen(
        (data) {
          final output = data.trim();
          if (output.isNotEmpty) {
            if (kDebugMode) print('PY: $output');

            // Logic to count generated documents
            if (output.contains('SUCCESS!') || output.contains('✅ SUCCESS')) {
              _documentCount++;
              if (kDebugMode) print('📊 Document count updated: $_documentCount');
            }
          }
        },
        onError: (error) => print('❌ Python stdout stream error: $error'),
      );

      _process!.stderr.transform(const SystemEncoding().decoder).listen(
        (data) {
           final output = data.trim();
           if (output.isNotEmpty) print('⚠️ PYTHON ERR: $output');
        },
        onError: (error) => print('❌ Python stderr stream error: $error'),
      );

      _process!.exitCode.then((code) {
        _isRunning = false;
        print('🛑 Python backend stopped (Exit Code: $code)');
      });

    } catch (e, stackTrace) {
      _isRunning = false;
      print('❌ FAILED TO START PYTHON BACKEND: $e');
      if (kDebugMode) print(stackTrace);
    }
  }
  static void forceKill() {
    if (_process != null) {
      print('💀 FORCE KILLING Python Backend (PID: ${_process!.pid})...');
      // On Windows, sigkill is the most reliable way to stop an exe
      _process!.kill(ProcessSignal.sigkill); 
      _process = null;
      _isRunning = false;
    }
  }

  /// Stops the Python backend safely
  static Future<void> stop() async {
    if (_process != null) {
      print('🛑 Stopping Python backend...');
      _process!.kill(ProcessSignal.sigterm);
      await Future.delayed(const Duration(seconds: 1));
      if (_isRunning) {
         _process!.kill(ProcessSignal.sigkill);
      }
      _process = null;
      _isRunning = false;
      print('✅ Python backend stopped.');
    }
  }

  static Future<void> restart() async {
    await stop();
    await Future.delayed(const Duration(seconds: 2));
    await start();
  }

  // ===========================================================================
  // GETTERS (This is what fixed your error)
  // ===========================================================================
  
  static bool get isRunning => _isRunning;
  
  // This was missing before:
  static int? get pid => _process?.pid; 
  
  static int get documentCount => _documentCount;
  
  static int get uptimeMinutes {
    if (_startTime == null || !_isRunning) return 0;
    return DateTime.now().difference(_startTime!).inMinutes;
  }
}