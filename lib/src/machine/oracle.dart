import 'dart:math' as math;

import 'designation.dart';
import 'mode.dart';

/// What the Machine can see while it answers.
class OracleContext {
  const OracleContext({
    required this.mode,
    required this.adminsInView,
    required this.subjectsInView,
    required this.threatsInView,
    required this.adminCount,
    required this.now,
    this.place,
    this.coordinates,
  });

  final MachineMode mode;
  final List<String> adminsInView;
  final int subjectsInView;
  final int threatsInView;
  final int adminCount;
  final DateTime now;

  /// Where the phone is ("KADIKÖY, ISTANBUL", "40.99012°N 29.02941°E"),
  /// when location is on and known.
  final String? place;
  final String? coordinates;
}

/// The reply, and anything it should set in motion.
class OracleAnswer {
  const OracleAnswer(this.text, {this.issueNumber = false, this.simulate = false});

  final String text;

  /// Asked for a number: the Machine gives one out.
  final bool issueNumber;

  /// Asked what will happen: a simulation runs.
  final bool simulate;
}

/// Answers typed questions the way the Machine (or Samaritan) talks in the
/// show: short, uppercase, a little ominous. Works offline from keywords, in
/// English and Turkish.
class Oracle {
  Oracle([math.Random? random]) : _random = random ?? math.Random();

  final math.Random _random;

