import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ---- Баптаулар (қажет болса осы жерден өзгертіңіз) ----
const int kOpenHour = 10; // жұмыс басталуы
const int kCloseHour = 21; // жұмыс аяқталуы
const int kSlotMinutes = 30; // бір слот ұзақтығы

const Color kBg = Color(0xFF0B0B0C);
const Color kCard = Color(0xFF161618);
const Color kBorder = Color(0xFF26262A);
const Color kMuted = Color(0xFF8A8A90);
const Color kGold = Color(0xFFD4B16A);

const monthsKk = [
  'қаңтар',
  'ақпан',
  'наурыз',
  'сәуір',
  'мамыр',
  'маусым',
  'шілде',
  'тамыз',
  'қыркүйек',
  'қазан',
  'қараша',
  'желтоқсан'
];
const weekdaysKk = [
  'дүйсенбі',
  'сейсенбі',
  'сәрсенбі',
  'бейсенбі',
  'жұма',
  'сенбі',
  'жексенбі'
];
const weekdaysShortKk = ['Дс', 'Сс', 'Ср', 'Бс', 'Жм', 'Сн', 'Жк'];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
String two(int n) => n.toString().padLeft(2, '0');
String fmtTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
String fmtDate(DateTime d) =>
    '${d.day} ${monthsKk[d.month - 1]}, ${weekdaysKk[d.weekday - 1]}';

String normalizePhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11 && digits.startsWith('8')) {
    digits = '7${digits.substring(1)}';
  } else if (digits.length == 10) {
    digits = '7$digits';
  }
  return digits;
}

Future<void> openWhatsApp(Booking b) async {
  final num = normalizePhone(b.phone);
  final msg =
      'Сәлем, ${b.name}! Сізді ${fmtDate(b.start)}, ${fmtTime(b.start)} уақытында күтеміз.';
  final uri = Uri.parse('https://wa.me/$num?text=${Uri.encodeComponent(msg)}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> callPhone(String phone) async {
  final num = normalizePhone(phone);
  await launchUrl(Uri.parse('tel:+$num'));
}

// ---- Модельдер ----
class Service {
  String name;
  int price;
  Service(this.name, this.price);
  Map<String, dynamic> toJson() => {'name': name, 'price': price};
  factory Service.fromJson(Map<String, dynamic> j) =>
      Service(j['name'] as String, (j['price'] as num?)?.toInt() ?? 0);
}

class Booking {
  final String id;
  String name;
  String phone;
  String service;
  String note;
  DateTime start;
  int minutes;
  bool done;

  Booking({
    required this.id,
    required this.name,
    required this.phone,
    required this.service,
    required this.start,
    this.note = '',
    this.minutes = kSlotMinutes,
    this.done = false,
  });

  DateTime get end => start.add(Duration(minutes: minutes));

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'service': service,
        'note': note,
        'start': start.toIso8601String(),
        'minutes': minutes,
        'done': done,
      };

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: (j['phone'] as String?) ?? '',
        service: (j['service'] as String?) ?? '',
        note: (j['note'] as String?) ?? '',
        start: DateTime.parse(j['start'] as String),
        minutes: (j['minutes'] as num?)?.toInt() ?? kSlotMinutes,
        done: (j['done'] as bool?) ?? false,
      );
}

