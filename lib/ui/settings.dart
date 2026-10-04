import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'components.dart';

Future<String?> pickImage(
  BuildContext context, {
  bool crop = false,
  double ratio = 1,
}) async {
  final file = await FilePicker.pickFile(type: FileType.image);
  if (file == null) return null;
  if ((await file.length() ?? 0) > 8 * 1024 * 1024) {
    throw Exception('请选择小于 8 MB 的图片');
  }
  final bytes = await file.readAsBytes();
  if (!context.mounted) return null;
  if (crop) {
    return showPanel<String>(
      context,
      '裁剪图片',
      ImageCrop(bytes: bytes, ratio: ratio),
      width: 520,
    );
  }
  final output = await compute(resizeImage, bytes);
  return 'data:image/png;base64,${base64Encode(output)}';
}

img.Image decodePhoto(Uint8List bytes) {
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width <= 0 || info.height <= 0) {
    throw const FormatException('图片无法读取');
  }
  if (info.width * info.height > 20000000) {
    throw const FormatException('图片尺寸过大，请选择较小图片');
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) throw const FormatException('图片无法读取');
  return decoded;
}

Uint8List resizeImage(Uint8List bytes) {
  final decoded = decodePhoto(bytes);
  return Uint8List.fromList(img.encodePng(img.copyResize(decoded, width: 384)));
}

Uint8List cropImage(Map<String, dynamic> args) {
  final decoded = decodePhoto(args['bytes']);
  final image = img.bakeOrientation(decoded);
  final ratio = args['ratio'] as double, zoom = args['zoom'] as double;
  final w =
          (image.width < image.height * ratio
              ? image.width
              : image.height * ratio) /
          zoom,
      h = w / ratio;
  final cropped = img.copyCrop(
    image,
    x: ((image.width - w) * args['x']).round(),
    y: ((image.height - h) * args['y']).round(),
    width: w.round().clamp(1, image.width),
    height: h.round().clamp(1, image.height),
  );
  return Uint8List.fromList(
    img.encodeJpg(
      img.copyResize(
        cropped,
        width: cropped.width > 1400 ? 1400 : cropped.width,
      ),
      quality: 88,
    ),
  );
}

class ImageCrop extends StatefulWidget {
  final Uint8List bytes;
  final double ratio;
  const ImageCrop({super.key, required this.bytes, required this.ratio});
  @override
  State<ImageCrop> createState() => _ImageCropState();
}

class _ImageCropState extends State<ImageCrop> {
  double zoom = 1, x = .5, y = .5;
  bool busy = false;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: widget.ratio,
          child: ClipRect(
            child: Transform.scale(
              scale: zoom,
              alignment: Alignment(x * 2 - 1, y * 2 - 1),
              child: Image.memory(
                widget.bytes,
                cacheWidth: 1200,
                errorBuilder: (_, _, _) => const Center(child: Text('图片无法读取')),
                fit: BoxFit.cover,
                alignment: Alignment(x * 2 - 1, y * 2 - 1),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 20),
      SettingSlider(
        '缩放',
        zoom,
        (v) => setState(() => zoom = v),
        min: 1,
        max: 4,
        suffix: '${zoom.toStringAsFixed(1)}×',
      ),
      SettingSlider('水平', x, (v) => setState(() => x = v)),
      SettingSlider('垂直', y, (v) => setState(() => y = v)),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      final bytes = await compute(cropImage, {
                        'bytes': widget.bytes,
                        'ratio': widget.ratio,
                        'zoom': zoom,
                        'x': x,
                        'y': y,
                      });
                      if (context.mounted) {
                        Navigator.pop(
                          context,
                          'data:image/jpeg;base64,${base64Encode(bytes)}',
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text('图片无法读取')));
                      }
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: Text(busy ? '处理中' : '使用'),
          ),
        ],
      ),
    ],
  );
}
