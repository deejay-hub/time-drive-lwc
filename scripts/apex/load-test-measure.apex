// Timeline load test (read-only): one request the component makes, and the
// governor limits it used. Placeholders filled in by the runner:
// __CONTACT__, __MODE__ (summary | days), __KEYS__.
Id contactId = '__CONTACT__';
String mode = '__MODE__';
List<String> keys = new List<String>{ __KEYS__ };

Long started = System.currentTimeMillis();
Integer cpu0 = Limits.getCpuTime();
String outcome;
try {
  if (mode == 'summary') {
    TimeDriveController.TimelineSummary s = TimeDriveController.getSummary(
      contactId, null, null, '2', '1'
    );
    Integer busiest = 0;
    for (TimeDriveController.DaySummary d : s.days) {
      busiest = Math.max(busiest, d.count);
    }
    outcome = 'total=' + s.total + ' days=' + s.days.size() + ' unit=' + s.unit + ' busiest=' + busiest + ' warnings=' + s.warnings;
    // The pages the next runs ask for: newest, busiest and quietest 7 days.
    List<String> newest = new List<String>();
    String today = Datetime.now().format('yyyy-MM-dd');
    for (TimeDriveController.DaySummary d : s.days) {
      if (newest.size() < 7 && d.key <= today) newest.add(d.key);
    }
    System.debug('KEYS_NEWEST ' + String.join(newest, ','));
    // Busiest and quietest days: counts as zero-padded text, sorted.
    List<String> ranked = new List<String>();
    for (TimeDriveController.DaySummary d : s.days) {
      ranked.add(String.valueOf(1000000 + d.count) + '|' + d.key);
    }
    ranked.sort();
    List<String> busy = new List<String>();
    List<String> quiet = new List<String>();
    for (Integer i = 0; i < Math.min(7, ranked.size()); i++) {
      quiet.add(ranked[i].substringAfter('|'));
      busy.add(ranked[ranked.size() - 1 - i].substringAfter('|'));
    }
    System.debug('KEYS_BUSY ' + String.join(busy, ','));
    System.debug('KEYS_QUIET ' + String.join(quiet, ','));
  } else {
    List<TimeDriveController.EngagementEvent> page = TimeDriveController.getDays(
      contactId, null, null, '2', '1', keys, null
    );
    Integer grouped = 0;
    Integer represented = 0;
    for (TimeDriveController.EngagementEvent e : page) {
      if (e.grouped == true) {
        grouped++;
        represented += e.groupCount == null ? 0 : e.groupCount;
      } else {
        represented++;
      }
    }
    outcome = 'rows=' + page.size() + ' grouped=' + grouped + ' items=' + represented;
  }
} catch (Exception e) {
  outcome = 'FAILED ' + e.getTypeName() + ': ' + e.getMessage();
}
System.debug(
  'RESULT ' + outcome +
  ' | soql=' + Limits.getQueries() + '/' + Limits.getLimitQueries() +
  ' rows=' + Limits.getQueryRows() + '/' + Limits.getLimitQueryRows() +
  ' heapNow=' + Limits.getHeapSize() + '/' + Limits.getLimitHeapSize() +
  ' cpu=' + (Limits.getCpuTime() - cpu0) + '/' + Limits.getLimitCpuTime() +
  ' wallMs=' + (System.currentTimeMillis() - started)
);
