import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

// Read-only AST audit. Keeps full adjacent strings and interpolation expressions
// together, with their enclosing method/constant, rather than regex fragments.
void main(List<String> args) {
  final root = Directory(args.isEmpty ? '../..' : args.first).absolute;
  final records = <Map<String, Object?>>[];
  for (final file in Directory(
    '${root.path}/lib',
  ).listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    final source = file.readAsStringSync();
    final parsed = parseString(content: source, path: file.path);
    final path = file.path
        .substring(root.path.length + 1)
        .replaceAll('\\', '/');
    parsed.unit.accept(_Strings(path, parsed.lineInfo.getLocation, records));
  }
  final output = File(
    '${root.path}/outputs/elevenlabs-voice-pack/source-audit.json',
  );
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(records)}\n',
  );
  stdout.writeln(
    'Audited ${records.length} Vietnamese string expressions: ${output.path}',
  );
}

class _Strings extends RecursiveAstVisitor<void> {
  _Strings(this.path, this.location, this.records);
  final String path;
  final dynamic Function(int) location;
  final List<Map<String, Object?>> records;

  void add(StringLiteral node) {
    if (node.parent is AdjacentStrings ||
        node.parent is InterpolationExpression)
      return;
    final text = node.stringValue;
    if (!RegExp(r'[À-ỹĐđ]').hasMatch(text ?? node.toSource())) return;
    var parent = node.parent;
    String? member;
    while (parent != null) {
      if (parent is MethodDeclaration) {
        member = parent.name.lexeme;
        break;
      }
      if (parent is FunctionDeclaration) {
        member = parent.name.lexeme;
        break;
      }
      if (parent is VariableDeclaration) {
        member = parent.name.lexeme;
        break;
      }
      parent = parent.parent;
    }
    records.add({
      'file': path,
      'line': location(node.offset).lineNumber,
      'member': member,
      'text': text,
      'expression': node.toSource(),
      'parent': node.parent.runtimeType.toString(),
      'parts': parts(node),
    });
  }

  List<Map<String, String>> parts(StringLiteral node) => switch (node) {
    SimpleStringLiteral() => [
      {'text': node.value},
    ],
    AdjacentStrings() => node.strings.expand(parts).toList(),
    StringInterpolation() =>
      node.elements
          .map(
            (element) => switch (element) {
              InterpolationString() => {'text': element.value},
              InterpolationExpression() => {
                'expression': element.expression.toSource(),
              },
            },
          )
          .toList(),
    _ => [],
  };

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => add(node);
  @override
  void visitAdjacentStrings(AdjacentStrings node) => add(node);
  @override
  void visitStringInterpolation(StringInterpolation node) => add(node);
}
