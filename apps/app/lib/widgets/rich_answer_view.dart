import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

/// Renders a `right_answer.rich_answer.v1` chat answer.
///
/// Contract (see apps/api's `/api/ai/chat` with `richAnswer: true`):
///   - `content` is markdown text and is ALWAYS present/safe — it is the
///     baseline rendering path and must work even if nothing else does.
///   - `blocks`, when present, is a list of typed block objects the model
///     was asked to produce. The model doesn't always comply strictly, so
///     every block is rendered defensively: missing fields, malformed
///     shapes, and unknown `type` values all fall back to rendering
///     something (never a blank widget), and one bad block never takes
///     down the rest of the answer.
class RichAnswerView extends StatelessWidget {
  final String content;
  final List<Map<String, dynamic>>? blocks;
  final List<Map<String, dynamic>> sources;
  final bool isDark;

  /// Whether to render the source list inline beneath the blocks. The chat
  /// screen surfaces sources via a dedicated "Sources" sheet instead, so it
  /// leaves this off; other call sites (e.g. saved outputs) may want it on.
  final bool showSources;

  const RichAnswerView({
    super.key,
    required this.content,
    this.blocks,
    this.sources = const [],
    required this.isDark,
    this.showSources = false,
  });

  @override
  Widget build(BuildContext context) {
    // Legacy/defensive path: some earlier stored content may itself be a
    // JSON envelope (e.g. `{"blocks": [...], "renderMarkdown": "..."}`)
    // rather than plain markdown, if a block-only source ever emits that.
    // Only used when the caller didn't already pass structured blocks.
    final effectiveBlocks = blocks ?? _LegacyPayload.tryExtractBlocks(content);
    final effectiveContent = blocks != null
        ? content
        : (_LegacyPayload.tryExtractMarkdown(content) ?? content);

    final widgets = <Widget>[];
    if (effectiveContent.trim().isNotEmpty) {
      widgets.add(_MarkdownAnswer(content: effectiveContent, isDark: isDark));
    }

    for (final block in effectiveBlocks ?? const <Map<String, dynamic>>[]) {
      final widget = _buildBlock(context, block);
      if (widget != null) {
        widgets.add(const SizedBox(height: 12));
        widgets.add(widget);
      }
    }

    if (showSources && sources.isNotEmpty) {
      widgets.add(const SizedBox(height: 14));
      widgets.add(_SourceList(sources: sources, isDark: isDark));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets.isEmpty
          ? [_MarkdownAnswer(content: content, isDark: isDark)]
          : widgets,
    );
  }

  Widget? _buildBlock(BuildContext context, Map<String, dynamic> rawBlock) {
    // A single malformed block (bad types, thrown exceptions while reading
    // fields, etc.) must never crash the whole answer — fall back to a
    // plain-text stringification of the block instead of dropping it.
    try {
      final type = rawBlock['type']?.toString();
      switch (type) {
        case 'markdown':
          return _MarkdownAnswer(
            content: rawBlock['content']?.toString() ?? '',
            isDark: isDark,
          );
        case 'math':
          return _MathBlock(block: rawBlock, isDark: isDark);
        case 'table':
          return _TableBlock(block: rawBlock, isDark: isDark);
        case 'chart':
          return _ChartBlock(block: rawBlock, isDark: isDark);
        case 'geometry':
          return _GeometryBlock(block: rawBlock, isDark: isDark);
        case 'svg':
          return _SvgBlock(block: rawBlock, isDark: isDark);
        case 'image':
          return _ImageBlock(block: rawBlock, isDark: isDark);
        case 'code':
          return _CodeBlock(block: rawBlock, isDark: isDark);
        case 'quote':
          return _MarkdownAnswer(
            content: '> ${rawBlock['content'] ?? rawBlock['text'] ?? ''}',
            isDark: isDark,
          );
        case 'callout':
          return _CalloutBlock(block: rawBlock, isDark: isDark);
        case 'timeline':
          return _TimelineBlock(block: rawBlock, isDark: isDark);
        default:
          // Unknown block type — never silently drop it. Render whatever
          // text-ish content we can find, or a stringified fallback.
          return _UnknownBlock(block: rawBlock, isDark: isDark);
      }
    } catch (_) {
      return _UnknownBlock(block: rawBlock, isDark: isDark);
    }
  }
}

/// Best-effort extraction for the (rare/legacy) case where `content` itself
/// is a JSON rich-answer envelope rather than plain markdown.
class _LegacyPayload {
  static List<Map<String, dynamic>>? tryExtractBlocks(String raw) {
    final decoded = _tryDecode(raw);
    if (decoded == null) return null;
    return _maps(decoded['blocks']);
  }