// ---- Сақтау (тек телефон жадында) ----
class Store extends ChangeNotifier {
  late SharedPreferences _p;
  List<Booking> bookings = [];
  List<Service> services = [];

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    try {
      final raw = _p.getString('bookings');
      if (raw != null) {
        bookings = (jsonDecode(raw) as List)
            .map((e) => Booking.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {
      bookings = [];
    }
    try {
      final raw = _p.getString('services');
      if (raw != null) {
        services = (jsonDecode(raw) as List)
            .map((e) => Service.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {
      services = [];
    }
    if (services.isEmpty) {
      services = [
        Service('Стрижка', 3000),
        Service('Сақал', 2000),
        Service('Стрижка + сақал', 4500),
        Service('Бала стрижкасы', 2500),
      ];
      await _saveServices();
    }
  }

  Future<void> _saveBookings() => _p.setString(
      'bookings', jsonEncode(bookings.map((e) => e.toJson()).toList()));
  Future<void> _saveServices() => _p.setString(
      'services', jsonEncode(services.map((e) => e.toJson()).toList()));

  List<Booking> forDay(DateTime d) {
    final list = bookings.where((b) => sameDay(b.start, d)).toList();
    list.sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  bool conflicts(DateTime start, int minutes, {String? exceptId}) {
    final end = start.add(Duration(minutes: minutes));
    for (final b in bookings) {
      if (b.id == exceptId) continue;
      if (start.isBefore(b.end) && end.isAfter(b.start)) return true;
    }
    return false;
  }

  void addBooking(Booking b) {
    bookings.add(b);
    _saveBookings();
    notifyListeners();
  }

  void updateBooking(Booking b) {
    _saveBookings();
    notifyListeners();
  }

  void removeBooking(Booking b) {
    bookings.removeWhere((e) => e.id == b.id);
    _saveBookings();
    notifyListeners();
  }

  void addService(Service s) {
    services.add(s);
    _saveServices();
    notifyListeners();
  }

  void removeService(Service s) {
    services.remove(s);
    _saveServices();
    notifyListeners();
  }
}

// ---- Қосымша ----
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  await store.load();
  runApp(BarberApp(store: store));
}

class BarberApp extends StatelessWidget {
  final Store store;
  const BarberApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: kGold,
      brightness: Brightness.dark,
    ).copyWith(
      primary: kGold,
      onPrimary: const Color(0xFF1A1405),
      surface: kBg,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Барбер',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: kBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: kBg,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kGold),
          ),
        ),
      ),
      home: HomePage(store: store),
    );
  }
}

// ---- Күн таңдау жолағы ----
class DayStrip extends StatelessWidget {
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final int count;
  final int Function(DateTime)? badge;

