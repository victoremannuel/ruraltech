import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/colors.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';

/// Input padrão do RuralTech v2 com ícone e toggle de visibilidade.
class RTField extends StatefulWidget {
  const RTField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.leadingIcon,
    this.obscure = false,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.errorText,
    this.fieldKey,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final IconData? leadingIcon;
  final bool obscure;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final String? errorText;
  final Key? fieldKey;

  @override
  State<RTField> createState() => _RTFieldState();
}

class _RTFieldState extends State<RTField> {
  late bool _obscured = widget.obscure;

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: RTTypography.eyebrow.copyWith(color: RTColors.inkSoft),
          ),
          const SizedBox(height: RTSpacing.x2),
        ],
        TextField(
          key: widget.fieldKey,
          controller: widget.controller,
          enabled: widget.enabled,
          obscureText: _obscured,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          style: RTTypography.body,
          cursorColor: RTColors.primary,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: RTTypography.body.copyWith(color: RTColors.inkMute),
            prefixIcon: widget.leadingIcon != null
                ? Icon(widget.leadingIcon,
                    size: 20, color: RTColors.inkSoft)
                : null,
            suffixIcon: widget.obscure
                ? IconButton(
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: RTColors.inkSoft,
                    ),
                    onPressed: () =>
                        setState(() => _obscured = !_obscured),
                  )
                : null,
            filled: true,
            fillColor: widget.enabled ? RTColors.bgAlt : RTColors.bgSubtle,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: RTSpacing.x4,
              vertical: RTSpacing.x3,
            ),
            border: _border(RTColors.hair),
            enabledBorder: _border(hasError ? RTColors.danger : RTColors.hair),
            focusedBorder: _border(
              hasError ? RTColors.danger : RTColors.primary,
              width: 1.6,
            ),
            errorBorder: _border(RTColors.danger),
            focusedErrorBorder: _border(RTColors.danger, width: 1.6),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: RTSpacing.x1),
          Text(
            widget.errorText!,
            style: RTTypography.bodySmall.copyWith(color: RTColors.danger),
          ),
        ],
      ],
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(RTRadius.r3),
        borderSide: BorderSide(color: color, width: width),
      );
}
