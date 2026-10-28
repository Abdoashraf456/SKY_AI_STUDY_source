import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() => runApp(const SkyStudyApp());

const courses = <String>[
  'مبادئ المحاسبة المالية',
  'مبادئ الاقتصاد',
  'مبادئ الإدارة',
  'رياضيات تحليل الأعمال التجارية',
  'إدارة رياضية',
  'لغة إنجليزية للمبتدئين',
  'التفكير الابتكاري',
];

class SkyStudyApp extends StatelessWidget {
  const SkyStudyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF101A33);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SKY AI STUDY',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3976E8)),
        scaffoldBackgroundColor: const Color(0xFFF5F7FC),
        appBarTheme: const AppBarTheme(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class CourseData {
  String text = '';
  String fileName = '';
  List<QuizQuestion> questions = [];
}

class QuizQuestion {
  final String question;
  final List<String> options;
  final int answer;
  final String explanation;

  const QuizQuestion(this.question, this.options, this.answer, this.explanation);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Map<String, CourseData> data = {for (final c in courses) c: CourseData()};
  String selected = courses.first;
  bool busy = false;
  String status = 'ارفع محاضرة PDF علشان تبدأ المذاكرة';
  int tab = 0;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    for (final c in courses) {
      data[c]!
        ..text = prefs.getString('text_$c') ?? ''
        ..fileName = prefs.getString('name_$c') ?? '';
      data[c]!.questions = _makeQuestions(data[c]!.text);
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveSelected() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('text_$selected', data[selected]!.text);
    await prefs.setString('name_$selected', data[selected]!.fileName);
  }

  Future<void> _importPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (result == null || result.files.single.bytes == null) return;
      setState(() {
        busy = true;
        status = 'جاري قراءة الملف...';
      });
      final Uint8List bytes = result.files.single.bytes!;
      final document = sf.PdfDocument(inputBytes: bytes);
      final extracted = sf.PdfTextExtractor(document).extractText();
      document.dispose();

      data[selected]!
        ..text = extracted.trim()
        ..fileName = result.files.single.name
        ..questions = _makeQuestions(extracted);
      await _saveSelected();
      if (!mounted) return;
      setState(() {
        busy = false;
        status = extracted.trim().isEmpty
            ? 'الملف مفيهوش نص قابل للاستخراج. غالبًا PDF مصوّر ويحتاج OCR.'
            : 'تمت قراءة ${result.files.single.name} وحفظ المحتوى على الجهاز.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        status = 'حصل خطأ في قراءة الملف: $e';
      });
    }
  }

  List<String> _sentences(String text) {
    return text
        .replaceAll('\r', '\n')
        .split(RegExp(r'[\n.!?؟؛]+'))
        .map((s) => s.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((s) => s.length >= 28)
        .toList();
  }

  List<QuizQuestion> _makeQuestions(String text) {
    final sentences = _sentences(text);
    final result = <QuizQuestion>[];
    for (final s in sentences.take(30)) {
      final words = s.split(' ');
      if (words.length < 5) continue;
      final answer = s.length > 180 ? '${s.substring(0, 177)}...' : s;
      result.add(QuizQuestion(
        'Which statement is taken from the lecture?',
        [answer, 'None of the statements is related to the lecture.', 'The lecture contains no information.', 'All terms have the opposite meaning.'],
        0,
        'الإجابة الأولى مقتبسة من النص المستخرج من المحاضرة. ده اختبار مبدئي آلي، مش امتحان أكاديمي مُراجع.',
      ));
    }
    return result;
  }

  List<String> _keywords(String text) {
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF\s-]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 5)
        .toList();
    final counts = <String, int>{};
    for (final w in words) {
      if (!RegExp(r'^[a-z]').hasMatch(w)) continue;
      counts[w] = (counts[w] ?? 0) + 1;
    }
    final sorted = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return sorted.take(40).toList();
  }

  Future<void> _exportPdf({required bool examOnly}) async {
    final content = data[selected]!.text;
    if (content.trim().isEmpty) {
      _message('ارفع PDF للمادة الأول.');
      return;
    }
    try {
      setState(() => busy = true);
      final doc = pw.Document();
      final questions = data[selected]!.questions;
      final keywords = _keywords(content);
      final textParts = _sentences(content);
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text('SKY AI STUDY', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(selected, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(examOnly ? 'Practice quiz / اختبار تدريبي' : 'Study notes / ملخص مذاكرة'),
          pw.Divider(),
          if (!examOnly) ...[
            pw.Text('Important keywords / كلمات مفتاحية',
                style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
            pw.Wrap(spacing: 6, runSpacing: 5, children: keywords.map((k) => pw.Container(
              padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.red)),
              child: pw.Text(k, style: const pw.TextStyle(fontSize: 10, color: PdfColors.red)),
            )).toList()),
            pw.SizedBox(height: 12),
            pw.Text('Extracted lecture text / نص المحاضرة المستخرج',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ...textParts.take(120).map((s) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Text(s, style: const pw.TextStyle(fontSize: 10)),
            )),
          ],
          if (examOnly) ...[
            pw.Text('Questions / الأسئلة',
                style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
            ...questions.take(25).toList().asMap().entries.map((entry) {
              final i = entry.key;
              final q = entry.value;
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('${i + 1}. ${q.question}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
                  ...q.options.asMap().entries.map((o) => pw.Text('${String.fromCharCode(65 + o.key)}. ${o.value}')),
                  pw.Text('Answer: ${String.fromCharCode(65 + q.answer)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('شرح: ${q.explanation}'),
                ]),
              );
            }),
          ],
          pw.SizedBox(height: 10),
          pw.Text('تنبيه: النص والأسئلة مولّدة محليًا من النص المستخرج، وراجِعها قبل الاعتماد عليها في الامتحان.',
              style: const pw.TextStyle(fontSize: 9)),
        ],
      ));
      await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name: '${selected}_${examOnly ? "quiz" : "notes"}.pdf',
      );
      if (mounted) setState(() => busy = false);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        _message('تعذر إنشاء PDF: $e');
      }
    }
  }

  void _message(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final course = data[selected]!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SKY AI STUDY', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'معلومات',
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'SKY AI STUDY',
              applicationVersion: '1.0.0',
              children: const [Text('مساعد مذاكرة محلي لقراءة PDF وتكوين ملخصات واختبارات أولية.')],
            ),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(colors: [Color(0xFF17264A), Color(0xFF2C55A0)]),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ذاكر أذكى مع SKY', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.bold)),
                    SizedBox(height: 7),
                    Text('ارفع المحاضرة، استخرج الكلمات المهمة، وصدّر ملفات مذاكرة وامتحانات.', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text('اختار المادة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selected,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                items: courses.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => selected = v ?? courses.first),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.picture_as_pdf, color: Colors.red, size: 30),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(course.fileName.isEmpty ? 'مفيش ملف مرفوع' : course.fileName,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('${course.text.length} حرف • ${course.questions.length} سؤال مبدئي',
                            style: const TextStyle(color: Colors.black54, fontSize: 12)),
                      ])),
                    ]),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: FilledButton.icon(
                      onPressed: busy ? null : _importPdf,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('رفع وقراءة PDF'),
                    )),
                    const SizedBox(height: 8),
                    Text(status, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    if (busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.28,
                children: [
                  _ActionCard(icon: Icons.summarize, title: 'ملف المذاكرة', subtitle: 'النص والكلمات المهمة', color: Colors.blue, onTap: () => _exportPdf(examOnly: false)),
                  _ActionCard(icon: Icons.quiz, title: 'إنشاء امتحان', subtitle: 'أسئلة تدريبية مع الحل', color: Colors.red, onTap: () => _exportPdf(examOnly: true)),
                  _ActionCard(icon: Icons.translate, title: 'المصطلحات', subtitle: 'كلمات إنجليزية متكررة', color: Colors.deepPurple, onTap: () => _showKeywords()),
                  _ActionCard(icon: Icons.school, title: 'اختبر نفسك', subtitle: 'حل الأسئلة داخل التطبيق', color: Colors.teal, onTap: () => _openQuiz()),
                ],
              ),
              const SizedBox(height: 18),
              const Text('ملاحظات مهمة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 6),
              const Text('• التطبيق يعمل بدون API مدفوع.\n• استخراج النص لا يقرأ صفحات PDF المصوّرة؛ تحتاج OCR.\n• الأسئلة التلقائية الحالية تدريبية مبدئية وليست محاكاة مضمونة لامتحان جامعي حقيقي.\n• ملفات PDF العربية قد تحتاج تضمين خط عربي للحصول على عرض مثالي في كل الأجهزة.'),
            ],
          ),
        ),
      ),
    );
  }

  void _showKeywords() {
    final words = _keywords(data[selected]!.text);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * .65,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('الكلمات المتكررة — $selected', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Expanded(child: words.isEmpty
                    ? const Center(child: Text('ارفع محاضرة فيها نص إنجليزي الأول.'))
                    : ListView.builder(
                        itemCount: words.length,
                        itemBuilder: (_, i) => ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.red.shade50, child: Text('${i + 1}', style: const TextStyle(color: Colors.red))),
                          title: Text(words[i], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text('كلمة متكررة في الملف — راجع معناها في سياق المحاضرة'),
                        ),
                      )),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _openQuiz() {
    final questions = data[selected]!.questions;
    if (questions.isEmpty) {
      _message('ارفع PDF قابل لاستخراج النص الأول.');
      return;
    }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => QuizPage(course: selected, questions: questions.take(20).toList()),
    ));
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          CircleAvatar(backgroundColor: color.withValues(alpha: .12), child: Icon(icon, color: color)),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 11)),
        ]),
      ),
    ),
  );
}