  static String? tryExtractMarkdown(String raw) {
    final decoded = _tryDecode(raw);
    if (decoded == null) return null;
    final markdown =
        decoded['renderMarkdown']?.toString() ??
        decoded['content']?.toString();
    return markdown;
  }

  static Map<String, dynamic>? _tryDecode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed[0] != '{') return null;

    String candidate = trimmed;
    final fenced = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      multiLine: true,
    ).firstMatch(trimmed);
    if (fenced != null) {
      candidate = fenced.group(1) ?? trimmed;
    }

    try {
      final decoded = jsonDecode(candidate);
      if (decoded is! Map<String, dynamic>) return null;
      final schema = decoded['schema']?.toString();
      final hasRichShape =
          schema == 'right_answer.rich_answer.v1' ||
          decoded.containsKey('renderMarkdown') ||
          decoded.containsKey('blocks');
      if (!hasRichShape) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }
}

class _MarkdownAnswer extends StatelessWidget {
  final String content;
  final bool isDark;

  const _MarkdownAnswer({required this.content, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (content.trim().isEmpty) return const SizedBox.shrink();
    return DefaultTextStyle.merge(
      style: GoogleFonts.inter(
        fontSize: 15,
        height: 1.65,
        color: isDark ? const Color(0xFFFAF9F5) : const Color(0xFF141413),
      ),
      child: GptMarkdown(content),
    );
  }
}

class _MathBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  final bool isDark;

  const _MathBlock({required this.block, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final latex = block['latex']?.toString() ?? block['content']?.toString();
    if (latex == null || latex.trim().isEmpty) return const SizedBox.shrink();
    final display = block['display'] != false;
    final color = isDark ? const Color(0xFFFAF9F5) : const Color(0xFF141413);

    Widget math;
    try {
      math = Math.tex(
        latex,
        mathStyle: display ? MathStyle.display : MathStyle.text,
        textStyle: TextStyle(fontSize: display ? 17 : 15, color: color),
        onErrorFallback: (error) =>
            _MarkdownAnswer(content: r'$' '$latex' r'$', isDark: isDark),
      );
    } catch (_) {
      math = _MarkdownAnswer(content: r'$' '$latex' r'$', isDark: isDark);
    }

    if (!display) return math;
    return _BlockFrame(
      caption: block['caption']?.toString(),
      isDark: isDark,
      child: Center(child: math),
    );
  }
}

class _TableBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  final bool isDark;

