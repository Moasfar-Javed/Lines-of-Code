import 'dart:io';
import 'package:dart_console/dart_console.dart';
import 'package:args/args.dart';

const String version = '0.0.1';

ArgParser buildParser() {
  return ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show additional command output.',
    )
    ..addFlag(
      'version',
      negatable: false,
      help: 'Print the tool version.',
    )
    ..addOption(
      'extensions',
      abbr: 'e',
      help: 'Comma-separated list of file extensions to analyze, e.g. dart,mjs',
    )
    ..addOption(
      'directory',
      abbr: 'd',
      help: 'Directory to analyze (defaults to the current directory).',
    );
}

void printUsage(ArgParser argParser, Console console) {
  console.setForegroundColor(ConsoleColor.cyan);
  console.writeLine('Usage: loc [flags] <directory> <extensions>');
  console.writeLine(argParser.usage);
  console.resetColorAttributes();
}

void main(List<String> arguments) async {
  final ArgParser argParser = buildParser();
  final console = Console();

  try {
    final ArgResults results = argParser.parse(arguments);
    bool verbose = results.wasParsed('verbose');

    if (results.wasParsed('help')) {
      printUsage(argParser, console);
      return;
    }

    if (results.wasParsed('version')) {
      console.setForegroundColor(ConsoleColor.green);
      console.writeLine('loc version: $version');
      console.resetColorAttributes();
      return;
    }

    // Determine the directory path (defaults to current directory if not passed)
    final directoryPath = results['directory'] ?? Directory.current.path;

    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      console.setForegroundColor(ConsoleColor.red);
      console.writeLine('Error: Directory "$directoryPath" does not exist.');
      console.resetColorAttributes();
      return;
    }

    if (verbose) {
      console.setForegroundColor(ConsoleColor.green);
      console.writeLine('Working directory: ${directory.path}');
      console.resetColorAttributes();
    }

    // Parse extensions
    List<String> extensions = [];
    if (results['extensions'] != null) {
      extensions = (results['extensions'] as String)
          .replaceAll("=", "")
          .split(',')
          .map((ext) => ext.trim().toLowerCase().replaceAll(".", ""))
          .toList();
      if (verbose) {
        console.setForegroundColor(ConsoleColor.cyan);
        console.writeLine(
            'Looking for files with extenstions: ${extensions.isEmpty ? "*" : extensions}');
        console.resetColorAttributes();
      }
    }

    final stats = await _countLines(directory, extensions, verbose, console);

    // Display Results
    console.setForegroundColor(ConsoleColor.yellow);
    console.writeLine('\nResults:');
    console.resetColorAttributes();
    _displayTable(console, stats['details']);

    console.setForegroundColor(ConsoleColor.magenta);
    console.writeLine('\nSummary:');
    console
        .writeLine('Total Files Visited: ${stats['summary']['filesChecked']}');
    console.writeLine('Total LOC: ${stats['summary']['loc']}');
    console.writeLine('Total Comments: ${stats['summary']['comments']}');
    console.writeLine('Total Blanks: ${stats['summary']['blanks']}');
    console.resetColorAttributes();
  } on FormatException catch (e) {
    console.setForegroundColor(ConsoleColor.red);
    console.writeLine('Error: ${e.message}');
    console.resetColorAttributes();
    print('');
    printUsage(argParser, console);
  }
}

Future<Map<String, dynamic>> _countLines(Directory directory,
    List<String> extensions, bool verbose, Console console) async {
  int totalLOC = 0;
  int totalComments = 0;
  int totalBlanks = 0;

  final details = <Map<String, dynamic>>[];
  int totalFilesChecked = 0;
  await for (var entity
      in directory.list(recursive: true, followLinks: false)) {
    if (entity is File &&
        (extensions.isEmpty ||
            extensions.contains(entity.path.split('.').last.toLowerCase()))) {
      try {
        final fileStats = await _analyzeFile(entity);
        details.add({
          'path': entity.path,
          'loc': fileStats['loc'],
          'comments': fileStats['comments'],
          'blanks': fileStats['blanks'],
        });
        totalLOC += fileStats['loc']!;
        totalComments += fileStats['comments']!;
        totalBlanks += fileStats['blanks']!;
        totalFilesChecked++;
        if (verbose) {
          console.write(
              '✅ Checked file [$totalFilesChecked] -> ${entity.path.replaceFirst(directory.path, "...")}\n');
        }
      } catch (e) {
        print('Error reading file ${entity.path}: $e');
      }
    }
  }

  return {
    'summary': {
      'filesChecked': totalFilesChecked,
      'loc': totalLOC,
      'comments': totalComments,
      'blanks': totalBlanks
    },
    'details': details,
  };
}

Future<Map<String, int>> _analyzeFile(File file) async {
  int loc = 0;
  int comments = 0;
  int blanks = 0;

  final lines = await file.readAsLines();
  for (var line in lines) {
    final trimmedLine = line.trim();
    if (trimmedLine.isEmpty) {
      blanks++;
    } else if (trimmedLine.startsWith('//') ||
        trimmedLine.startsWith('/*') ||
        trimmedLine.startsWith('*')) {
      comments++;
    } else {
      loc++;
    }
  }

  return {'loc': loc, 'comments': comments, 'blanks': blanks};
}

void _displayTable(Console console, List<Map<String, dynamic>> details) {
  const headerRow = [' File Path', ' LOC', ' Comments', ' Blanks'];
  const columnWidths = [40, 10, 10, 10];
  final maxPathLength = 40; // Maximum width for file path

  final separator = '+${columnWidths.map((width) => '-' * width).join('+')}+';

  // Print header
  console.writeLine(separator);
  console.write('|');
  for (var i = 0; i < headerRow.length; i++) {
    console.write(headerRow[i].padRight(columnWidths[i]));
    console.write('|');
  }
  console.writeLine('');
  console.writeLine(separator);

  // Print rows
  for (var detail in details) {
    String path = detail['path'];

    // Truncate the file path if it exceeds the max length
    if (path.length > maxPathLength - 5) {
      path =
          '...${path.substring(path.length - maxPathLength + 5)}'; // Keep the last part, prepend "..."
    }

    // Print each column with the correct padding and truncation
    console.write('|');
    console.write(path.padRight(columnWidths[0]));
    console.write('| ');
    console.write(detail['loc'].toString().padRight(columnWidths[1] - 1));
    console.write('| ');
    console.write(detail['comments'].toString().padRight(columnWidths[2] - 1));
    console.write('| ');
    console.write(detail['blanks'].toString().padRight(columnWidths[3] - 1));
    console.write('|\n');
  }

  console.writeLine(separator);
}