class QuizPage extends StatefulWidget {
  final String course;
  final List<QuizQuestion> questions;
  const QuizPage({super.key, required this.course, required this.questions});
  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  int index = 0;
  int score = 0;
  int? selectedAnswer;
  bool answered = false;
  @override
  Widget build(BuildContext context) {
    final q = widget.questions[index];
    return Scaffold(
      appBar: AppBar(title: const Text('اختبر نفسك')),
      body: Directionality(
        textDirection: TextDirection.ltr,
        child: ListView(padding: const EdgeInsets.all(18), children: [
          Text(widget.course, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: (index + 1) / widget.questions.length),
          const SizedBox(height: 20),
          Text('Question ${index + 1} of ${widget.questions.length}', style: const TextStyle(color: Colors.blue)),
          const SizedBox(height: 12),
          Text(q.question, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          ...q.options.asMap().entries.map((entry) => Card(
            child: RadioListTile<int>(
              value: entry.key,
              groupValue: selectedAnswer,
              onChanged: answered ? null : (v) => setState(() => selectedAnswer = v),
              title: Text('${String.fromCharCode(65 + entry.key)}. ${entry.value}'),
            ),
          )),
          if (answered) ...[
            const SizedBox(height: 12),
            Text(selectedAnswer == q.answer ? 'Correct!' : 'Correct answer: ${String.fromCharCode(65 + q.answer)}',
              style: TextStyle(fontWeight: FontWeight.bold, color: selectedAnswer == q.answer ? Colors.green : Colors.red)),
            Directionality(textDirection: TextDirection.rtl, child: Text(q.explanation)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: !answered
                ? (selectedAnswer == null ? null : () => setState(() {
                      answered = true;
                      if (selectedAnswer == q.answer) score++;
                    }))
                : () {
                    if (index + 1 >= widget.questions.length) {
                      showDialog(context: context, builder: (_) => AlertDialog(
                        title: const Text('خلصت الامتحان'),
                        content: Text('درجتك: $score / ${widget.questions.length}'),
                        actions: [TextButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text('تمام'))],
                      ));
                    } else {
                      setState(() { index++; selectedAnswer = null; answered = false; });
                    }
                  },
            child: Text(!answered ? 'Check answer' : (index + 1 >= widget.questions.length ? 'Show result' : 'Next question')),
          ),
        ]),
      ),
    );
  }
}