  const _TableBlock({required this.block, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final columns = _strings(block['columns']);
    final rows = (block['rows'] is List ? block['rows'] as List : const [])
        .map((row) => _strings(row))
        .where((row) => row.isNotEmpty)
        .toList();
    if (columns.isEmpty || rows.isEmpty) return const SizedBox.shrink();

    return _BlockFrame(
      caption: block['caption']?.toString(),
      isDark: isDark,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black,
          ),
          dataTextStyle: GoogleFonts.inter(
            color: isDark ? Colors.white70 : Colors.black87,
          ),
          columns: columns.map((name) => DataColumn(label: Text(name))).toList(),
          rows: rows.map((row) {
            final cells = List<String>.generate(
              columns.length,
              (index) => index < row.length ? row[index] : '',
            );
            return DataRow(
              cells: cells.map((cell) => DataCell(Text(cell))).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ChartBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  final bool isDark;

  const _ChartBlock({required this.block, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final series = _series(block['series']);
    if (series.isEmpty) return const SizedBox.shrink();
    final chartType = block['chartType']?.toString().toLowerCase() ?? 'bar';
    final color = isDark ? const Color(0xFFE8A55A) : const Color(0xFFCC785C);
    final palette = [
      color,
      isDark ? const Color(0xFF7CA9C9) : const Color(0xFF5B8AA6),
      isDark ? const Color(0xFFB88FD4) : const Color(0xFF8E6BAE),
      isDark ? const Color(0xFF8FCB8C) : const Color(0xFF6BA968),
    ];

    Widget chart;
    switch (chartType) {
      case 'line':
        chart = LineChart(
          LineChartData(
            gridData: const FlGridData(show: true),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            lineBarsData: series.indexed.map((entry) {
              final values = entry.$2;
              return LineChartBarData(
                spots: values.indexed
                    .map((p) => FlSpot(p.$1.toDouble(), p.$2))
                    .toList(),
                color: palette[entry.$1 % palette.length],
                barWidth: 3,
                dotData: const FlDotData(show: true),
              );
            }).toList(),
          ),
        );
        break;
      case 'pie':
        final values = series.first;
        chart = PieChart(
          PieChartData(
            sections: values.indexed.map((entry) {
              return PieChartSectionData(
                value: entry.$2,
                color: palette[entry.$1 % palette.length],
                title: entry.$2.toStringAsFixed(entry.$2 % 1 == 0 ? 0 : 1),
                titleStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              );
            }).toList(),
          ),
        );
        break;
      case 'bar':
      default:
        chart = BarChart(
          BarChartData(
            gridData: const FlGridData(show: true),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            barGroups: series.first.indexed.map((entry) {
              return BarChartGroupData(
                x: entry.$1,
                barRods: [
                  BarChartRodData(toY: entry.$2, color: color),
                ],
              );
            }).toList(),
          ),
        );
    }

    return _BlockFrame(
      caption: block['caption']?.toString() ?? block['title']?.toString(),
      isDark: isDark,
      child: SizedBox(height: 220, child: chart),
    );
  }

  static List<List<double>> _series(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((item) {
      final values = item['values'];
      if (values is! List) return <double>[];
      return values
          .map((number) => number is num ? number.toDouble() : null)
          .whereType<double>()
          .toList();
    }).where((values) => values.isNotEmpty).toList();
  }
}

class _GeometryBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  final bool isDark;

  const _GeometryBlock({required this.block, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final geometryData = block['data'] is Map
        ? Map<String, dynamic>.from(block['data'] as Map)
        : block;

    final points = <String, Offset>{};
    for (final point in _maps(geometryData['points'])) {
      final id = point['id']?.toString();
      final x = point['x'];
      final y = point['y'];
      if (id != null && x is num && y is num) {
        points[id] = Offset(x.toDouble(), y.toDouble());
      }
    }

    final objects = _maps(geometryData['objects']);
    if (points.isEmpty || objects.isEmpty) return const SizedBox.shrink();

    return _BlockFrame(
      caption: block['caption']?.toString(),
      isDark: isDark,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: CustomPaint(
          painter: GeometryPainter(
            points: points,
            objects: objects,
            isDark: isDark,
          ),
        ),
      ),
    );
  }
}

/// Draws a geometry block's `points`/`objects` payload. Supports polygons,
/// line segments, circles/arcs, angle markings (with optional degree
/// labels), and side-length labels. Unknown `kind` values are skipped
/// individually rather than aborting the whole drawing.
class GeometryPainter extends CustomPainter {
  final Map<String, Offset> points;
  final List<Map<String, dynamic>> objects;
  final bool isDark;

  const GeometryPainter({
    required this.points,
    required this.objects,
    this.isDark = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final bounds = _bounds(points.values);
    final scale =
        math.min(
          size.width / math.max(bounds.width, 1),
          size.height / math.max(bounds.height, 1),
        ) *
        0.82;
    final offset = Offset(
      (size.width - bounds.width * scale) / 2 - bounds.left * scale,
      (size.height - bounds.height * scale) / 2 - bounds.top * scale,
    );

    Offset tx(Offset point) => Offset(
      point.dx * scale + offset.dx,
      point.dy * scale + offset.dy,
    );

    final linePaint = Paint()
      ..color = isDark ? const Color(0xFFEDE9DD) : const Color(0xFF1F2937)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final accentPaint = Paint()
      ..color = const Color(0xFFCC785C)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = const Color(0xFFCC785C).withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    for (final object in objects) {
      try {
        _paintObject(canvas, object, tx, linePaint, accentPaint, fillPaint);
      } catch (_) {
        // A single malformed geometry object should never break the rest
        // of the drawing.
      }
    }

    for (final entry in points.entries) {
      final p = tx(entry.value);
      canvas.drawCircle(p, 4, Paint()..color = const Color(0xFFCC785C));
      _drawText(canvas, entry.key, p + const Offset(7, -22));
    }
  }

  void _paintObject(
    Canvas canvas,
    Map<String, dynamic> object,
    Offset Function(Offset) tx,
    Paint linePaint,
    Paint accentPaint,
    Paint fillPaint,
  ) {
    final kind = object['kind']?.toString();
    switch (kind) {
      case 'polygon':
        final ids = _strings(object['points']);
        final path = Path();
        for (var i = 0; i < ids.length; i++) {
          final point = points[ids[i]];
          if (point == null) continue;
          if (i == 0) {
            path.moveTo(tx(point).dx, tx(point).dy);
          } else {
            path.lineTo(tx(point).dx, tx(point).dy);
          }
        }
        if (object['closed'] != false) path.close();
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, linePaint);
        break;

      case 'line':
      case 'sideLabel':
        final from = points[object['from']?.toString()];
        final to = points[object['to']?.toString()];
        if (from != null && to != null) {
          canvas.drawLine(tx(from), tx(to), linePaint);
          final label = object['label']?.toString();
          if (label != null) {
            _drawText(canvas, label, (tx(from) + tx(to)) / 2);
          }
        }
        break;

      case 'circle':
        final center = points[object['center']?.toString()];
        final radiusPoint = object['radiusPoint'] != null
            ? points[object['radiusPoint']?.toString()]
            : null;
        final radiusValue = object['radius'];
        double? radius;
        if (radiusPoint != null && center != null) {
          radius = (tx(radiusPoint) - tx(center)).distance;
        } else if (radiusValue is num) {
          // Radius given in model-space units; scale it the same way
          // points are scaled by comparing two transformed offsets.
          final a = tx(Offset.zero);
          final b = tx(Offset(radiusValue.toDouble(), 0));
          radius = (b - a).distance;
        }
        if (center != null && radius != null) {
          canvas.drawCircle(tx(center), radius, accentPaint);
          final label = object['label']?.toString();
          if (label != null) {
            _drawText(canvas, label, tx(center) + Offset(0, -radius - 14));
          }
        }
        break;

      case 'arc':
        final center = points[object['center']?.toString()];
        final radiusValue = object['radius'];
        final startAngle = object['startAngle'];
        final sweepAngle = object['sweepAngle'];
        if (center != null && radiusValue is num) {
          final a = tx(Offset.zero);
          final b = tx(Offset(radiusValue.toDouble(), 0));
          final radius = (b - a).distance;
          final start = startAngle is num
              ? startAngle.toDouble() * math.pi / 180
              : 0.0;
          final sweep = sweepAngle is num
              ? sweepAngle.toDouble() * math.pi / 180
              : math.pi;
          canvas.drawArc(
            Rect.fromCircle(center: tx(center), radius: radius),
            start,
            sweep,
            false,
            accentPaint,
          );
        }
        break;

      case 'angle':
      case 'rightAngle':
        final vertex = points[object['vertex']?.toString()];
        final from =
            points[object['from']?.toString() ?? object['point1']?.toString()];
        final to =
            points[object['to']?.toString() ?? object['point2']?.toString()];
        if (vertex != null && from != null && to != null) {
          final v = tx(vertex);
          final a1 = math.atan2(tx(from).dy - v.dy, tx(from).dx - v.dx);
          final a2 = math.atan2(tx(to).dy - v.dy, tx(to).dx - v.dx);
          var sweep = a2 - a1;
          while (sweep < -math.pi) {
            sweep += math.pi * 2;
          }
          while (sweep > math.pi) {
            sweep -= math.pi * 2;
          }
          canvas.drawArc(
            Rect.fromCircle(center: v, radius: 26),
            a1,
            sweep,
            false,
            accentPaint,
          );
          final label =
              object['label']?.toString() ??
              (kind == 'rightAngle'
                  ? null
                  : '${(sweep.abs() * 180 / math.pi).round()}°');
          if (label != null) {
            final mid = a1 + sweep / 2;
            _drawText(
              canvas,
              label,
              v + Offset(math.cos(mid), math.sin(mid)) * 42,
            );
          }
        }
        break;

      default:
        // Unknown geometry object kind — skip it, don't break the drawing.
        break;
    }
  }

  static Rect _bounds(Iterable<Offset> values) {
    var left = double.infinity;
    var right = double.negativeInfinity;
    var top = double.infinity;
    var bottom = double.negativeInfinity;
    for (final value in values) {
      left = math.min(left, value.dx);
      right = math.max(right, value.dx);
      top = math.min(top, value.dy);
      bottom = math.max(bottom, value.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom).inflate(24);
  }

  void _drawText(Canvas canvas, String text, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 120);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant GeometryPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.objects != objects ||
      oldDelegate.isDark != isDark;
}

class _SvgBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  final bool isDark;

  const _SvgBlock({required this.block, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final svg = block['svg']?.toString();
    if (svg == null || svg.trim().isEmpty) return const SizedBox.shrink();
    return _BlockFrame(
      caption: block['caption']?.toString(),
      isDark: isDark,
      child: Builder(
        builder: (context) {
          try {
            return SvgPicture.string(svg);
          } catch (_) {
            return _MarkdownAnswer(content: '```svg\n$svg\n```', isDark: isDark);
          }
        },
      ),
    );
  }
}

class _ImageBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  final bool isDark;

  const _ImageBlock({required this.block, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final url = block['url']?.toString() ?? block['imageUrl']?.toString();
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return _BlockFrame(
      caption: block['caption']?.toString() ?? block['alt']?.toString(),
      isDark: isDark,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(url, fit: BoxFit.contain),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  final bool isDark;

  const _CodeBlock({required this.block, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final code = block['content']?.toString() ?? block['code']?.toString() ?? '';
    if (code.trim().isEmpty) return const SizedBox.shrink();
    final language = block['language']?.toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1917) : const Color(0xFF1F1E1B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (language != null && language.isNotEmpty)
                Text(
                  language,
                  style: GoogleFonts.robotoMono(
                    fontSize: 11,
                    color: Colors.white54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const Spacer(),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Code copied'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: const Icon(
                  Icons.copy_rounded,
                  size: 15,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              code,
              style: GoogleFonts.robotoMono(
                fontSize: 12.5,
                height: 1.5,
                color: const Color(0xFFEDE9DD),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalloutBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  final bool isDark;

  const _CalloutBlock({required this.block, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final text = block['content']?.toString() ?? block['text']?.toString() ?? '';
    return _BlockFrame(
      caption: block['title']?.toString(),
      isDark: isDark,
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 14,
          height: 1.55,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      ),
    );
  }
}

class _TimelineBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  final bool isDark;

  const _TimelineBlock({required this.block, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final events = _maps(block['events']);
    if (events.isEmpty) return const SizedBox.shrink();
    return _BlockFrame(
      caption: block['caption']?.toString(),
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < events.length; i++)
            _TimelineRow(
              event: events[i],
              isLast: i == events.length - 1,
              isDark: isDark,
            ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final Map<String, dynamic> event;
  final bool isLast;
  final bool isDark;

  const _TimelineRow({
    required this.event,
    required this.isLast,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    const coral = Color(0xFFCC785C);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  color: coral,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: isDark
                        ? const Color(0xFF2E2C28)
                        : const Color(0xFFE6DFD8),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (event['year'] != null)
                    Text(
                      event['year'].toString(),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: coral,
                      ),
                    ),
                  Text(
                    event['title']?.toString() ?? '',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (event['description'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        event['description'].toString(),
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          height: 1.45,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
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

/// Fallback for any block `type` this renderer doesn't recognize. Never
/// drops content silently — renders text/content-ish fields as markdown,
/// or a stringified dump of the block as a last resort.
class _UnknownBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  final bool isDark;

  const _UnknownBlock({required this.block, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final text =
        block['content']?.toString() ??
        block['text']?.toString() ??
        block['markdown']?.toString();
    if (text != null && text.trim().isNotEmpty) {
      return _MarkdownAnswer(content: text, isDark: isDark);
    }
    String dump;
    try {
      dump = const JsonEncoder.withIndent('  ').convert(block);
    } catch (_) {
      dump = block.toString();
    }
    return _MarkdownAnswer(content: '```\n$dump\n```', isDark: isDark);
  }
}

class _SourceList extends StatelessWidget {
  final List<Map<String, dynamic>> sources;
  final bool isDark;

  const _SourceList({required this.sources, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _BlockFrame(
      caption: 'Sources',
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sources.take(5).map((source) {
          final page = source['pageNumber'] == null
              ? ''
              : ' p. ${source['pageNumber']}';
          final label =
              [
                source['subjectName']?.toString(),
                source['chapterName']?.toString(),
              ].where((v) => v != null && v.isNotEmpty).join(' · ');
          final text = source['text']?.toString() ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${label.isEmpty ? 'Source' : label}$page${text.isEmpty ? '' : ': $text'}',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.45,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BlockFrame extends StatelessWidget {
  final String? caption;
  final bool isDark;
  final Widget child;

  const _BlockFrame({
    required this.caption,
    required this.isDark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1E1B) : const Color(0xFFFFFCF6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (caption != null && caption!.trim().isNotEmpty) ...[
            Text(
              caption!,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}

List<String> _strings(dynamic value) {
  if (value is! List) return const [];
  return value.map((item) => item?.toString() ?? '').toList();
}

List<Map<String, dynamic>> _maps(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((item) {
    return item.map((key, value) => MapEntry(key.toString(), value));
  }).toList();
}
