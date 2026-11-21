/**
 * Engagement events for Time Drive LWC: every active
 * Time Drive Source for the record's object (Salesforce records, Data
 * 360 DMOs or Apex providers) merged into one newest-first stream.
 */
// The branching follows the platform's cases and the plot's rules; splitting it up would only scatter them.
// Size, parameter lists and field counts follow the platform's entry points, its cases and the data the components exchange;
// splitting them up would only scatter what belongs together.
@SuppressWarnings(
  'PMD.CyclomaticComplexity, PMD.CognitiveComplexity, PMD.AvoidBooleanMethodParameters, PMD.ExcessiveParameterList, PMD.ExcessivePublicCount, PMD.NcssCount, PMD.TooManyFields'
)
public with sharing class TimeDriveController {
  // How far back and forward the timeline reaches, in years: the App Builder's
  // History and Future. Only these values; anything else falls back to the
  // default with a warning.
  public static final Set<Decimal> RANGE_YEARS = new Set<Decimal>{ 0.25, 0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
  // A date range the user narrows it to (the Filters panel's Back and Ahead)
  // can also be a month ("1m"), and start today (History "0").
  private static final String ONE_MONTH = '1m';
  public static final Decimal DEFAULT_HISTORY_YEARS = 1;
  // A day with more matching events than this comes back as one row per
  // event type ("212 Email events") instead of every event.
  public static final Integer GROUP_OVER = 50;
  // Reads of one source for one page, at most, before the periods left are
  // counted instead (see readInFull).
  private static final Integer MAX_READS = 4;
  // Query rows the summary's counts may use, of the 50,000 a request has
  // (the rest is for sources read as rows). Each counted Salesforce source
  // can use a row per period, so a long window, or many sources, counts per
  // week or month instead of per day.
  public static final Integer COUNT_ROWS = 30000;

  // Past this much of a request's SOQL queries or CPU time, getTimeline leaves the
  // days to a request of their own.
  private static final Integer SPENT_QUERIES = 45;
  private static final Integer SPENT_CPU_MS = 5000;
  @TestVisible
  private static Boolean testBudgetSpent;

  public static final Integer GROUP_PAGE_SIZE = 50;
  public static final Integer MAX_GROUP_PAGE_SIZE = 200;

  // A record page that's a person account: an Account with its own Contact.
  public static final String PERSON_ACCOUNT = 'PersonAccount';

  private static final Map<Id, Id> PERSON_CONTACTS = new Map<Id, Id>();

  /**
   * The whole history as per-period counts (no event details): what the day
   * list, minimap, filter panel and counts are drawn from. Periods are days,
   * or weeks or months when the window is too long to count by day (see
   * COUNT_ROWS). Sources that can count (TimeDriveCountProvider: every
   * Salesforce object, Data 360) are counted, however many records they
   * hold; others are read as rows. Filters are applied here, so counts match
   * what the days will show. History and Future (years, e.g. "2" and "0.5";
   * Future blank or "None" for up to today) set the window.
   * @param contactId the Id of the Contact or Account the timeline is on
   * @param categories the categories to show, or null for all
   * @param hiddenTypes the event types to leave out
   * @param historyYears how many years back to look, as the App Builder lists them
   * @param futureYears how many years ahead to look, or blank for up to today
   * @return the per-period counts, with any warnings and problems
   */
  @AuraEnabled(cacheable=true)
  public static TimelineSummary getSummary(
    Id contactId,
    List<String> categories,
    List<String> hiddenTypes,
    String historyYears,
    String futureYears
  ) {
    return summarise(contactId, categories, hiddenTypes, historyYears, futureYears, null);
  }

  // The summary; `keep`, when given, gets its Run, so the days read in the
  // same request reuse what it learned (its sources, rows read whole, counts
  // that failed) instead of doing it all again.
  private static TimelineSummary summarise(
    Id contactId,
    List<String> categories,
    List<String> hiddenTypes,
    String historyYears,
    String futureYears,
    List<Run> keep
  ) {
    TimelineSummary summary = new TimelineSummary();
    if (contactId == null) {
      return summary;
    }
    Filters filters = new Filters(categories, hiddenTypes);
    List<Tally> tallies;
    Run run;
    try {
      run = new Run(
        contactId,
        summary.warnings,
        summary.problems,
        windowFor(historyYears, futureYears, summary.warnings)
      );
      run.only = filters;
      if (keep != null) {
        keep.add(run);
      }
      tallies = run.tallies();
      summary.unit = run.unit;
      summary.counted = run.countedNames;
    } catch (Exception e) {
      throw safeFailure(e);
    }

    // Types offered in the filter panel: those in the view, whatever else.
    Map<String, TypeCount> typeCounts = new Map<String, TypeCount>();
    Map<String, DaySummary> days = new Map<String, DaySummary>();
    for (Tally t : tallies) {
      summary.unfilteredTotal += t.count;
      if (!filters.inView(t.category)) {
        continue;
      }
      TypeCount type = typeCounts.get(t.type);
      if (type == null) {
        type = new TypeCount(t.type, 0);
        type.label = t.typeLabel;
        type.labelName = t.typeLabelName;
        type.icon = t.icon;
        type.iconColour = t.iconColour;
        typeCounts.put(t.type, type);
      }
      type.count += t.count;

      if (!filters.shows(t)) {
        continue;
      }
      DaySummary day = days.get(t.dayKey);
      if (day == null) {
        day = new DaySummary(t.dayKey);
        days.put(t.dayKey, day);
      }
      day.count += t.count;
      if (t.source != null) {
        day.add(summary.counted.indexOf(t.source), t.count);
      }
      summary.total += t.count;
    }
    // A page with no sources set up says so, rather than looking empty.
    summary.noSources = run.sources.isEmpty();
    summary.page = run.parentObject == PERSON_ACCOUNT
      ? 'Person Account'
      : TimeDriveConfig.describeType(contactId.getSObjectType()).getLabel();
    // Every source in the view is offered, found nothing or not, so the
    // filter panel always lists what the timeline looks for.
    for (Time_Drive_Source__mdt s : run.sources) {
      if (
        String.isBlank(s.Event_Type__c) ||
        typeCounts.containsKey(s.Event_Type__c) ||
        !filters.inView(TimeDriveConfig.lensKey(s))
      ) {
        continue;
      }
      TypeCount none = new TypeCount(s.Event_Type__c, 0);
      none.label = TimeDriveConfig.legendLabel(s);
      none.labelName = TimeDriveConfig.legendLabelName(s);
      none.icon = String.isBlank(s.Icon__c) ? null : s.Icon__c;
      none.iconColour = String.isBlank(s.Icon_Colour__c) ? null : s.Icon_Colour__c;
      typeCounts.put(s.Event_Type__c, none);
    }
    summary.types.addAll(typeCounts.values());
    // Newest first.
    List<String> keys = new List<String>(days.keySet());
    keys.sort();
    for (Integer i = keys.size() - 1; i >= 0; i--) {
      DaySummary day = days.get(keys[i]);
      // Only a busy period's counts are used again (its grouped rows).
      if (day.count <= GROUP_OVER) {
        day.n = null;
      }
      summary.days.add(day);
    }
    return summary;
  }

  /** The summary, and the days the card opens on, in one answer. */
  public class TimelineLoad {
    @AuraEnabled
    public TimelineSummary summary;
    // The periods whose events are in `events` (some may have none).
    @AuraEnabled
    public List<String> keys = new List<String>();
    @AuraEnabled
    public List<EngagementEvent> events = new List<EngagementEvent>();
  }

  /**
   * getSummary and the first getPageDays in one request: the summary, and the
   * events of the days the card will draw first, so it needn't ask again. Not
   * cached (the events must be fresh). `focus` is where the card opens (today,
   * earliest or latest); `newestFirst` the list's order; `centred` puts that
   * period in the middle of `count` periods (the horizontal layout), else it
   * heads a list of `count` (the vertical one, with every period above it when
   * that is fewer than `count`); none for a count of 0. If the card draws other
   * days it asks for them as before.
   * @param contactId the Id of the Contact or Account the timeline is on
   * @param categories the categories to show, or null for all
   * @param hiddenTypes the event types to leave out
   * @param historyYears how many years back to look
   * @param futureYears how many years ahead to look, or blank for up to today
   * @param focus where the card opens (today, earliest or latest)
   * @param newestFirst true when the list runs newest first
   * @param centred true to centre the focus among the periods (horizontal layout)
   * @param count how many periods to open with, 0 for none
   * @return the summary and the events of the opening periods
   */
  @AuraEnabled
  public static TimelineLoad getTimeline(
    Id contactId,
    List<String> categories,
    List<String> hiddenTypes,
    String historyYears,
    String futureYears,
    String focus,
    Boolean newestFirst,
    Boolean centred,
    Integer count
  ) {
    TimeDriveLog.recordId = contactId;
    try {
      return loadTimeline(
        contactId,
        categories,
        hiddenTypes,
        historyYears,
        futureYears,
        focus,
        newestFirst,
        centred,
        count
      );
    } finally {
      // What failed, written to the log once everything has been read.
      TimeDriveLog.flush();
    }
  }

  private static TimelineLoad loadTimeline(
    Id contactId,
    List<String> categories,
    List<String> hiddenTypes,
    String historyYears,
    String futureYears,
    String focus,
    Boolean newestFirst,
    Boolean centred,
    Integer count
  ) {
    TimelineLoad out = new TimelineLoad();
    List<Run> summaryRun = new List<Run>();
    out.summary = summarise(contactId, categories, hiddenTypes, historyYears, futureYears, summaryRun);
    // A count of none asks for the summary alone (a refresh keeps its place and
    // asks for the days it is on).
    if (contactId == null || out.summary.days.isEmpty() || (count != null && count <= 0)) {
      return out;
    }
    // The summary used much of this request's queries or time (many sources, a
    // busy account): the days are asked for on their own, in a request of their
    // own, rather than risk the limits here.
    if (budgetSpent()) {
      return out;
    }
    Integer size = count == null ? 7 : Math.max(1, Math.min(count, 30));
    out.keys = openingKeys(
      out.summary,
      windowFor(historyYears, futureYears, new List<String>()),
      focus,
      newestFirst != false,
      centred == true,
      size
    );
    if (out.keys.isEmpty()) {
      return out;
    }
    List<String> busy = new List<String>();
    Set<String> wanted = new Set<String>(out.keys);
    for (DaySummary d : out.summary.days) {
      if (wanted.contains(d.key) && d.count > out.summary.groupOver) {
        busy.add(d.key);
      }
    }
    // The days are read knowing what the summary just counted.
    out.events = readDays(
      contactId,
      categories,
      hiddenTypes,
      historyYears,
      futureYears,
      out.keys,
      busy,
      emptySourcesFor(out.summary, wanted),
      busyCountsFor(out.summary, wanted),
      runsOf(out.summary, wanted, new Set<String>(busy)),
      summaryRun.isEmpty() ? null : summaryRun[0],
      out.summary.problems
    );
    return out;
  }

  /**
   * The wanted periods that follow one another in the summary (it lists every
   * period that has items, so nothing with items lies between two of them),
   * each run as its periods' keys joined by commas. A run is read as one span
   * of dates, not one range per period; a busy period (counted, not read)
   * ends a run, so its items are never pulled in.
   * @param summary the timeline summary listing every period with items
   * @param wanted the period keys asked for
   * @param busy the period keys that are counted, not read
   * @return each run of consecutive wanted periods as keys joined by commas
   */
  private static List<String> runsOf(TimelineSummary summary, Set<String> wanted, Set<String> busy) {
    List<String> runs = new List<String>();
    List<String> current = new List<String>();
    for (DaySummary d : summary.days) {
      if (wanted.contains(d.key) && !busy.contains(d.key)) {
        current.add(d.key);
      } else if (!current.isEmpty()) {
        runs.add(String.join(current, ','));
        current = new List<String>();
      }
    }
    if (!current.isEmpty()) {
      runs.add(String.join(current, ','));
    }
    return runs;
  }

  // The counted sources the summary found nothing in, over these periods.
  private static List<String> emptySourcesFor(TimelineSummary summary, Set<String> keys) {
    Set<Integer> found = new Set<Integer>();
    for (DaySummary d : summary.days) {
      if (keys.contains(d.key)) {
        found.addAll(d.src);
      }
    }
    List<String> empty = new List<String>();
    for (Integer i = 0; i < summary.counted.size(); i++) {
      if (!found.contains(i)) {
        empty.add(summary.counted[i]);
      }
    }
    return empty;
  }

  // What the summary counted for each source in the busy periods among these.
  private static List<BusyCount> busyCountsFor(TimelineSummary summary, Set<String> keys) {
    List<BusyCount> out = new List<BusyCount>();
    for (DaySummary d : summary.days) {
      if (!keys.contains(d.key) || d.count <= summary.groupOver || d.n == null) {
        continue;
      }
      for (Integer j = 0; j < d.src.size(); j++) {
        BusyCount b = new BusyCount();
        b.key = d.key;
        b.source = summary.counted[d.src[j]];
        b.count = d.n[j];
        out.add(b);
      }
    }
    return out;
  }

  private static Boolean budgetSpent() {
    if (testBudgetSpent != null) {
      return testBudgetSpent;
    }
    return Limits.getQueries() > SPENT_QUERIES || Limits.getCpuTime() > SPENT_CPU_MS;
  }

  /**
   * The periods with items the card draws first, as it works them out: the
   * days (with the placeholders for today, where History starts and where
   * Future ends) in the list's order, the focus among them, and a window around
   * it (see getTimeline). Only periods with items come back.
   * @param summary the timeline summary listing every period with items
   * @param window the dates the timeline covers
   * @param focus where the card opens (today, earliest or latest)
   * @param newestFirst true when the list runs newest first
   * @param centred true to centre the focus among the periods
   * @param size how many periods to open with
   * @return the keys of the opening periods that have items
   */
  @TestVisible
  private static List<String> openingKeys(
    TimelineSummary summary,
    TimeDriveContext.Span window,
    String focus,
    Boolean newestFirst,
    Boolean centred,
    Integer size
  ) {
    Set<String> real = new Set<String>();
    for (DaySummary d : summary.days) {
      real.add(d.key);
    }
    Set<String> all = new Set<String>(real);
    String nowKey = TimeDriveContext.periodKey(Date.today(), summary.unit);
    all.add(nowKey);
    all.add(TimeDriveContext.periodKey(window.since.date(), summary.unit));
    // The end is a period of its own only when Future reaches past today.
    if (window.until.date() > Date.today()) {
      all.add(TimeDriveContext.periodKey(window.until.date(), summary.unit));
    }
    List<String> ordered = new List<String>(all);
    ordered.sort();
    if (newestFirst) {
      List<String> reversed = new List<String>();
      for (Integer i = ordered.size() - 1; i >= 0; i--) {
        reversed.add(ordered[i]);
      }
      ordered = reversed;
    }
    // Earliest and latest are of the periods with items.
    Integer index = 0;
    String want = String.isBlank(focus) ? 'today' : focus.toLowerCase();
    String earliest;
    String latest;
    for (String key : ordered) {
      if (real.contains(key)) {
        earliest = earliest == null || key < earliest ? key : earliest;
        latest = latest == null || key > latest ? key : latest;
      }
    }
    // Open At as the App Builder names it: Today, Earliest item, Latest item.
    String target = want.startsWith('earliest')
      ? earliest
      : (want.startsWith('latest') ? latest : (ordered.contains(nowKey) ? nowKey : latest));
    index = Math.max(0, ordered.indexOf(target));
    Integer startAt;
    Integer stopAt;
    if (centred) {
      startAt = Math.max(0, Math.min(index - size / 2, ordered.size() - size));
      stopAt = Math.min(ordered.size(), startAt + size);
    } else if (index <= 0) {
      startAt = 0;
      stopAt = Math.min(ordered.size(), size);
    } else if (index < size) {
      startAt = 0;
      stopAt = Math.min(ordered.size(), index + size);
    } else {
      startAt = Math.max(0, Math.min(index, ordered.size() - size));
      stopAt = Math.min(ordered.size(), startAt + size);
    }
    List<String> keys = new List<String>();
    for (Integer i = startAt; i < stopAt; i++) {
      if (real.contains(ordered[i])) {
        keys.add(ordered[i]);
      }
    }
    return keys;
  }

  /**
   * Full events for the given periods (keys from getSummary), newest
   * first, with the same filters; each event's dayKey is its period's key.
   * The timeline asks for a page at a time. Counted sources are queried for
   * those periods only, and not at all for a busy one: its counts come back
   * as grouped rows.
   *
   * The summary's hints mean fewer queries run: `emptySources` are counted
   * sources the summary found nothing in for these days (not queried again),
   * and `busyCounts` are its counts for the busy days (their grouped rows are
   * built from them, not counted again; a grouped row then stands for the
   * whole period, "All day"). Both are hints for what the user sees: leave
   * them null and every source is queried. `runs` are the days asked for that follow one
   * another in the summary, each run's keys joined by commas: a run is read
   * as one span of dates, not one range per day (see runsOf).
   * @param contactId the Id of the Contact or Account the timeline is on
   * @param categories the categories to show, or null for all
   * @param hiddenTypes the event types to leave out
   * @param historyYears how many years back to look
   * @param futureYears how many years ahead to look, or blank for up to today
   * @param dayKeys the period keys to read
   * @param busyKeys the period keys that come back as grouped rows
   * @param emptySources counted sources the summary found nothing in, or null
   * @param busyCounts the summary's counts for the busy periods, or null
   * @param runs the consecutive period keys, each run joined by commas
   * @return the events of those periods, newest first
   */
  // Not cached in the browser: Refresh must bring back new items on days
  // already drawn (the component keeps the days it has fetched itself).
  @AuraEnabled
  public static List<EngagementEvent> getPageDays(
    Id contactId,
    List<String> categories,
    List<String> hiddenTypes,
    String historyYears,
    String futureYears,
    List<String> dayKeys,
    List<String> busyKeys,
    List<String> emptySources,
    List<BusyCount> busyCounts,
    List<String> runs
  ) {
    TimeDriveLog.recordId = contactId;
    try {
      return readDays(
        contactId,
        categories,
        hiddenTypes,
        historyYears,
        futureYears,
        dayKeys,
        busyKeys,
        emptySources,
        busyCounts,
        runs,
        null,
        null
      );
    } finally {
      TimeDriveLog.flush();
    }
  }

  // Runs as the card sends them ("2026-10-03,2026-10-02"), each a list of keys.
  private static List<List<String>> parsedRuns(List<String> runs) {
    List<List<String>> out = new List<List<String>>();
    for (String run : runs ?? new List<String>()) {
      if (String.isNotBlank(run)) {
        out.add(run.split(','));
      }
    }
    return out;
  }

  private static List<EngagementEvent> readDays(
    Id contactId,
    List<String> categories,
    List<String> hiddenTypes,
    String historyYears,
    String futureYears,
    List<String> dayKeys,
    List<String> busyKeys,
    List<String> emptySources,
    List<BusyCount> busyCounts,
    List<String> runs,
    Run reuse,
    List<Problem> said
  ) {
    if (contactId == null || dayKeys == null || dayKeys.isEmpty()) {
      return new List<EngagementEvent>();
    }
    // Warnings were already said with the summary.
    List<String> warnings = new List<String>();
    List<EngagementEvent> events;
    List<Problem> failed;
    try {
      Map<String, Map<String, Integer>> counted = countsByPeriod(busyKeys, busyCounts);
      Run run = reuse;
      if (run == null) {
        run = new Run(contactId, warnings, new List<Problem>(), windowFor(historyYears, futureYears, warnings));
      } else {
        // The summary's, read in this request: its warnings and problems
        // are said; the days apply the filters themselves.
        run.warnings = warnings;
        run.problems = new List<Problem>();
        run.only = null;
      }
      events = run
        .days(
          new Set<String>(dayKeys),
          new Filters(categories, hiddenTypes),
          GROUP_OVER,
          busyKeys == null ? null : new Set<String>(busyKeys),
          emptySources == null ? null : new Set<String>(emptySources),
          counted,
          parsedRuns(runs)
        );
      markRights(events);
      failed = run.problems;
    } catch (Exception e) {
      throw safeFailure(e);
    }
    // A source that counted but whose rows couldn't be read: with the summary,
    // it joins the summary's problems (the timeline shows its error page,
    // naming it); on its own (a page of days), the request fails, so the
    // page shows the error rather than a gap.
    if (!failed.isEmpty()) {
      if (said == null) {
        throw coded(failed[0].kind);
      }
      for (Problem p : failed) {
        Boolean known = false;
        for (Problem q : said) {
          known = known || q.source == p.source;
        }
        if (!known) {
          said.add(p);
        }
      }
    }
    return events;
  }

  // The summary's counts for the busy periods, by period then source; null
  // (count them here) when they don't cover every busy period: a period
  // left without counts would come back empty.
  @TestVisible
  private static Map<String, Map<String, Integer>> countsByPeriod(List<String> busyKeys, List<BusyCount> busyCounts) {
    if (busyCounts == null) {
      return null;
    }
    Map<String, Map<String, Integer>> counted = new Map<String, Map<String, Integer>>();
    for (BusyCount b : busyCounts) {
      if (b?.key == null || b.source == null || b.count == null) {
        return null;
      }
      if (!counted.containsKey(b.key)) {
        counted.put(b.key, new Map<String, Integer>());
      }
      counted.get(b.key).put(b.source, b.count);
    }
    for (String key : busyKeys ?? new List<String>()) {
      if (!counted.containsKey(key)) {
        return null;
      }
    }
    return counted;
  }

  /**
   * View all: a grouped row's items, a page at a time, newest first. The
   * type's Salesforce sources between fromAt and toAt (the row's span), each
   * paged by its own keyset (date, then Id, after its last item shown), so
   * nothing is skipped or repeated however many there are. `cursor` is the
   * last page's, null for the first; the first also says what the page is
   * for (the type's label and icon, the record's name). Each item carries
   * the source's own detail fields, which are the page's columns.
   * @param recordId the Id of the record the timeline is on
   * @param type the event type whose items are listed
   * @param fromAt the start of the grouped row's span
   * @param toAt the end of the grouped row's span
   * @param pageSize how many items to return, or null for the default
   * @param cursor the previous page's cursor, or null for the first page
   * @return one page of items with a cursor for the next
   */
  @AuraEnabled
  public static GroupPage getGroupPage(
    Id recordId,
    String type,
    Datetime fromAt,
    Datetime toAt,
    Integer pageSize,
    String cursor
  ) {
    if (recordId == null || String.isBlank(type) || fromAt == null || toAt == null) {
      return new GroupPage();
    }
    Integer size = pageSize == null ? GROUP_PAGE_SIZE : Math.max(1, Math.min(pageSize, MAX_GROUP_PAGE_SIZE));
    TimeDriveLog.recordId = recordId;
    try {
      Map<String, List<String>> cursors = String.isBlank(cursor)
        ? new Map<String, List<String>>()
        : (Map<String, List<String>>) JSON.deserialize(cursor, Map<String, List<String>>.class);
      // Whole days (the user's): a grouped row stands for every item of its
      // type in its day, week or month, and date-only items' span is an
      // instant (midday).
      TimeDriveContext.Span days = new TimeDriveContext.Span(
        Datetime.newInstance(fromAt.date(), Time.newInstance(0, 0, 0, 0)),
        Datetime.newInstance(toAt.date(), Time.newInstance(23, 59, 59, 999))
      );
      GroupPage page = new Run(recordId, new List<String>(), new List<Problem>(), days).page(type, size, cursors);
      if (String.isBlank(cursor)) {
        page.recordName = nameOf(recordId);
      }
      return page;
    } catch (Exception e) {
      throw safeFailure(e);
    } finally {
      TimeDriveLog.flush();
    }
  }

  // The record's name, for the page's breadcrumb; null when it has none or
  // it can't be read.
  private static String nameOf(Id recordId) {
    try {
      List<SObject> rows = Database.queryWithBinds(
        'SELECT Name FROM ' +
          TimeDriveConfig.describeType(recordId.getSObjectType()).getName() +
          ' WHERE Id = :recordId',
        new Map<String, Object>{ 'recordId' => recordId },
        AccessLevel.USER_MODE
      );
      return rows.isEmpty() ? null : (String) rows[0].get('Name');
    } catch (Exception e) {
      return null;
    }
  }

  /** One page of a grouped row's items, with what the page needs to draw itself. */
  public class GroupPage {
    @AuraEnabled
    public List<EngagementEvent> items = new List<EngagementEvent>();
    // Where the next page starts (pass it back), and whether there is one.
    @AuraEnabled
    public String cursor;
    @AuraEnabled
    public Boolean more = false;
    // Sources that couldn't be read.
    @AuraEnabled
    public List<Problem> problems = new List<Problem>();
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String labelName;
    @AuraEnabled
    public String icon;
    // Every source's date is a date (no time to show).
    @AuraEnabled
    public Boolean dateOnly = false;
    // The record the timeline is on, for the way back.
    @AuraEnabled
    public String recordName;
  }

  /**
   * Every event, newest first: every source read over the whole window, the
   * heaviest read there is. For tests only; the timeline reads a summary and
   * pages of days, and nothing on the client can call this.
   * @param contactId the Id of the Contact or Account the timeline is on
   * @return the events and any warnings and problems
   */
  @TestVisible
  private static TimelineResult getEvents(Id contactId) {
    TimelineResult result = new TimelineResult();
    if (contactId == null) {
      return result;
    }
    result.events = collect(contactId, result.warnings, result.problems, new TimeDriveContext.Span());
    return result;
  }

  /**
   * Days with more than `threshold` events become one row per event type,
   * newest first: the latest event's time, the earliest kept as firstAt, and
   * the count. Quieter days pass through unchanged, and so does a type with
   * a single item on a busy day (a group of one says no more than the item).
   * Rows already grouped (a counted source's busy day) count as their
   * groupCount.
   * @param events the events to group
   * @param threshold the most events a day shows before it is grouped
   * @return the events with busy days grouped by type
   */
  @TestVisible
  private static List<EngagementEvent> groupBusyDays(List<EngagementEvent> events, Integer threshold) {
    Map<String, List<EngagementEvent>> byDay = new Map<String, List<EngagementEvent>>();
    Map<String, Integer> sizes = new Map<String, Integer>();
    for (EngagementEvent e : events) {
      if (!byDay.containsKey(e.dayKey)) {
        byDay.put(e.dayKey, new List<EngagementEvent>());
        sizes.put(e.dayKey, 0);
      }
      byDay.get(e.dayKey).add(e);
      sizes.put(e.dayKey, sizes.get(e.dayKey) + weight(e));
    }
    List<EngagementEvent> result = new List<EngagementEvent>();
    for (String day : byDay.keySet()) {
      List<EngagementEvent> dayEvents = byDay.get(day);
      if (sizes.get(day) <= threshold) {
        result.addAll(dayEvents);
        continue;
      }
      Map<String, EngagementEvent> groups = new Map<String, EngagementEvent>();
      Map<String, EngagementEvent> lone = new Map<String, EngagementEvent>();
      for (EngagementEvent e : dayEvents) {
        Datetime first = e.grouped && e.firstAt != null ? e.firstAt : e.occurredAt;
        EngagementEvent g = groups.get(e.type);
        if (g == null) {
          g = new EngagementEvent('group-' + day + '-' + e.type, e.type, e.category, null, null, e.occurredAt);
          g.grouped = true;
          g.allDay = e.allDay;
          g.groupCount = 0;
          g.firstAt = first;
          g.dayKey = day;
          g.sourceLabel = e.sourceLabel;
          g.sourceObject = e.sourceObject;
          g.icon = e.icon;
          g.iconColour = e.iconColour;
          g.typeLabel = e.typeLabel;
          g.typeLabelName = e.typeLabelName;
          groups.put(e.type, g);
          lone.put(e.type, e);
        } else {
          lone.remove(e.type);
        }
        g.groupCount += weight(e);
        g.allDay = g.allDay && e.allDay;
        if (e.occurredAt > g.occurredAt) {
          g.occurredAt = e.occurredAt;
        }
        if (first < g.firstAt) {
          g.firstAt = first;
        }
      }
      for (String type : groups.keySet()) {
        EngagementEvent only = lone.get(type);
        // A single plain item stays itself; a counted row of one stays grouped.
        result.add(only != null && !only.grouped ? only : groups.get(type));
      }
    }
    result.sort();
    return result;
  }

  private static Integer weight(EngagementEvent e) {
    return e.grouped && e.groupCount != null ? e.groupCount : 1;
  }

  /**
   * Whether the Overdue lens (by its API name) has anything for this record,
   * for the Overdue button in the header. Asked after the timeline has loaded,
   * as a call of its own: its Salesforce sources are checked once per object
   * (their conditions joined, LIMIT 1), stopping at the first that has an
   * item. False when the lens isn't offered or the check fails.
   * @param recordId the Id of the record the timeline is on
   * @param historyYears how many years back the timeline looks
   * @param futureYears how many years ahead it looks, or blank for up to today
   * @return true when the Overdue lens has at least one item
   */
  @AuraEnabled(cacheable=true)
  public static Boolean getOverdue(Id recordId, String historyYears, String futureYears) {
    if (recordId == null || !TimeDriveConfig.isOffered(TimeDriveConfig.OVERDUE_VIEW)) {
      return false;
    }
    try {
      List<String> unused = new List<String>();
      Run run = new Run(recordId, unused, new List<Problem>(), windowFor(historyYears, futureYears, unused));
      return run.anyIn(TimeDriveConfig.OVERDUE_VIEW);
    } catch (Exception e) {
      // No button: the lens itself still says what's wrong when opened.
      return false;
    }
  }

  /**
   * Says on each item that is a Salesforce record what the user's permissions
   * on its object allow, for the menu at the end of its row (none without
   * either): no query, only the object's describe. What the record itself
   * allows (sharing, ownership, Modify All Data) is asked for when the row's
   * menu is opened (getRights), not for every item drawn.
   * @param events the events to mark with what the user's permissions allow
   */
  @TestVisible
  private static void markRights(List<EngagementEvent> events) {
    for (EngagementEvent e : events) {
      if (e.grouped || e.recordId == null) {
        continue;
      }
      Schema.DescribeSObjectResult object1 = TimeDriveConfig.describeType(e.recordId.getSObjectType());
      e.objectLabel = object1.getLabel();
      e.canEdit = object1.isUpdateable();
      e.canDelete = object1.isDeletable();
    }
  }

  /** What the user may do with one record. */
  public class RecordRights {
    @AuraEnabled
    public Boolean canEdit = false;
    @AuraEnabled
    public Boolean canDelete = false;
  }

  /**
   * Whether the user may edit or delete a record, for its row's menu when it
   * is opened. Two things must allow it: the object (the user's permissions on
   * it; with Modify All Data that is enough) and, otherwise, the record itself
   * (sharing, ownership: UserRecordAccess). If the record's access can't be
   * read, the object's permissions decide and Salesforce still has the last
   * word when the user acts.
   * @param recordId the Id of the record whose rights are wanted
   * @return what the user may do with the record
   */
  // UserRecordAccess and UserPermissionAccess are read-only views of the running user's own access.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  @AuraEnabled(cacheable=true)
  public static RecordRights getRights(Id recordId) {
    RecordRights out = new RecordRights();
    if (recordId == null) {
      return out;
    }
    Schema.DescribeSObjectResult object1 = TimeDriveConfig.describeType(recordId.getSObjectType());
    Boolean modifyAll = false;
    try {
      for (UserPermissionAccess p : [SELECT PermissionsModifyAllData FROM UserPermissionAccess LIMIT 1]) {
        modifyAll = p.PermissionsModifyAllData;
      }
    } catch (Exception ex) {
      modifyAll = false;
    }
    UserRecordAccess access;
    if (!modifyAll) {
      try {
        for (UserRecordAccess a : [
          SELECT RecordId, HasEditAccess, HasDeleteAccess
          FROM UserRecordAccess
          WHERE UserId = :UserInfo.getUserId() AND RecordId = :recordId
        ]) {
          access = a;
        }
      } catch (Exception ex) {
        // Unknown: the object's permissions decide.
        access = null;
      }
    }
    out.canEdit = object1.isUpdateable() && (modifyAll || access == null || access.HasEditAccess);
    out.canDelete = object1.isDeletable() && (modifyAll || access == null || access.HasDeleteAccess);
    return out;
  }

  /** A highlight on an item: an icon (or a dot), its colour and what it says. */
  public class Flag {
    @AuraEnabled
    public String icon;
    @AuraEnabled
    public String colour;
    @AuraEnabled
    public String text;

    /**
     * Builds a highlight.
     * @param icon the icon name, or 'dot'
     * @param colour the icon colour, or null
     * @param text what the highlight says
     */
    public Flag(String icon, String colour, String text) {
      this.icon = icon;
      this.colour = colour;
      this.text = text;
    }
  }

  /**
   * The timeline's views for its picker: { value (the key sources use), label }.
   * @return the views for the picker
   */
  @AuraEnabled(cacheable=true)
  public static List<ViewOption> getViews() {
    List<ViewOption> out = new List<ViewOption>();
    for (Time_Drive_View__mdt v : TimeDriveConfig.activeViews()) {
      ViewOption option = new ViewOption(v.DeveloperName, TimeDriveConfig.viewLabel(v), v.Label);
      option.labelName = TimeDriveConfig.viewLabelName(v);
      out.add(option);
    }
    return out;
  }

  /**
   * What this person last chose (see Time_Drive_Preference__c): their own row, else none.
   * @return the user's saved choices, with blank fields when none
   */
  @AuraEnabled
  public static Preference getPreference() {
    Preference out = new Preference();
    Time_Drive_Preference__c mine = own();
    if (mine != null) {
      out.lens = mine.Last_Lens__c;
      out.itemDetail = mine.Item_Detail__c;
      out.dateRange = mine.Date_Range__c;
      out.lensFilters = mine.Lens_Filters__c;
    }
    return out;
  }

  /**
   * Keeps the event types this person hid in each lens (Sales=call,email;Service=case),
   * so each lens keeps its own filter; blank for none. The timeline fits it to the field,
   * the lens in use first.
   * @param lensFilters each lens's hidden types, or blank for none
   */
  @SuppressWarnings('PMD.ApexCRUDViolation')
  @AuraEnabled
  public static void saveLensFilters(String lensFilters) {
    String kept = String.isBlank(lensFilters) ? null : lensFilters.trim().left(255);
    Time_Drive_Preference__c mine = own();
    if (mine == null && kept == null) {
      return;
    }
    // Written as the system, as savePreference explains.
    if (mine == null) {
      Database.insert(
        new Time_Drive_Preference__c(SetupOwnerId = UserInfo.getUserId(), Lens_Filters__c = kept),
        AccessLevel.SYSTEM_MODE
      );
    } else {
      mine.Lens_Filters__c = kept;
      Database.update(mine, AccessLevel.SYSTEM_MODE);
    }
  }

  /**
   * Keeps how far back and ahead this person narrowed the timeline to, in
   * months ("3,6"), or blank for the page's own History and Future. The
   * timeline offers each side only up to the page's, and trims a kept one
   * that no longer fits.
   * @param dateRange the months back and ahead, or blank for none
   */
  @SuppressWarnings('PMD.ApexCRUDViolation')
  @AuraEnabled
  public static void saveDateRange(String dateRange) {
    String kept = String.isBlank(dateRange) ? null : dateRange.trim().left(20);
    Time_Drive_Preference__c mine = own();
    if (mine == null && kept == null) {
      return;
    }
    // Written as the system, as savePreference explains.
    if (mine == null) {
      Database.insert(
        new Time_Drive_Preference__c(SetupOwnerId = UserInfo.getUserId(), Date_Range__c = kept),
        AccessLevel.SYSTEM_MODE
      );
    } else {
      mine.Date_Range__c = kept;
      Database.update(mine, AccessLevel.SYSTEM_MODE);
    }
  }

  /**
   * Keeps the lens and/or the label choice (Lite or Max) as this person's own;
   * a null leaves that one as it is. Nothing else is kept.
   * @param lens the lens to keep, or null to leave it as it is
   * @param itemDetail the label choice (Lite or Max) to keep, or null to leave it as it is
   */
  @SuppressWarnings('PMD.ApexCRUDViolation')
  @AuraEnabled
  public static void savePreference(String lens, String itemDetail) {
    Time_Drive_Preference__c mine = own();
    Boolean isNew = mine == null;
    if (isNew) {
      mine = new Time_Drive_Preference__c(SetupOwnerId = UserInfo.getUserId());
    }
    if (lens != null) {
      mine.Last_Lens__c = lens.left(80);
    }
    if (itemDetail != null) {
      mine.Item_Detail__c = itemDetail.toLowerCase() == 'lite' ? 'Lite' : 'Max';
    }
    // The row is the running user's own and a custom setting's access can't be granted by a permission
    // set, so user mode would refuse everyone but admins: it is written as the system.
    if (isNew) {
      Database.insert(mine, AccessLevel.SYSTEM_MODE);
    } else {
      Database.update(mine, AccessLevel.SYSTEM_MODE);
    }
  }

  // The user's own row (not the profile's or the org's, which getInstance falls back to).
  private static Time_Drive_Preference__c own() {
    Time_Drive_Preference__c row = Time_Drive_Preference__c.getInstance(UserInfo.getUserId());
    return row != null && row.Id != null && row.SetupOwnerId == UserInfo.getUserId() ? row : null;
  }

  /** The user's saved choices: the lens, the label choice, the date range and each lens's hidden types. */
  public class Preference {
    @AuraEnabled
    public String lens;
    @AuraEnabled
    public String itemDetail;
    @AuraEnabled
    public String dateRange;
    @AuraEnabled
    public String lensFilters;
  }

  /** A view for the picker: the key sources use and its label. */
  public class ViewOption {
    @AuraEnabled
    public String value;
    @AuraEnabled
    public String label;
    // The view's own name (Marketing), beside the picker's (also Marketing now).
    @AuraEnabled
    public String name;
    // The custom label its Menu Label names (Time_Drive_View_Sales), or null
    // for plain text: the card shows its own copy of a label it knows.
    @AuraEnabled
    public String labelName;
    /**
     * Builds a view option.
     * @param value the view's key
     * @param label the label shown in the picker
     * @param name the view's own name
     */
    public ViewOption(String value, String label, String name) {
      this.value = value;
      this.label = label;
      this.name = name;
    }
  }

  /**
   * The person account's Contact, or null for any other record (and in orgs without person
   * accounts, where Account has no IsPersonAccount).
   * @param recordId the Id of the page's record
   * @return the Contact Id, or null
   */
  public static Id personContactOf(Id recordId) {
    if (recordId == null || recordId.getSObjectType() != Account.SObjectType) {
      return null;
    }
    // Asked once per request: the combined first load runs the summary and the
    // days in one transaction, and a record's kind doesn't change within it.
    if (PERSON_CONTACTS.containsKey(recordId)) {
      return PERSON_CONTACTS.get(recordId);
    }
    Id found = lookUpPersonContact(recordId);
    PERSON_CONTACTS.put(recordId, found);
    return found;
  }

  private static Id lookUpPersonContact(Id recordId) {
    Map<String, Schema.SObjectField> fields = TimeDriveConfig.fieldMap('Account');
    if (!fields.containsKey('ispersonaccount') || !fields.containsKey('personcontactid')) {
      return null;
    }
    try {
      String lookup = 'SELECT IsPersonAccount, PersonContactId FROM Account WHERE Id = :recordId';
      Map<String, Object> lookupBinds = new Map<String, Object>{ 'recordId' => recordId };
      List<SObject> rows = Database.queryWithBinds(lookup, lookupBinds, AccessLevel.USER_MODE);
      TimeDriveQueries.record('(page)', 'lookup', lookup);
      if (!rows.isEmpty() && rows[0].get('IsPersonAccount') == true) {
        return (Id) rows[0].get('PersonContactId');
      }
    } catch (Exception e) {
      // The Account can't be read as this user: the page's own Id is used.
    }
    return null;
  }

  private static List<EngagementEvent> collect(
    Id contactId,
    List<String> warnings,
    List<Problem> problems,
    TimeDriveContext.Span window
  ) {
    return new Run(contactId, warnings, problems, window).events();
  }

  /**
   * One request's sources (Time Drive Source records, in sequence) and
   * their providers. Each source is read as rows at most once, and only when
   * something needs its rows: it can't be counted, the days asked for are
   * quiet, or a later provider reads its prior events.
   */
  private class Run {
    Id recordId;
    String parentObject;
    List<String> warnings;
    List<Problem> problems;
    TimeDriveContext.Span window;
    List<Time_Drive_Source__mdt> sources;
    List<TimeDriveRowProvider> providers = new List<TimeDriveRowProvider>();
    Boolean counting = false;
    // What the summary counts per: day, week or month.
    String unit = TimeDriveContext.UNIT_DAY;
    // Sources whose count failed this time, read as rows instead.
    Set<Integer> uncounted = new Set<Integer>();
    // The sources the summary counted (DeveloperNames), in order.
    List<String> countedNames = new List<String>();
    // The days being read that follow one another in the summary: each run is
    // read as one span of dates (null: one range per period).
    List<List<String>> runs;
    // The summary's filters: a source they hide isn't counted (or read) at
    // all. Set only for the summary; the days apply the filters themselves.
    Filters only;
    // Each source's events over the whole window, once read.
    Map<Integer, List<EngagementEvent>> rowsBySource = new Map<Integer, List<EngagementEvent>>();

    // A person account's own Contact, when the page is one.
    Id personContactId;

    Run(Id recordId, List<String> warnings, List<Problem> problems, TimeDriveContext.Span window) {
      this.recordId = recordId;
      this.parentObject = TimeDriveConfig.describeType(recordId.getSObjectType()).getName();
      // A person account has its own sources (Person Account in setup).
      personContactId = personContactOf(recordId);
      if (personContactId != null) {
        parentObject = PERSON_ACCOUNT;
      }
      this.warnings = warnings;
      this.problems = problems;
      this.window = window;
      sources = TimeDriveConfig.sources(parentObject);
      for (Time_Drive_Source__mdt config : sources) {
        providers.add(TimeDriveConfig.providerFor(config, warnings));
      }
    }

    // Whether any of the lens's Salesforce sources has an item in the window
    // (see TimeDriveSoqlProvider.anyOf). Data 360 and Apex sources aren't asked.
    Boolean anyIn(String lens) {
      List<TimeDriveContext> asked = new List<TimeDriveContext>();
      for (Integer i = 0; i < sources.size(); i++) {
        if (providers[i] instanceof TimeDriveSoqlProvider && TimeDriveConfig.lensesOf(sources[i]).contains(lens)) {
          asked.add(context(i));
        }
      }
      return TimeDriveSoqlProvider.anyOf(asked);
    }

    // Every source's events, newest first.
    List<EngagementEvent> events() {
      List<EngagementEvent> all = new List<EngagementEvent>();
      for (Integer i = 0; i < sources.size(); i++) {
        all.addAll(rows(i));
      }
      all.sort();
      return all;
    }

    // What the summary adds up: per period for sources that can count, one
    // per event for the rest.
    List<Tally> tallies() {
      counting = true;
      unit = unitFor();
      List<Tally> result = new List<Tally>();
      for (Integer i = 0; i < sources.size(); i++) {
        if (only != null && !only.shows(TimeDriveConfig.lensKey(sources[i]), sources[i].Event_Type__c)) {
          continue;
        }
        List<TimeDriveContext.DayCount> counted = counts(i) ? count(i, context(i), unit) : null;
        if (counted != null) {
          countedNames.add(sources[i].DeveloperName);
          if (!counted.isEmpty()) {
            Tally same = new Tally(sources[i], null, 0);
            same.source = sources[i].DeveloperName;
            for (TimeDriveContext.DayCount c : counted) {
              result.add(new Tally(same, c.dayKey, c.count));
            }
          }
          continue;
        }
        for (EngagementEvent e : rows(i)) {
          result.add(new Tally(e, periodOf(e)));
        }
      }
      return result;
    }

    /**
     * The finest unit (day, week, month) whose counts fit COUNT_ROWS query
     * rows: each counted Salesforce source can return a row per period of
     * the window. Data 360 counts use no query rows. Worked out from the
     * window and the sources alone, so the summary and its pages agree.
     * @return the unit of each count: day, week or month
     */
    String unitFor() {
      if (!counting) {
        return TimeDriveContext.UNIT_DAY;
      }
      Integer queried = 0;
      for (Integer i = 0; i < sources.size(); i++) {
        if (counts(i) && !(providers[i] instanceof TimeDriveData360Provider)) {
          queried++;
        }
      }
      for (String candidate : new List<String>{ TimeDriveContext.UNIT_DAY, TimeDriveContext.UNIT_WEEK }) {
        if (queried * TimeDriveContext.periods(window.since.date(), window.until.date(), candidate) <= COUNT_ROWS) {
          return candidate;
        }
      }
      return TimeDriveContext.UNIT_MONTH;
    }

    // A source's counts in the busy periods as the summary gave them (a
    // period each, none for a source with nothing in it).
    List<TimeDriveContext.DayCount> knownCounts(
      String sourceName,
      Set<String> busyKeys,
      Map<String, Map<String, Integer>> busyCounts
    ) {
      List<TimeDriveContext.DayCount> out = new List<TimeDriveContext.DayCount>();
      for (String key : busyKeys) {
        Map<String, Integer> bySource = busyCounts.get(key);
        Integer n = bySource == null ? null : bySource.get(sourceName);
        if (n != null && n > 0) {
          TimeDriveContext.DayCount c = new TimeDriveContext.DayCount(key, null, n);
          c.whole = true;
          out.add(c);
        }
      }
      return out;
    }

    // The period (day, week or month key) an event falls in.
    String periodOf(EngagementEvent e) {
      return TimeDriveContext.periodKey(Date.valueOf(e.dayKey), unit);
    }

    // A period (its key, yyyy-MM-dd) as the part of the window it covers;
    // null outside it.
    TimeDriveContext.Span periodIn(String key) {
      Date first = Date.valueOf(key);
      Datetime since = Datetime.newInstance(first, Time.newInstance(0, 0, 0, 0));
      Datetime until = Datetime.newInstance(TimeDriveContext.periodEnd(first, unit), Time.newInstance(23, 59, 59, 999));
      since = since < window.since ? window.since : since;
      until = until > window.until ? window.until : until;
      return since > until ? null : new TimeDriveContext.Span(since, until);
    }

    /**
     * Groups a source's counts, one for each day, by the period each falls in. Days outside the
     * wanted periods are dropped; each kept count is added to that period's total.
     * @param found The source's counts by day.
     * @param wanted The period keys asked for.
     * @param totals The running total of items for each period, added to here.
     * @return The counts of each wanted period.
     */
    private Map<String, List<TimeDriveContext.DayCount>> groupByPeriod(
      List<TimeDriveContext.DayCount> found,
      Set<String> wanted,
      Map<String, Integer> totals
    ) {
      Map<String, List<TimeDriveContext.DayCount>> byPeriod = new Map<String, List<TimeDriveContext.DayCount>>();
      for (TimeDriveContext.DayCount c : found) {
        String key = TimeDriveContext.periodKey(Date.valueOf(c.dayKey), unit);
        if (!wanted.contains(key)) {
          continue;
        }
        List<TimeDriveContext.DayCount> inPeriod = byPeriod.get(key);
        if (inPeriod == null) {
          inPeriod = new List<TimeDriveContext.DayCount>();
          byPeriod.put(key, inPeriod);
        }
        inPeriod.add(c);
        totals.put(key, (totals.containsKey(key) ? totals.get(key) : 0) + c.count);
      }
      return byPeriod;
    }

    // The events of the wanted periods (keys from the summary), busy ones
    // grouped. Counted sources are counted inside those periods (per hour of
    // each day, or per day of each week or month) and read only where quiet.
    // `busyHint`: the periods the summary already found busy (over the
    // threshold), from the component; only they are counted, the rest read
    // as rows straight away (no count query for a quiet page). Null: count
    // every period, as without a summary.
    List<EngagementEvent> days(
      Set<String> wanted,
      Filters filters,
      Integer threshold,
      Set<String> busyHint,
      Set<String> emptySources,
      Map<String, Map<String, Integer>> busyCounts,
      List<List<String>> runs
    ) {
      this.runs = runs;
      counting = true;
      unit = unitFor();
      String grain = unit == TimeDriveContext.UNIT_DAY ? TimeDriveContext.UNIT_HOUR : TimeDriveContext.UNIT_DAY;
      List<String> keys = new List<String>(wanted);
      keys.sort();
      List<TimeDriveContext.Span> periods = new List<TimeDriveContext.Span>();
      for (String key : keys) {
        TimeDriveContext.Span w = periodIn(key);
        if (w != null) {
          periods.add(w);
        }
      }
      List<TimeDriveContext.Span> toCount = periods;
      if (busyHint != null) {
        toCount = new List<TimeDriveContext.Span>();
        for (String key : keys) {
          TimeDriveContext.Span w = busyHint.contains(key) ? periodIn(key) : null;
          if (w != null) {
            toCount.add(w);
          }
        }
      }
      List<EngagementEvent> page = new List<EngagementEvent>();
      Map<String, Integer> totals = new Map<String, Integer>();

      Map<Integer, TimeDriveContext> contexts = new Map<Integer, TimeDriveContext>();
      Map<Integer, Map<String, List<TimeDriveContext.DayCount>>> counted = new Map<Integer, Map<String, List<TimeDriveContext.DayCount>>>();
      for (Integer i = 0; i < sources.size(); i++) {
        if (counts(i)) {
          if (periods.isEmpty() || !filters.shows(TimeDriveConfig.lensKey(sources[i]), sources[i].Event_Type__c)) {
            continue;
          }
          // The summary found nothing of this source in these periods.
          if (emptySources != null && emptySources.contains(sources[i].DeveloperName)) {
            continue;
          }
          TimeDriveContext context = context(i);
          // Nothing busy on the page: no count, its rows are read below.
          if (toCount.isEmpty()) {
            contexts.put(i, context);
            counted.put(i, new Map<String, List<TimeDriveContext.DayCount>>());
            continue;
          }
          context.ranges = toCount;
          List<TimeDriveContext.DayCount> found = busyCounts == null ||
            busyHint == null
            ? count(i, context, grain)
            : knownCounts(sources[i].DeveloperName, busyHint, busyCounts);
          if (found != null) {
            contexts.put(i, context);
            counted.put(i, groupByPeriod(found, wanted, totals));
            continue;
          }
        }
        // Not counted (or the count failed): its rows in these periods only
        // (or the whole window's, when the summary already read them).
        for (EngagementEvent e : rowsIn(i, keys)) {
          String key = periodOf(e);
          if (wanted.contains(key) && filters.shows(e)) {
            e.dayKey = key;
            page.add(e);
            totals.put(key, (totals.containsKey(key) ? totals.get(key) : 0) + 1);
          }
        }
      }
      Set<String> busy = new Set<String>();
      for (String key : totals.keySet()) {
        if (totals.get(key) > threshold) {
          busy.add(key);
        }
      }

      // Busy periods from the counts; quiet ones' rows, read for those only:
      // each its own span (one query, the spans OR'd), so nothing between
      // them is read, whichever periods are asked for.
      // A period not counted (the summary found it quiet) is read as rows.
      for (Integer i : counted.keySet()) {
        Map<String, List<TimeDriveContext.DayCount>> byPeriod = counted.get(i);
        List<TimeDriveContext.Span> quiet = new List<TimeDriveContext.Span>();
        Set<String> readKeys = new Set<String>();
        for (String key : keys) {
          Boolean uncounted = busyHint != null && !busyHint.contains(key);
          if (!byPeriod.containsKey(key) && !uncounted) {
            continue;
          }
          if (byPeriod.containsKey(key) && busy.contains(key)) {
            page.add(grouped(contexts.get(i), key, byPeriod.get(key), grain));
          } else {
            TimeDriveContext.Span w = periodIn(key);
            if (w != null) {
              quiet.add(w);
              readKeys.add(key);
            }
          }
        }
        if (quiet.isEmpty()) {
          continue;
        }
        page.addAll(readInFull(i, readKeys, grain));
      }
      List<EngagementEvent> result = groupBusyDays(page, threshold);
      Map<String, Boolean> pageableTypes = new Map<String, Boolean>();
      for (EngagementEvent e : result) {
        if (e.grouped) {
          if (!pageableTypes.containsKey(e.type)) {
            pageableTypes.put(e.type, pageable(e.type));
          }
          e.pageable = pageableTypes.get(e.type);
        }
      }
      return result;
    }

    // Source i can be read a page at a time: a Salesforce source, keyed by
    // its records' Ids.
    Boolean pages(Integer i) {
      return providers[i] instanceof TimeDriveSoqlProvider && context(i).idField() == 'Id';
    }

    // Every source of the type pages (and there is one).
    Boolean pageable(String type) {
      Boolean found = false;
      for (Integer i = 0; i < sources.size(); i++) {
        if (sources[i].Event_Type__c == type) {
          if (!pages(i)) {
            return false;
          }
          found = true;
        }
      }
      return found;
    }

    /**
     * A page of the type's items in the window, newest first. Each source
     * reads one more than the page after its own cursor (its last item
     * shown); the reads are merged newest first, each source's in its own
     * order, so what's shown of each is always the start of what's left.
     * @param type the event type whose items are listed
     * @param size how many items to return
     * @param cursors each source's cursor, by source name, where its last page ended
     * @return one page of items with a cursor for the next
     */
    GroupPage page(String type, Integer size, Map<String, List<String>> cursors) {
      GroupPage out = new GroupPage();
      List<Integer> mine = new List<Integer>();
      List<List<EngagementEvent>> reads = new List<List<EngagementEvent>>();
      for (Integer i = 0; i < sources.size(); i++) {
        if (sources[i].Event_Type__c != type || !pages(i)) {
          continue;
        }
        String name = sources[i].DeveloperName;
        List<EngagementEvent> read = new List<EngagementEvent>();
        // A source already read to its end has a null cursor.
        if (!cursors.containsKey(name) || cursors.get(name) != null) {
          TimeDriveContext context = context(i);
          context.ranges = new List<TimeDriveContext.Span>{ window };
          context.pageSize = size + 1;
          List<String> after = cursors.get(name);
          if (after != null) {
            context.pageAt = Datetime.newInstance(Long.valueOf(after[0]));
            context.pageId = Id.valueOf(after[1]);
          }
          read = read(i, context);
        }
        mine.add(i);
        reads.add(read);
      }
      List<Integer> next = new List<Integer>();
      for (Integer k = 0; k < reads.size(); k++) {
        next.add(0);
      }
      while (out.items.size() < size) {
        Integer best = -1;
        for (Integer k = 0; k < reads.size(); k++) {
          if (
            next[k] < reads[k].size() &&
            (best == -1 ||
            reads[k][next[k]].occurredAt > reads[best][next[best]].occurredAt)
          ) {
            best = k;
          }
        }
        if (best == -1) {
          break;
        }
        out.items.add(reads[best][next[best]]);
        next[best] = next[best] + 1;
      }
      Map<String, List<String>> after = new Map<String, List<String>>(cursors);
      for (Integer k = 0; k < reads.size(); k++) {
        Time_Drive_Source__mdt s = sources[mine[k]];
        Boolean left = next[k] < reads[k].size();
        if (!left) {
          after.put(s.DeveloperName, null);
        } else if (next[k] > 0) {
          EngagementEvent last = reads[k][next[k] - 1];
          after.put(
            s.DeveloperName,
            new List<String>{ String.valueOf(last.occurredAt.getTime()), last.id.removeEnd('-' + s.DeveloperName) }
          );
        }
        out.more = out.more || left;
      }
      out.cursor = JSON.serialize(after);
      out.problems = problems;
      if (!mine.isEmpty()) {
        Time_Drive_Source__mdt first = sources[mine[0]];
        out.label = TimeDriveConfig.legendLabel(first);
        out.labelName = TimeDriveConfig.legendLabelName(first);
        out.icon = first.Icon__c;
        out.dateOnly = true;
        for (Integer i : mine) {
          out.dateOnly = out.dateOnly && dateOnly(sources[i]);
        }
      }
      return out;
    }

    // The source's Date Field holds dates, not date/times.
    Boolean dateOnly(Time_Drive_Source__mdt s) {
      try {
        return TimeDriveConfig.fieldDescribe(s.Object_Name__c, s.Date_Field__c).getType() == Schema.DisplayType.DATE;
      } catch (Exception e) {
        return false;
      }
    }

    /**
     * A source's items in some periods, every one of them: a read can't
     * return more than the source's cap (Max Records, and Data 360's 2,000),
     * so a read that comes back full is read again from its oldest period
     * on (newest first, the periods after that one are complete), a few
     * times at most. A single period with more than the cap (a summary out
     * of date: it was busy) is counted instead, as one grouped row.
     * @param i the index of the source in the run's list
     * @param periodKeys the period keys to read
     * @param grain the unit of the keys (day, week or month)
     * @return every event in those periods, or grouped rows for periods over the cap
     */
    List<EngagementEvent> readInFull(Integer i, Set<String> periodKeys, String grain) {
      List<EngagementEvent> out = new List<EngagementEvent>();
      List<String> pending = new List<String>(periodKeys);
      pending.sort();
      // Periods with more than the cap on their own: counted, not read.
      List<String> overCap = new List<String>();
      Integer cap = rowCap(i);
      for (Integer round = 0; round < MAX_READS && !pending.isEmpty(); round++) {
        Set<String> wantedNow = new Set<String>(pending);
        TimeDriveContext context = context(i);
        context.ranges = windowsFor(pending);
        List<EngagementEvent> read = new List<EngagementEvent>();
        String oldest;
        for (EngagementEvent e : read(i, context)) {
          String key = periodOf(e);
          if (wantedNow.contains(key)) {
            e.dayKey = key;
            read.add(e);
            oldest = oldest == null || key < oldest ? key : oldest;
          }
        }
        if (read.size() < cap) {
          // Under the cap: these periods are complete (any set aside as
          // over the cap are still counted, below).
          out.addAll(read);
          pending = new List<String>();
          break;
        }
        // Full: the periods after the oldest one read are complete.
        Boolean progressed = false;
        for (EngagementEvent e : read) {
          if (e.dayKey > oldest) {
            out.add(e);
            progressed = true;
          }
        }
        // Every row from one period (the newest left): it has the cap or more
        // on its own, so it's counted, and the next read starts below it.
        // Reading it again would only return the same rows.
        if (!progressed) {
          overCap.add(oldest);
        }
        List<String> rest = new List<String>();
        for (String key : pending) {
          if (key < oldest || (progressed && key == oldest)) {
            rest.add(key);
          }
        }
        pending = rest;
      }
      // Out of reads: what's left is counted too.
      overCap.addAll(pending);
      if (!overCap.isEmpty()) {
        out.addAll(countedRows(i, overCap, grain));
      }
      return out;
    }

    // The periods as spans: a run of periods that follow one another in the
    // summary is one span (a query with one range reads far faster than one
    // with a range per day, and nothing with items lies between them); any
    // other period is a span of its own.
    List<TimeDriveContext.Span> windowsFor(List<String> periodKeys) {
      List<TimeDriveContext.Span> out = new List<TimeDriveContext.Span>();
      Set<String> pending = new Set<String>(periodKeys);
      Set<String> placed = new Set<String>();
      for (List<String> run : runs ?? new List<List<String>>()) {
        TimeDriveContext.Span span;
        for (String key : run) {
          TimeDriveContext.Span w = pending.contains(key) ? periodIn(key) : null;
          if (w == null) {
            // A period not wanted now ends the span.
            if (span != null) {
              out.add(span);
              span = null;
            }
            continue;
          }
          placed.add(key);
          if (span == null) {
            span = w;
          } else {
            span = new TimeDriveContext.Span(
              span.since < w.since ? span.since : w.since,
              span.until > w.until ? span.until : w.until
            );
          }
        }
        if (span != null) {
          out.add(span);
        }
      }
      for (String key : periodKeys) {
        if (!placed.contains(key)) {
          TimeDriveContext.Span w = periodIn(key);
          if (w != null) {
            out.add(w);
          }
        }
      }
      return out;
    }

    // Periods too full to read, as grouped rows from their counts.
    List<EngagementEvent> countedRows(Integer i, List<String> periodKeys, String grain) {
      List<EngagementEvent> out = new List<EngagementEvent>();
      if (!counts(i)) {
        return out;
      }
      TimeDriveContext context = context(i);
      context.ranges = windowsFor(periodKeys);
      List<TimeDriveContext.DayCount> found = count(i, context, grain);
      if (found == null) {
        return out;
      }
      Set<String> wanted = new Set<String>(periodKeys);
      Map<String, List<TimeDriveContext.DayCount>> byPeriod = new Map<String, List<TimeDriveContext.DayCount>>();
      for (TimeDriveContext.DayCount c : found) {
        String key = TimeDriveContext.periodKey(Date.valueOf(c.dayKey), unit);
        if (!wanted.contains(key)) {
          continue;
        }
        if (!byPeriod.containsKey(key)) {
          byPeriod.put(key, new List<TimeDriveContext.DayCount>());
        }
        byPeriod.get(key).add(c);
      }
      for (String key : byPeriod.keySet()) {
        out.add(grouped(context, key, byPeriod.get(key), grain));
      }
      return out;
    }

    // The most rows one read of source i returns.
    Integer rowCap(Integer i) {
      Integer cap = context(i).maxRecords();
      return providers[i] instanceof TimeDriveData360Provider
        ? Math.min(cap, TimeDriveData360Provider.MAX_DMO_ROWS)
        : cap;
    }

    // A counted source's busy period as one grouped row, from the start of
    // its first hour (or day) to the end of its last; date-only fields
    // counted by hour sit at midday.
    EngagementEvent grouped(
      TimeDriveContext context,
      String key,
      List<TimeDriveContext.DayCount> counts,
      String grain
    ) {
      Time_Drive_Source__mdt s = context.source;
      Integer total = 0;
      Datetime first;
      Datetime last;
      Boolean whole = false;
      for (TimeDriveContext.DayCount c : counts) {
        total += c.count;
        Date day = Date.valueOf(c.dayKey);
        if (c.whole == true) {
          // Counted for the period as a whole: it spans all of it.
          whole = true;
          Datetime periodFrom = Datetime.newInstance(day, Time.newInstance(0, 0, 0, 0));
          Datetime periodTo = Datetime.newInstance(
            TimeDriveContext.periodEnd(day, unit),
            Time.newInstance(23, 59, 59, 0)
          );
          first = first == null || periodFrom < first ? periodFrom : first;
          last = last == null || periodTo > last ? periodTo : last;
          continue;
        }
        Datetime fromAt = c.hour != null
          ? Datetime.newInstance(day, Time.newInstance(c.hour, 0, 0, 0))
          : Datetime.newInstance(day, Time.newInstance(grain == TimeDriveContext.UNIT_HOUR ? 12 : 0, 0, 0, 0));
        Datetime toAt = c.hour != null
          ? Datetime.newInstance(day, Time.newInstance(c.hour, 59, 59, 0))
          : (grain == TimeDriveContext.UNIT_HOUR ? fromAt : Datetime.newInstance(day, Time.newInstance(23, 59, 59, 0)));
        first = first == null || fromAt < first ? fromAt : first;
        last = last == null || toAt > last ? toAt : last;
      }
      first = first < window.since ? window.since : first;
      last = last > window.until ? window.until : last;
      EngagementEvent g = new EngagementEvent(
          'group-' + key + '-' + s.DeveloperName,
          s.Event_Type__c,
          TimeDriveConfig.lensKey(s),
          null,
          null,
          last
        )
        .source(context.sourceObject, context.sourceLabel);
      g.grouped = true;
      g.allDay = whole;
      g.groupCount = total;
      g.firstAt = first;
      g.dayKey = key;
      return context.styled(g);
    }

    // Counted this time: counting is allowed and the provider can, and
    // hasn't failed to.
    Boolean counts(Integer i) {
      return counting && providers[i] instanceof TimeDriveCountProvider && !uncounted.contains(i);
    }

    TimeDriveContext context(Integer i) {
      TimeDriveContext context = new TimeDriveContext(recordId, parentObject, window.since, sources[i], null, warnings);
      context.problems = problems;
      context.personContactId = personContactId;
      context.until = window.until;
      context.priorLoader = new Prior(this, i);
      return context;
    }

    // A source's counts, or null when they can't be had: it's read as rows
    // instead (which says what's wrong, if that fails too).
    List<TimeDriveContext.DayCount> count(Integer i, TimeDriveContext context, String grain) {
      try {
        List<TimeDriveContext.DayCount> found = ((TimeDriveCountProvider) providers[i]).countDays(context, grain);
        if (found == null) {
          // An Apex source that doesn't count: read as rows.
          uncounted.add(i);
          return null;
        }
        return found;
      } catch (Exception e) {
        uncounted.add(i);
        return null;
      }
    }

    // A source's events over the whole window, read once.
    List<EngagementEvent> rows(Integer i) {
      if (!rowsBySource.containsKey(i)) {
        TimeDriveContext context = context(i);
        List<EngagementEvent> events = read(i, context);
        // Read for itself (not only as another source's prior events): say
        // when Max Records cut it short.
        if (!counts(i) && providers[i] != null && events.size() >= context.maxRecords()) {
          context.warn(
            String.format(
              Label.Time_Drive_Server_Max_Records,
              new List<String>{ sources[i].Label, String.valueOf(context.maxRecords()) }
            )
          );
        }
        rowsBySource.put(i, events);
      }
      return rowsBySource.get(i);
    }

    // A source's rows in some periods: those already read over the whole
    // window (by the summary, in this request), else a read of just those
    // periods, not of the window: a page of days shouldn't cost a full read.
    List<EngagementEvent> rowsIn(Integer i, List<String> periodKeys) {
      if (rowsBySource.containsKey(i)) {
        return rowsBySource.get(i);
      }
      TimeDriveContext context = context(i);
      context.ranges = windowsFor(periodKeys);
      if (context.ranges.isEmpty()) {
        return new List<EngagementEvent>();
      }
      List<EngagementEvent> events = read(i, context);
      if (providers[i] != null && events.size() >= context.maxRecords()) {
        context.warn(
          String.format(
            Label.Time_Drive_Server_Max_Records,
            new List<String>{ sources[i].Label, String.valueOf(context.maxRecords()) }
          )
        );
      }
      return events;
    }

    // Whatever a provider returns, only what's inside the window plots.
    List<EngagementEvent> read(Integer i, TimeDriveContext context) {
      List<EngagementEvent> events = new List<EngagementEvent>();
      if (providers[i] == null) {
        return events;
      }
      try {
        events = window.within(TimeDrivePlotter.run(providers[i], context));
      } catch (Exception e) {
        context.fail(sources[i].Label, e);
      }
      for (EngagementEvent e : events) {
        e.dayKey = e.occurredAt.format('yyyy-MM-dd');
      }
      return events;
    }

    // The events of every source before source i.
    List<EngagementEvent> before(Integer i) {
      List<EngagementEvent> prior = new List<EngagementEvent>();
      for (Integer j = 0; j < i; j++) {
        prior.addAll(rows(j));
      }
      return prior;
    }
  }

  // A provider's prior events, read when it first asks for them.
  private class Prior implements TimeDriveContext.PriorEvents {
    Run run;
    Integer index;

    Prior(Run run, Integer index) {
      this.run = run;
      this.index = index;
    }

    /**
     * Loads the events of the sources before this one.
     * @return the earlier events
     */
    public List<EngagementEvent> load() {
      return run.before(index);
    }
  }

  // What the summary adds up: a counted source's items on one day, or one
  // event read as a row.
  private class Tally {
    String dayKey;
    String type;
    String category;
    String typeLabel;
    String typeLabelName;
    String icon;
    String iconColour;
    Integer count;
    EngagementEvent event;
    // The source's DeveloperName, for a source that was counted.
    String source;

    Tally(Time_Drive_Source__mdt s, String dayKey, Integer count) {
      this.dayKey = dayKey;
      this.count = count;
      type = s.Event_Type__c;
      category = TimeDriveConfig.lensKey(s);
      typeLabel = TimeDriveConfig.legendLabel(s);
      typeLabelName = TimeDriveConfig.legendLabelName(s);
      icon = String.isBlank(s.Icon__c) ? null : s.Icon__c;
      iconColour = String.isBlank(s.Icon_Colour__c) ? null : s.Icon_Colour__c;
    }

    // Another period of the same source: what the source says is worked out
    // once (its label reads its fields and the org's labels), not per period.
    Tally(Tally same, String dayKey, Integer count) {
      this.dayKey = dayKey;
      this.count = count;
      type = same.type;
      category = same.category;
      typeLabel = same.typeLabel;
      typeLabelName = same.typeLabelName;
      icon = same.icon;
      iconColour = same.iconColour;
      source = same.source;
    }

    Tally(EngagementEvent e, String periodKey) {
      event = e;
      dayKey = periodKey;
      count = 1;
      type = e.type;
      category = e.category;
      typeLabel = e.typeLabel;
      typeLabelName = e.typeLabelName;
      icon = e.icon;
      iconColour = e.iconColour;
    }
  }

  /**
   * The timeline's filters: view categories and hidden types, which apply
   * to a whole source, so every source that can count still counts.
   */
  private class Filters {
    Set<String> inView;
    Set<String> hidden;

    Filters(List<String> categories, List<String> hiddenTypes) {
      inView = categories == null || categories.isEmpty() ? null : new Set<String>(categories);
      hidden = hiddenTypes == null ? new Set<String>() : new Set<String>(hiddenTypes);
    }

    // A source in several lenses carries them as Sales;Service: it shows when
    // any of them is in the view. One in no lens at all is in All.
    Boolean inView(String category) {
      if (inView == null) {
        return true;
      }
      for (
        String lens : String.isBlank(category) ? new List<String>{ TimeDriveConfig.ALL_VIEW } : category.split(';')
      ) {
        if (inView.contains(lens)) {
          return true;
        }
      }
      return false;
    }

    Boolean shows(String category, String type) {
      return inView(category) && !hidden.contains(type);
    }

    Boolean shows(Tally t) {
      return t.event == null ? shows(t.category, t.type) : shows(t.event);
    }

    Boolean shows(EngagementEvent e) {
      return shows(e.category, e.type);
    }
  }

  /**
   * The kind of failure an exception is, for the user: 'access' (in user
   * mode a field or object hidden from the user reads as missing, so both
   * land here), 'busy' or 'unknown'.
   * @param e the exception to classify
   * @return access, busy or unknown
   */
  public static String kindOf(Exception e) {
    if (e instanceof NoAccessException || e instanceof System.SecurityException) {
      return 'access';
    }
    String text = String.valueOf(e.getMessage()).toLowerCase();
    for (
      String sign : new List<String>{
        'no such column',
        'inaccessible',
        'insufficient',
        'not supported',
        'invalid_field',
        'invalid type',
        'does not exist'
      }
    ) {
      if (text.contains(sign)) {
        return 'access';
      }
    }
    if (e instanceof System.LimitException || text.contains('limit') || text.contains('timed out')) {
      return 'busy';
    }
    return 'unknown';
  }

  // An unexpected failure, as the client sees it: only the kind, never the
  // message or stack trace.
  @TestVisible
  private static AuraHandledException safeFailure(Exception e) {
    String kind = kindOf(e);
    TimeDriveLog.note(null, null, kind, e);
    return coded(kind);
  }

  // The card's error for a kind of failure ("timedrive:access"): the code alone,
  // never the raw message.
  private static AuraHandledException coded(String kind) {
    String code = 'timedrive:' + kind;
    AuraHandledException failure = new AuraHandledException(code);
    failure.setMessage(code);
    return failure;
  }

  /** A source that couldn't be read, and the kind of failure. */
  public class Problem {
    @AuraEnabled
    public String source;
    @AuraEnabled
    public String kind;

    /**
     * Builds a problem.
     * @param source the name of the source
     * @param kind the kind of failure
     */
    public Problem(String source, String kind) {
      this.source = source;
      this.kind = kind;
    }
  }

  /** The events of a whole timeline with any warnings and problems. */
  public class TimelineResult {
    @AuraEnabled
    public List<EngagementEvent> events = new List<EngagementEvent>();
    // Sources that couldn't be read (no Data 360, missing DMO, no access):
    // the timeline shows what it has and says what's missing.
    @AuraEnabled
    public List<String> warnings = new List<String>();
    @AuraEnabled
    public List<Problem> problems = new List<Problem>();
  }

  /** The per-period counts of a timeline with the sources and types they came from. */
  public class TimelineSummary {
    // A period with more items than this comes back grouped: the component
    // says which periods are, so their pages count only those.
    @AuraEnabled
    public Integer groupOver = GROUP_OVER;
    // Events after the filters, and before them (to tell "no history" from
    // "filtered out").
    @AuraEnabled
    public Integer total = 0;
    @AuraEnabled
    // What the sources the filters leave in view hold (the others aren't counted).
    public Integer unfilteredTotal = 0;
    // What each of days is: a day, or a week (from 1 January: the 1st-7th,
    // 8th-14th ...) or calendar month when the window is too long to count
    // by day. Keys are the period's first day; getPageDays takes them as they are.
    @AuraEnabled
    public String unit = TimeDriveContext.UNIT_DAY;
    // Newest first.
    @AuraEnabled
    public List<DaySummary> days = new List<DaySummary>();
    // The sources that were counted (by DeveloperName): a day's `src` indexes
    // this list. A source not in it is read as rows, always.
    @AuraEnabled
    public List<String> counted = new List<String>();
    @AuraEnabled
    public List<TypeCount> types = new List<TypeCount>();
    // True when the record's page has no active sources at all.
    @AuraEnabled
    public Boolean noSources = false;
    // The page's object as people know it: Contact, Account, Person Account.
    @AuraEnabled
    public String page;
    @AuraEnabled
    public List<String> warnings = new List<String>();
    // Sources that couldn't be read (named, with the kind of failure).
    @AuraEnabled
    public List<Problem> problems = new List<Problem>();
  }

  /** The count of one period: its key and how many items each source has. */
  public class DaySummary {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public Integer count = 0;
    // The counted sources with items this period (indices into the summary's
    // `counted`), and how many each has (parallel; kept for busy periods only,
    // where they build the grouped rows without counting again).
    @AuraEnabled
    public List<Integer> src = new List<Integer>();
    @AuraEnabled
    public List<Integer> n = new List<Integer>();

    /**
     * Builds a summary for one period.
     * @param key the period's key
     */
    public DaySummary(String key) {
      this.key = key;
    }

    void add(Integer source, Integer items) {
      Integer at = src.indexOf(source);
      if (at < 0) {
        src.add(source);
        n.add(items);
      } else {
        n.set(at, n.get(at) + items);
      }
    }
  }

  /**
   * The count for one source in one busy period, handed back with the periods asked for.
   * Properties, not fields: the card's values reach a parameter only through setters.
   */
  public class BusyCount {
    @AuraEnabled
    public String key { get; set; }
    @AuraEnabled
    public String source { get; set; }
    @AuraEnabled
    public Integer count { get; set; }
  }

  /** How many items a type has. */
  public class TypeCount {
    @AuraEnabled
    public String type;
    @AuraEnabled
    public Integer count;
    // From the source's configuration, when it sets them; labelName is the
    // custom label its label comes from, if any (the card shows its own copy).
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String labelName;
    @AuraEnabled
    public String icon;
    @AuraEnabled
    public String iconColour;

    /**
     * Builds a type count.
     * @param type the event type
     * @param count how many items it has
     */
    public TypeCount(String type, Integer count) {
      this.type = type;
      this.count = count;
    }
  }

  /**
   * One timeline event. `type` drives the icon and colour in the component;
   * `category` groups types into the timeline views.
   */

  // 0.25 years -> 3 months.
  public static Integer monthsIn(Decimal years) {
    return (years * 12).round(System.RoundingMode.HALF_UP).intValue();
  }

  // The App Builder's History and Future, in years. A value not on the list
  // falls back (History to half a year, Future to none) with a warning.
  @TestVisible
  private static TimeDriveContext.Span windowFor(String historyYears, String futureYears, List<String> warnings) {
    Decimal history = String.isNotBlank(historyYears) && historyYears.trim() == '0'
      ? 0
      : yearsFrom(historyYears, 'History', warnings);
    Decimal future = yearsFrom(futureYears, 'Future', warnings);
    return new TimeDriveContext.Span(history == null ? DEFAULT_HISTORY_YEARS : history, future);
  }

  private static Decimal yearsFrom(String value, String name, List<String> warnings) {
    if (String.isBlank(value) || value.trim().equalsIgnoreCase('None')) {
      return null;
    }
    if (value.trim().equalsIgnoreCase(ONE_MONTH)) {
      return Decimal.valueOf(1).divide(12, 6);
    }
    Decimal years;
    try {
      years = Decimal.valueOf(value.trim());
    } catch (Exception e) {
      years = null;
    }
    for (Decimal allowed : RANGE_YEARS) {
      if (years != null && years == allowed) {
        return allowed;
      }
    }
    warnings.add(String.format(Label.Time_Drive_Server_Bad_Years, new List<String>{ name, String.valueOf(value) }));
    return null;
  }

  /** One item on the timeline, from a CRM record or a Data 360 row. */
  public class EngagementEvent implements Comparable {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String subtitle;
    @AuraEnabled
    public Datetime occurredAt;
    // API name of the object the event comes from, e.g. Invoice__c or
    // ssot__EmailEngagement__dlm, and a readable label for it.
    @AuraEnabled
    public String sourceObject;
    @AuraEnabled
    public String sourceLabel;
    // The Salesforce record behind a CRM event (order, review, case,
    // opportunity), for linking; null for Data 360 events.
    @AuraEnabled
    public Id recordId;
    // The day it falls on (yyyy-MM-dd, user's time zone).
    @AuraEnabled
    public String dayKey;
    // A busy day's row standing for many events of one type.
    @AuraEnabled
    public Boolean grouped = false;
    // A grouped row whose items can be listed a page at a time (View all):
    // every source of its type is a Salesforce one.
    @AuraEnabled
    public Boolean pageable = false;
    @AuraEnabled
    public Integer groupCount;
    @AuraEnabled
    public Datetime firstAt;
    // From the source's configuration: SLDS icon and its background colour.
    @AuraEnabled
    public String icon;
    @AuraEnabled
    public String iconColour;
    // The type's plural label from configuration ("Case updates"), and the
    // custom label it comes from, if any (the card shows its own copy).
    @AuraEnabled
    public String typeLabel;
    @AuraEnabled
    public String typeLabelName;
    @AuraEnabled
    public List<Detail> details = new List<Detail>();
    // Email Messages only (see TimeDriveEmails): opened, unopened or
    // bounced, and when it was last opened.
    // An all-day event: the timeline says All-Day instead of a time.
    @AuraEnabled
    public Boolean allDay = false;
    // Dated by a Date field (a Task's Activity Date): it has a day but no time,
    // so the timeline shows none and puts it first in its day.
    @AuraEnabled
    public Boolean dateOnly = false;
    @AuraEnabled
    public String emailState;
    // Email Messages: who it went to (the first To recipient, by name where
    // Salesforce knows it) and how many others: the card says "Sent to: ..."
    // in its own words; subtitle has the same in Apex's.
    @AuraEnabled
    public String sentTo;
    @AuraEnabled
    public Integer sentToOthers;
    // The record's object, in the user's language ("Event"), for the delete
    // question; set with the rights (see markRights).
    @AuraEnabled
    public String objectLabel;
    // What the user may do with the record behind the item (see markRights).
    @AuraEnabled
    public Boolean canEdit = false;
    @AuraEnabled
    public Boolean canDelete = false;
    // Small icons for what a field's value says about the item (high
    // priority, a record type), from the source's highlights.
    @AuraEnabled
    public List<Flag> flags;
    @AuraEnabled
    public Datetime emailOpenedAt;

    /**
     * Builds an event.
     * @param id the event's Id
     * @param type the event type
     * @param category the event's category
     * @param title the title shown
     * @param subtitle the subtitle shown
     * @param occurredAt when the event happened
     */
    public EngagementEvent(
      String id,
      String type,
      String category,
      String title,
      String subtitle,
      Datetime occurredAt
    ) {
      this.id = id;
      this.type = type;
      this.category = category;
      this.title = title;
      this.subtitle = subtitle;
      this.occurredAt = occurredAt;
    }

    /**
     * Sets the Id of the record the event stands for.
     * @param recordId the record's Id
     * @return this event
     */
    public EngagementEvent record(Id recordId) {
      this.recordId = recordId;

      return this;
    }

    /**
     * Sets where the event says it comes from.
     * @param sourceObject the source's object API name
     * @param sourceLabel the source's label
     * @return this event
     */
    public EngagementEvent source(String sourceObject, String sourceLabel) {
      this.sourceObject = sourceObject;
      this.sourceLabel = sourceLabel;
      return this;
    }

    /**
     * Adds a detail line, unless the value is empty.
     * @param label the detail's label
     * @param value the detail's value
     * @return this event
     */
    public EngagementEvent detail(String label, Object value) {
      if (value != null && String.valueOf(value) != '') {
        details.add(new Detail(label, String.valueOf(value)));
      }
      return this;
    }

    /**
     * Adds a detail already built (an amount, say), unless it has nothing to show.
     * @param d the detail
     * @return this event
     */
    public EngagementEvent detail(Detail d) {
      if (d != null && String.isNotBlank(d.value)) {
        details.add(d);
      }
      return this;
    }

    /**
     * Orders events newest first.
     * @param other the event to compare with
     * @return a negative number when this event is newer
     */
    public Integer compareTo(Object other) {
      Datetime theirs = ((EngagementEvent) other).occurredAt;
      if (occurredAt == theirs) {
        return 0;
      }
      if (occurredAt == null) {
        return 1;
      }
      if (theirs == null) {
        return -1;
      }
      return occurredAt > theirs ? -1 : 1;
    }
  }

  /** A labelled value shown in an opened event. */
  public class Detail {
    @AuraEnabled
    public String label;
    // The words to show; for a number, the user's locale's (the components
    // format amount and currencyCode, when there, in the user's own way).
    @AuraEnabled
    public String value;
    @AuraEnabled
    public Decimal amount;
    // The amount's currency (ISO code), when it's money.
    @AuraEnabled
    public String currencyCode;
    // The record the value names (an Account's name, a task's Related To),
    // which the card links to; null when there's none to open.
    @AuraEnabled
    public Id recordId;

    /**
     * Builds a detail.
     * @param label the detail's label
     * @param value the detail's value
     */
    public Detail(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }
}