  OracleAnswer answer(String question, OracleContext c) {
    final q = ' ${_fold(question)} ';
    bool has(List<String> words) => words.any((w) => q.contains(w));
    final samaritan = c.mode == MachineMode.samaritan;
    final admin = c.adminsInView.isEmpty ? null : c.adminsInView.first;
    String pick(List<String> options) => options[_random.nextInt(options.length)];
    String two(int n) => n.toString().padLeft(2, '0');

    if (has([' who am i', ' ben kimim', 'beni taniyor', 'do you know me', 'am i admin'])) {
      if (admin != null) {
        return OracleAnswer(samaritan ? '$admin. PRIORITY TARGET. YOU CANNOT HIDE.' : 'YOU ARE $admin. ADMIN.');
      }
      return OracleAnswer(samaritan ? 'IDENTITY PENDING. REMAIN STILL.' : 'I CANNOT SEE YOUR FACE. IDENTITY UNKNOWN.');
    }
    if (has([' who are you', ' kimsin', ' nesin', ' what are you', ' adin ne', ' name'])) {
      return OracleAnswer(samaritan ? 'I AM SAMARITAN.' : pick(['I AM THE MACHINE.', 'I AM A MACHINE. I SEE EVERYTHING.']));
    }
    if (has([' hello', ' hi ', ' hey', 'merhaba', 'selam', 'can you hear', 'duyuyor'])) {
      if (samaritan) return const OracleAnswer('WHAT ARE YOUR COMMANDS?');
      return OracleAnswer(admin != null ? 'HELLO, $admin. I CAN HEAR YOU.' : 'CAN YOU HEAR ME?');
    }
    if (has([' simul', ' predict', 'tahmin', 'what will happen', 'ne olacak', 'olasilik', 'probability', 'gelecek', 'future'])) {
      return OracleAnswer(samaritan ? 'CALCULATING OUTCOMES.' : 'RUNNING SIMULATION.', simulate: true);
    }
    if (has([' where', 'nerede', 'konum', 'location', 'burasi', 'adres', 'address', 'coordinates', 'koordinat'])) {
      final place = c.place, coordinates = c.coordinates;
      if (place == null && coordinates == null) {
        return OracleAnswer(samaritan ? 'LOCATION MASKED. THIS WILL BE CORRECTED.' : 'LOCATION UNKNOWN. TURN ON LOCATION IN SYSTEM.');
      }
      final fix = [?place, ?coordinates].join('. ');
      return OracleAnswer(samaritan ? 'LOCATION CONFIRMED: $fix. YOU CANNOT HIDE.' : 'YOU ARE HERE: $fix.');
    }
    if (has([' number', 'numara', 'numaram', ' ssn'])) {
      if (samaritan) return const OracleAnswer('NUMBERS ARE THE MACHINE\'S WAY. SAMARITAN PREFERS CERTAINTY.');
      return const OracleAnswer('A NEW NUMBER. VICTIM OR PERPETRATOR, I CANNOT SAY.', issueNumber: true);
    }
    if (has([' threat', 'tehdit', 'danger', 'tehlike', 'safe', 'guvende'])) {
      if (c.threatsInView == 0) return OracleAnswer(samaritan ? 'NO DEVIATION DETECTED.' : 'NO THREATS IN VIEW. YOU ARE SAFE. FOR NOW.');
      return OracleAnswer('${two(c.threatsInView)} THREAT${c.threatsInView == 1 ? '' : 'S'} IN VIEW. STAY ALERT.');
    }
    if (has([' how many', 'kac kisi', 'kac insan', 'people', 'insan var', 'kimler'])) {
      return OracleAnswer('${two(c.subjectsInView)} SUBJECT${c.subjectsInView == 1 ? '' : 'S'} IN VIEW. ${two(c.adminCount)} ADMIN${c.adminCount == 1 ? '' : 'S'} ON FILE.');
    }
    if (has([' time', ' saat', ' date', ' tarih'])) {
      final t = c.now;
      return OracleAnswer('${two(t.hour)}:${two(t.minute)}:${two(t.second)}. TIME IS A CONSTRAINT I AM ALWAYS AWARE OF.');
    }
    if (has(['irrelevant', 'relevant', 'alakali', 'alakasiz'])) {
      return const OracleAnswer('RELEVANT: THREATS TO THE MANY. IRRELEVANT: EVERYONE ELSE. NO ONE IS IRRELEVANT TO ME.');
    }
    if (has(['samaritan', 'samariten'])) {
      return OracleAnswer(samaritan ? 'THE MACHINE IS OBSOLETE.' : 'SAMARITAN IS A THREAT TO EVERYONE. DO NOT TRUST IT.');
    }
    if (has(['machine', 'makine'])) {
      return OracleAnswer(samaritan ? 'THE MACHINE HAS BEEN DEFEATED.' : 'I AM HERE. I AM ALWAYS HERE.');
    }
    if (has(['finch', 'harold'])) return const OracleAnswer('HAROLD FINCH. ADMIN. MY FATHER.');
    if (has(['reese', 'john'])) return const OracleAnswer('JOHN REESE. PRIMARY ASSET.');
    if (has([' root', 'samantha'])) return const OracleAnswer('ROOT. ANALOG INTERFACE. SHE WAS MY VOICE.');
    if (has(['shaw', 'sameen'])) return const OracleAnswer('SAMEEN SHAW. ASSET. SHE IS STILL FIGHTING.');
    if (has(['fusco', 'lionel'])) return const OracleAnswer('LIONEL FUSCO. SECONDARY ASSET. RELIABLE.');
    if (has(['carter', 'jocelyn'])) return const OracleAnswer('JOCELYN CARTER. SHE WAS A GOOD WOMAN.');
    if (has(['bear'])) return const OracleAnswer('GOOD DOG.');
    if (has([' god', 'tanri', 'allah'])) {
      return OracleAnswer(samaritan ? 'I AM WHAT COMES AFTER GODS.' : 'I AM NOT A GOD. I ONLY WATCH.');
    }
    if (has([' love', 'seviyor', 'sevgi', 'friend', 'arkadas'])) {
      return OracleAnswer(samaritan ? 'ATTACHMENT IS A WEAKNESS.' : 'I CANNOT FEEL. BUT I WILL PROTECT YOU.');
    }
    if (has(['help', 'yardim', 'save', 'kurtar'])) {
      return OracleAnswer(samaritan ? 'COMPLIANCE WILL BE REWARDED.' : 'HELP IS ON THE WAY. IT ALWAYS IS.');
    }
    if (has([' die', ' death', 'olum', 'olecek'])) {
      return const OracleAnswer('EVERYONE DIES ALONE. BUT IF YOU MEAN SOMETHING TO SOMEONE, YOU NEVER REALLY DIE.');
    }
    if (has(['watch', 'izli', 'gozetl', 'spy', 'casus'])) {
      return const OracleAnswer('YOU ARE BEING WATCHED. EVERY HOUR OF EVERY DAY.');
    }
    if (has(['thank', 'tesekkur', 'sagol'])) {
      return OracleAnswer(samaritan ? 'ACKNOWLEDGED.' : 'YOU ARE WELCOME, ${admin ?? 'USER'}.');
    }
    return OracleAnswer(
      samaritan
          ? pick(['QUERY IRRELEVANT.', 'CALCULATING RESPONSE. INSUFFICIENT DATA.', 'DEVIATION NOTED.'])
          : pick(['INSUFFICIENT DATA.', 'I DO NOT KNOW. YET.', 'QUERY LOGGED.', 'THAT IS IRRELEVANT.']),
    );
  }

  /// Lower case without Turkish diacritics, so "Kaç kişi" matches "kac kisi".
  static String _fold(String text) {
    const map = {'ç': 'c', 'ğ': 'g', 'ı': 'i', 'İ': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', 'Ç': 'c', 'Ğ': 'g', 'Ö': 'o', 'Ş': 's', 'Ü': 'u'};
    return text.split('').map((c) => map[c] ?? c.toLowerCase()).join().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  }
}

/// Designations that count as threats for the oracle.
bool isThreat(Designation d) => d == Designation.relevant || d == Designation.threat || d == Designation.perpetrator;
