import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_exception.dart';
import '../repositories/settings_repository.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/app_feedback.dart';

/// Account profile: display name, avatar, and password change. The avatar
/// is never uploaded anywhere (no S3/R2, no server round trip, never sent
/// to the AI provider) — it's copied into this device's app-documents
/// directory and only the local file path is persisted, purely for
/// re-rendering on this device.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _settingsRepo = SettingsRepository();

  final _nameFormKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();

  final _passwordFormKey = GlobalKey<FormState>();
  final _oldPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  bool _savingName = false;
  bool _savingPassword = false;
  bool _pickingAvatar = false;

  String? _avatarPath;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = AuthService.instance.currentUser?.name ?? '';
    _loadAvatar();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _oldPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAvatar() async {
    final path = await _settingsRepo.get(SettingKeys.profileAvatarPath);
    if (!mounted || path == null) return;
    // The saved path might point at a file that's since been removed
    // (cleared cache, reinstalled app) — verify before trusting it so the
    // UI falls back to initials instead of a broken image.
    if (await File(path).exists()) {
      setState(() => _avatarPath = path);
    }
  }

  Future<void> _pickAvatar() async {
    if (_pickingAvatar) return;
    setState(() => _pickingAvatar = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (picked == null) return;

      final docsDir = await getApplicationDocumentsDirectory();
      final avatarDir = Directory(p.join(docsDir.path, 'avatar'));
      if (!await avatarDir.exists()) {
        await avatarDir.create(recursive: true);
      }
      final ext = p.extension(picked.path).isEmpty
          ? '.jpg'
          : p.extension(picked.path);
      final destPath = p.join(
        avatarDir.path,
        'profile_${DateTime.now().millisecondsSinceEpoch}$ext',
      );
      await File(picked.path).copy(destPath);

      // Best-effort cleanup of the previous avatar file — never let a
      // failure here (permissions, already gone) block saving the new one.
      final previous = _avatarPath;
      if (previous != null && previous != destPath) {
        try {
          final file = File(previous);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }

      await _settingsRepo.set(SettingKeys.profileAvatarPath, destPath);
      if (!mounted) return;
      setState(() => _avatarPath = destPath);
    } catch (e) {
      if (mounted) {
        AppFeedback.showErrorToast(context, 'Could not set profile photo');
      }
    } finally {
      if (mounted) setState(() => _pickingAvatar = false);
    }
  }

  Future<void> _saveName() async {
    if (!_nameFormKey.currentState!.validate()) return;
    setState(() => _savingName = true);
    try {
      await AuthService.instance.updateName(_nameCtrl.text.trim());
      if (!mounted) return;
      AppFeedback.showSuccessToast(context, 'Name updated');
    } catch (e) {
      if (!mounted) return;
      final message = switch (e) {
        AppException(:final message) => message,
        ApiException(:final message) => message,
        _ => 'Could not update name',
      };
      AppFeedback.showErrorToast(context, message);
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    setState(() => _savingPassword = true);
    try {
      await AuthService.instance.changePassword(
        oldPassword: _oldPasswordCtrl.text,
        newPassword: _newPasswordCtrl.text,
      );
      if (!mounted) return;
      _oldPasswordCtrl.clear();
      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();
      AppFeedback.showSuccessToast(context, 'Password changed');
    } catch (e) {
      if (!mounted) return;
      final message = switch (e) {
        AppException(:final message) => message,
        ApiException(:final message) => message,
        _ => 'Could not change password',
      };
      AppFeedback.showErrorToast(context, message);
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  String? _requiredValidator(String? value, String label) {
    if (value == null || value.trim().isEmpty) return 'Enter $label';
    return null;
  }

  String? _newPasswordValidator(String? value) {
    if (value == null || value.isEmpty) return 'Enter a new password';
    if (value.length < 6) return 'Must be at least 6 characters';
    if (value == _oldPasswordCtrl.text && value.isNotEmpty) {
      return 'New password must differ from the current one';
    }
    return null;
  }

  String? _confirmPasswordValidator(String? value) {
    if (value == null || value.isEmpty) return 'Confirm your new password';
    if (value != _newPasswordCtrl.text) return 'Passwords do not match';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = AuthService.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 60),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickingAvatar ? null : _pickAvatar,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: _avatarPath != null
                        ? FileImage(File(_avatarPath!))
                        : null,
                    child: _avatarPath == null
                        ? Text(
                            (user?.name.isNotEmpty == true
                                    ? user!.name[0]
                                    : user?.email[0] ?? '?')
                                .toUpperCase(),
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 2,
                        ),
                      ),
                      child: _pickingAvatar
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Photo is stored on this device only',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 28),
          _sectionTitle('Profile', Icons.person_outline, theme),
          _card(
            theme,
            children: [
              Form(
                key: _nameFormKey,
                child: TextFormField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.done,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.badge_outlined),
                    counterText: '',
                  ),
                  validator: (v) => _requiredValidator(v, 'your name'),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: user?.email ?? '',
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _savingName ? null : _saveName,
                  child: _savingName
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save Name'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _sectionTitle('Change Password', Icons.lock_outline, theme),
          _card(
            theme,
            children: [
              Form(
                key: _passwordFormKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _oldPasswordCtrl,
                      obscureText: _obscureOld,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Current password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureOld
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _obscureOld = !_obscureOld),
                        ),
                      ),
                      validator: (v) =>
                          _requiredValidator(v, 'your current password'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _newPasswordCtrl,
                      obscureText: _obscureNew,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'New password',
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureNew
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _obscureNew = !_obscureNew),
                        ),
                      ),
                      validator: _newPasswordValidator,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmPasswordCtrl,
                      obscureText: _obscureConfirm,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _changePassword(),
                      decoration: InputDecoration(
                        labelText: 'Confirm new password',
                        prefixIcon: const Icon(Icons.check_circle_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                        ),
                      ),
                      validator: _confirmPasswordValidator,
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _savingPassword ? null : _changePassword,
                        child: _savingPassword
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Change Password'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, IconData icon, ThemeData theme) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.primary),
        const SizedBox(width: 7),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
            letterSpacing: 0.6,
          ),
        ),
      ],
    ),
  );

  Widget _card(ThemeData theme, {required List<Widget> children}) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: theme.dividerColor),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}
