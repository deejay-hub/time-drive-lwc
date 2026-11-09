// Data 360 load test (read-only): the Data 360 provider's queries, written
// out as it builds them, against a large DMO with a stand-in for "one
// person". Each step logs its time and what it used of the request's limits.
// Placeholders filled in by the runner: __PERSON__ (a country, or ALL).
String person = '__PERSON__';
String dmo = 'Reservation_Dataset__dlm';
String personField = 'country__c';
String dateField = 'reservation_status_date__c'; // a Date: compared as days
Date since = Date.newInstance(2022, 10, 1);
Date until = Date.today().addYears(1);
TimeDriveData360SqlRunner sql = new TimeDriveData360SqlRunner();

String personSql = person == 'ALL' ? 'TRUE' : personField + ' IN (\'' + person + '\')';
String personSoql = person == 'ALL' ? personField + ' != null' : personField + ' IN :ids';
List<String> ids = new List<String>{ person };
String day = 'to_char(date_trunc(\'day\', CAST(' + dateField + ' AS TIMESTAMP)), \'YYYY-MM-DD\')';
String rangeSql = '(' + dateField + ' >= DATE \'' + String.valueOf(since) + '\' AND ' + dateField + ' <= DATE \'' + String.valueOf(until) + '\')';

Long t0;
Integer cpu0;
Integer heapPeak = 0;
void mark(String step, String outcome) {
  heapPeak = Math.max(heapPeak, Limits.getHeapSize());
  System.debug(
    'STEP ' + step + ' | ' + outcome +
    ' | ms=' + (System.currentTimeMillis() - t0) +
    ' cpu=' + (Limits.getCpuTime() - cpu0) +
    ' soql=' + Limits.getQueries() + ' rows=' + Limits.getQueryRows() +
    ' callouts=' + Limits.getCallouts() + ' heap=' + Limits.getHeapSize()
  );
}

// 1. The summary: a count per day over the whole window, in Data 360.
t0 = System.currentTimeMillis();
cpu0 = Limits.getCpuTime();
List<List<Object>> perDay = sql.run(
  'SELECT ' + day + ' AS g0, COUNT(*) AS n FROM ' + dmo + ' WHERE ' + personSql + ' AND (' + rangeSql + ') GROUP BY ' + day,
  null
);
Map<String, Integer> counts = new Map<String, Integer>();
Integer total = 0;
Integer busiest = 0;
for (List<Object> row : perDay) {
  Integer n = Integer.valueOf(String.valueOf(row[1]));
  counts.put(String.valueOf(row[0]).left(10), n);
  total += n;
  busiest = Math.max(busiest, n);
}
mark('summary', 'days=' + counts.size() + ' total=' + total + ' busiest=' + busiest);

// The pages the component would ask for: newest, busiest, quietest 7 days.
List<String> keys = new List<String>(counts.keySet());
keys.sort();
List<String> newest = new List<String>();
for (Integer i = keys.size() - 1; i >= 0 && newest.size() < 7; i--) newest.add(keys[i]);
List<String> ranked = new List<String>();
for (String k : keys) ranked.add(String.valueOf(1000000 + counts.get(k)) + '|' + k);
ranked.sort();
List<String> busy7 = new List<String>();
List<String> quiet7 = new List<String>();
for (Integer i = 0; i < Math.min(7, ranked.size()); i++) {
  quiet7.add(ranked[i].substringAfter('|'));
  busy7.add(ranked[ranked.size() - 1 - i].substringAfter('|'));
}

// 2. A page: busy days (over 50) counted, the quiet ones read as rows, as
// the provider does with the busy-day hints.
void page(String name, List<String> pageKeys) {
  t0 = System.currentTimeMillis();
  cpu0 = Limits.getCpuTime();
  List<String> busy = new List<String>();
  List<String> quiet = new List<String>();
  for (String k : pageKeys) {
    if (counts.get(k) > 50) busy.add(k);
    else quiet.add(k);
  }
  Integer grouped = 0;
  if (!busy.isEmpty()) {
    List<String> spans = new List<String>();
    for (String k : busy) spans.add('(' + dateField + ' = DATE \'' + k + '\')');
    for (List<Object> row : sql.run(
      'SELECT ' + day + ' AS g0, COUNT(*) AS n FROM ' + dmo + ' WHERE ' + personSql + ' AND (' + String.join(spans, ' OR ') + ') GROUP BY ' + day,
      null
    )) grouped += Integer.valueOf(String.valueOf(row[1]));
  }
  Integer rowsRead = 0;
  if (!quiet.isEmpty()) {
    Map<String, Object> binds = new Map<String, Object>{ 'ids' => ids };
    List<String> spans = new List<String>();
    for (Integer i = 0; i < quiet.size(); i++) {
      binds.put('d' + i, Date.valueOf(quiet[i]));
      spans.add('(' + dateField + ' = :d' + i + ')');
    }
    String soql =
      'SELECT Id, ' + dateField + ', reservation_id__c, resort__c, adr__c, reserved_room_type__c FROM ' + dmo +
      ' WHERE ' + personSoql + ' AND (' + String.join(spans, ' OR ') + ') ORDER BY ' + dateField + ' DESC LIMIT 500';
    rowsRead = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE).size();
  }
  mark('page-' + name, 'busy=' + busy.size() + ' (' + grouped + ' items grouped) quiet=' + quiet.size() + ' rowsRead=' + rowsRead);
}
page('newest', newest);
page('busiest', busy7);
page('quietest', quiet7);

// 3. A summary out of date: a busy day read as rows (Max Records caps it).
t0 = System.currentTimeMillis();
cpu0 = Limits.getCpuTime();
Map<String, Object> binds = new Map<String, Object>{ 'ids' => ids, 'd0' => Date.valueOf(busy7[0]) };
Integer stale = Database.queryWithBinds(
  'SELECT Id, ' + dateField + ', reservation_id__c FROM ' + dmo + ' WHERE ' + personSoql + ' AND (' + dateField + ' = :d0) ORDER BY ' + dateField + ' DESC LIMIT 500',
  binds,
  AccessLevel.USER_MODE
).size();
mark('stale-busy-day', 'day=' + busy7[0] + ' (' + counts.get(busy7[0]) + ' items) rowsRead=' + stale);
System.debug('PEAK heap=' + heapPeak + '/' + Limits.getLimitHeapSize() + ' cpuLimit=' + Limits.getLimitCpuTime());
