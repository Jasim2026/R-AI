import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/gradient_background.dart';
import '../utils/theme.dart';

class PermissionScreen extends StatefulWidget {
  final VoidCallback? onPermissionGranted;

  const PermissionScreen({super.key, this.onPermissionGranted});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _isRequesting = false;
  bool _allGranted = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final statuses = await [
      Permission.storage,
      Permission.manageExternalStorage,
    ].request();

    setState(() {
      _allGranted = statuses[Permission.storage]!.isGranted &&
          (statuses[Permission.manageExternalStorage]!.isGranted ||
              statuses[Permission.manageExternalStorage]!.isLimited);
    });
  }

  Future<void> _requestPermissions() async {
    setState(() => _isRequesting = true);

    try {
      // First request standard storage permission
      var status = await Permission.storage.request();

      if (!status.isGranted) {
        // If denied, try to open app settings
        await openAppSettings();
        status = await Permission.storage.request();
      }

      // For Android 11+, also request manage external storage
      if (status.isGranted) {
        final manageStatus = await Permission.manageExternalStorage.request();
        setState(() {
          _allGranted = manageStatus.isGranted || manageStatus.isLimited;
        });
      } else {
        setState(() {
          _allGranted = false;
        });
      }
    } catch (e) {
      setState(() {
        _allGranted = false;
      });
    } finally {
      setState(() => _isRequesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withOpacity(0.2),
                        AppColors.accent.withOpacity(0.2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Icon(
                    Icons.folder_open_rounded,
                    size: 48,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Storage Access Required',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'R-AI needs access to your storage to load vector databases '
                  'and embedding models for RAG (Retrieval-Augmented Generation).',
                  style: TextStyle(
                    color: AppColors.textHint,
                    fontSize: 15,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.divider,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.accent.withOpacity(0.7),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Vector database expected at:\n/storage/emulated/0/R-AI/vector.db',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: Material(
                    color: _allGranted ? AppColors.success : AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _isRequesting
                          ? null
                          : _allGranted
                              ? () {
                                  widget.onPermissionGranted?.call();
                                  Navigator.of(context).pop(true);
                                }
                              : _requestPermissions,
                      child: Center(
                        child: _isRequesting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _allGranted ? 'Continue' : 'Grant Permission',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                if (_allGranted) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      widget.onPermissionGranted?.call();
                      Navigator.of(context).pop(true);
                    },
                    child: const Text(
                      'Skip for now',
                      style: TextStyle(
                        color: AppColors.textHint,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