  const DayStrip({
    super.key,
    required this.selected,
    required this.onSelect,
    this.count = 30,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final d = DateTime(today.year, today.month, today.day + i);
          final isSel = sameDay(d, selected);
          final n = badge?.call(d) ?? 0;
          return GestureDetector(
            onTap: () => onSelect(d),
            child: Container(
              width: 58,
              decoration: BoxDecoration(
                color: isSel ? kGold : kCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isSel ? kGold : kBorder),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    weekdaysShortKk[d.weekday - 1],
                    style: TextStyle(
                      fontSize: 12,
                      color: isSel ? const Color(0xFF1A1405) : kMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${d.day}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: isSel ? const Color(0xFF1A1405) : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: n > 0
                          ? (isSel ? const Color(0xFF1A1405) : kGold)
                          : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---- Басты бет ----
class HomePage extends StatefulWidget {
  final Store store;
  const HomePage({super.key, required this.store});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DateTime _selected = dateOnly(DateTime.now());

  void _openEditor({Booking? booking}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BookingEditor(
        store: widget.store,
        booking: booking,
        initialDate: _selected,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final list = widget.store.forDay(_selected);
        final active = list.where((b) => !b.done).length;
        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Барбер',
              style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1),
            ),
            actions: [
              IconButton(
                tooltip: 'Қызметтер',
                icon: const Icon(Icons.content_cut_rounded),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ServicesPage(store: widget.store),
                )),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: kGold,
            foregroundColor: const Color(0xFF1A1405),
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Жазу'),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sameDay(_selected, DateTime.now())
                          ? 'Бүгін'
                          : fmtDate(_selected),
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${fmtDate(_selected)} · $active клиент',
                      style: const TextStyle(color: kMuted),
                    ),
                  ],
                ),
              ),
              DayStrip(
                selected: _selected,
                onSelect: (d) => setState(() => _selected = d),
                badge: (d) => widget.store.forDay(d).length,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: list.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_available_rounded,
                                size: 48, color: kMuted),
                            SizedBox(height: 12),
                            Text('Бұл күні жазылу жоқ',
                                style: TextStyle(color: kMuted)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => BookingCard(
                          booking: list[i],
                          store: widget.store,
                          onTap: () => _openEditor(booking: list[i]),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class BookingCard extends StatelessWidget {
  final Booking booking;
  final Store store;
  final VoidCallback onTap;

  const BookingCard({
    super.key,
    required this.booking,
    required this.store,
    required this.onTap,
  });

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Жазылуды жою?'),
        content: Text('${booking.name} · ${fmtTime(booking.start)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Жоқ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Жою'),
          ),
        ],
      ),
    );
    if (ok == true) store.removeBooking(booking);
  }

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final hasPhone = normalizePhone(b.phone).length >= 10;
    return Opacity(
      opacity: b.done ? 0.5 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kBorder),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fmtTime(b.start),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: kGold,
                    ),
                  ),
                  Text(
                    'дейін ${fmtTime(b.end)}',
                    style: const TextStyle(fontSize: 12, color: kMuted),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        decoration:
                            b.done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      b.service.isEmpty ? '—' : b.service,
                      style: const TextStyle(color: kMuted),
                    ),
                    if (b.phone.isNotEmpty)
                      Text(
                        b.phone,
                        style: const TextStyle(color: kMuted, fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (hasPhone)
                IconButton(
                  tooltip: 'WhatsApp',
                  icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
                  onPressed: () => openWhatsApp(b),
                ),
              if (hasPhone)
                IconButton(
                  tooltip: 'Қоңырау',
                  icon: const Icon(Icons.call_rounded, color: kGold),
                  onPressed: () => callPhone(b.phone),
                ),
              PopupMenuButton<String>(
                color: kCard,
                onSelected: (v) {
                  if (v == 'done') {
                    b.done = !b.done;
                    store.updateBooking(b);
                  } else if (v == 'edit') {
                    onTap();
                  } else if (v == 'delete') {
                    _confirmDelete(context);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'done',
                    child: Text(b.done ? 'Қайтару' : 'Орындалды'),
                  ),
                  const PopupMenuItem(value: 'edit', child: Text('Өзгерту')),
                  const PopupMenuItem(value: 'delete', child: Text('Жою')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Жазылу қосу / өзгерту ----
class BookingEditor extends StatefulWidget {
  final Store store;
  final Booking? booking;
  final DateTime initialDate;

  const BookingEditor({
    super.key,
    required this.store,
    this.booking,
    required this.initialDate,
  });

  @override
  State<BookingEditor> createState() => _BookingEditorState();
}

class _BookingEditorState extends State<BookingEditor> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _note;
  String? _service;
  late DateTime _date;
  DateTime? _slot;
  int _minutes = kSlotMinutes;

  @override
  void initState() {
    super.initState();
    final b = widget.booking;
    _name = TextEditingController(text: b?.name ?? '');
    _phone = TextEditingController(text: b?.phone ?? '');
    _note = TextEditingController(text: b?.note ?? '');
    _service = b?.service;
    if (_service == null && widget.store.services.isNotEmpty) {
      _service = widget.store.services.first.name;
    }
    _date = dateOnly(b?.start ?? widget.initialDate);
    _slot = b?.start;
    _minutes = b?.minutes ?? kSlotMinutes;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  List<DateTime> _slots() {
    final list = <DateTime>[];
    for (var m = kOpenHour * 60; m + kSlotMinutes <= kCloseHour * 60; m += kSlotMinutes) {
      list.add(DateTime(_date.year, _date.month, _date.day, m ~/ 60, m % 60));
    }
    return list;
  }

  bool _free(DateTime s) {
    final end = s.add(Duration(minutes: _minutes));
    final close = DateTime(s.year, s.month, s.day, kCloseHour);
    if (end.isAfter(close)) return false;
    final orig = widget.booking;
    if (s.isBefore(DateTime.now()) && !(orig != null && orig.start == s)) {
      return false;
    }
    return !widget.store.conflicts(s, _minutes, exceptId: orig?.id);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _save() {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty) {
      _toast('Клиенттің атын жазыңыз');
      return;
    }
    if (phone.isNotEmpty && normalizePhone(phone).length < 10) {
      _toast('Телефон нөмірі толық емес');
      return;
    }
    if (_service == null) {
      _toast('Алдымен қызмет қосыңыз');
      return;
    }
    if (_slot == null) {
      _toast('Уақытты таңдаңыз');
      return;
    }
    final b = widget.booking;
    if (b == null) {
      widget.store.addBooking(Booking(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        phone: phone,
        service: _service!,
        note: _note.text.trim(),
        start: _slot!,
        minutes: _minutes,
      ));
    } else {
      b.name = name;
      b.phone = phone;
      b.service = _service!;
      b.note = _note.text.trim();
      b.start = _slot!;
      b.minutes = _minutes;
      widget.store.updateBooking(b);
    }
    Navigator.of(context).pop();
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
        child: Text(
          text,
          style: const TextStyle(color: kMuted, fontWeight: FontWeight.w600),
        ),
      );

  Widget _chip(String label, bool selected, VoidCallback? onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: onTap == null ? null : (_) => onTap(),
      backgroundColor: kCard,
      selectedColor: kGold,
      side: const BorderSide(color: kBorder),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF1A1405) : Colors.white,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.store.services;
    final slots = _slots();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.booking == null ? 'Жаңа жазылу' : 'Өзгерту'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kGold,
              foregroundColor: const Color(0xFF1A1405),
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _save,
            child: const Text(
              'Сақтау',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _label('Клиент'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Аты'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: 'Телефон (мыс: 8 701 123 45 67)',
              prefixIcon: Icon(Icons.phone_rounded),
            ),
          ),
          _label('Қызмет'),
          if (services.isEmpty)
            const Text('Қызмет жоқ. Басты беттегі қайшы белгісінен қосыңыз.',
                style: TextStyle(color: kMuted))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in services)
                  _chip(
                    s.price > 0 ? '${s.name} · ${s.price} ₸' : s.name,
                    _service == s.name,
                    () => setState(() => _service = s.name),
                  ),
              ],
            ),
          _label('Ұзақтығы'),
          Wrap(
            spacing: 8,
            children: [
              for (final m in [30, 60, 90])
                _chip(
                  m == 30 ? '30 мин' : (m == 60 ? '1 сағ' : '1,5 сағ'),
                  _minutes == m,
                  () => setState(() {
                    _minutes = m;
                    if (_slot != null && !_free(_slot!)) _slot = null;
                  }),
                ),
            ],
          ),
          _label('Күні'),
          SizedBox(
            height: 84,
            child: OverflowBox(
              maxWidth: MediaQuery.of(context).size.width,
              child: Transform.translate(
                offset: Offset.zero,
                child: DayStrip(
                  selected: _date,
                  count: 60,
                  onSelect: (d) => setState(() {
                    _date = d;
                    _slot = null;
                  }),
                ),
              ),
            ),
          ),
          _label('Уақыты'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in slots)
                _chip(
                  fmtTime(s),
                  _slot == s,
                  _free(s) ? () => setState(() => _slot = s) : null,
                ),
            ],
          ),
          _label('Ескертпе'),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'Қосымша (міндетті емес)'),
          ),
        ],
      ),
    );
  }
}

// ---- Қызметтер ----
class ServicesPage extends StatelessWidget {
  final Store store;
  const ServicesPage({super.key, required this.store});

  Future<void> _add(BuildContext context) async {
    final name = TextEditingController();
    final price = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Жаңа қызмет'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(hintText: 'Атауы'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Бағасы, ₸'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Бас тарту'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Қосу'),
          ),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      store.addService(
          Service(name.text.trim(), int.tryParse(price.text.trim()) ?? 0));
    }
    name.dispose();
    price.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Қызметтер')),
        floatingActionButton: FloatingActionButton(
          backgroundColor: kGold,
          foregroundColor: const Color(0xFF1A1405),
          onPressed: () => _add(context),
          child: const Icon(Icons.add_rounded),
        ),
        body: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: store.services.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final s = store.services[i];
            return Container(
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder),
              ),
              child: ListTile(
                title: Text(s.name),
                subtitle: Text(s.price > 0 ? '${s.price} ₸' : 'Бағасы жоқ',
                    style: const TextStyle(color: kMuted)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => store.removeService(s),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
