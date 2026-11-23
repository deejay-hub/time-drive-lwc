/**
 * Real digital engagement from Data 360: rows of one engagement data model
 * object (DMO) per Time Drive Source record of Kind Data 360, for every
 * Individual linked to the Contact's unified profile. TimeDrivePlotter
 * turns them into events like any other source.
 *
 * How the Contact is found in Data 360:
 *   1. The Sales Cloud connector maps Contact to Individual, so the Contact Id
 *      is an Individual Id (ssot__Individual__dlm.ssot__Id__c).
 *   2. Identity resolution links that Individual to a Unified Individual. The
 *      identity link DMO (Time Drive Setting, Default; else the ruleset's
 *      UnifiedLinkssotIndividual...__dlm) gives the Unified Id and every other
 *      source Individual (web, app, Marketing Cloud subscriber) merged into
 *      the same person.
 *   3. The source's DMO is queried by its Individual Field IN those Ids: the
 *      Unified Id, for DMOs keyed by the unified profile, and the source
 *      Individuals', for DMOs keyed by those.
 *
 *
 * Queries are dynamic so this class deploys to orgs without Data 360; a DMO
 * that doesn't exist, isn't mapped or isn't readable adds a warning instead.
 */
// The branching follows the platform's cases and the plot's rules; splitting it up would only scatter them.
// Size, parameter lists and field counts follow the platform's entry points, its cases and the data the components exchange;
// splitting them up would only scatter what belongs together.
// Namespace accessible: the Data 360 package (the same namespace) implements SqlRunner and Catalog.
@NamespaceAccessible
@SuppressWarnings('PMD.CyclomaticComplexity, PMD.CognitiveComplexity, PMD.ExcessiveParameterList, PMD.NcssCount')
public with sharing class TimeDriveData360Provider implements TimeDriveRowProvider, TimeDriveCountProvider {
  // A DMO query returning more rows than this fails ("too many rows for
  // direct assignment"), whatever the source's Max Records.
  public static final Integer MAX_DMO_ROWS = 2000;
  // Names that go into SQL as they are: letters, digits and underscores.
  private static final Pattern PLAIN_NAME = Pattern.compile('[A-Za-z][A-Za-z0-9_]*');
  // Runs the counts' SQL; deployed (force-app-data360) only to orgs with
  // Data 360, as ConnectApi.CdpQuery doesn't compile without it.
  private static final String SQL_RUNNER_CLASS = 'TimeDriveData360SqlRunner';

  @TestVisible
  private static Time_Drive_Setting__mdt testSetting;
  // Tests stand in for Data 360's query API here.
  @TestVisible
  private static SqlRunner sqlRunner;

  // Identity resolution's link DMOs are named for their ruleset.
  private static final Pattern RULESET_LINK = Pattern.compile('(?i)UnifiedLinkssotIndividual[A-Za-z0-9_]*__dlm');
  // Tests stand in for Data 360's list of DMOs here.
  @TestVisible
  private static List<String> testDmoNames;
  @TestVisible
  private static Set<String> testProfileDmoNames;

  // Individual Ids per Contact and data space, worked out once a request for
  // all the DMO sources (and kept 15 minutes, see TimeDriveCache).
  private static Map<String, Set<String>> individualIdsByRecord = new Map<String, Set<String>>();
  // The org's own model, as passed in by getRows and countDays.
  private static Map<String, Schema.SObjectType> realModel;

  /**
   * Reads the source's Data 360 rows for the context's window.
   *
   * @param context the request context
   * @return the rows read
   */
  public List<TimeDriveRow> getRows(TimeDriveContext context) {
    // Empty on purpose: objects are looked up by name (see objectIn), not by
    // reading the org's whole global describe.
    realModel = new Map<String, Schema.SObjectType>();
    return getRows(context, realModel);
  }

  // The org's data model is passed in so tests can stand in for Data 360.
  @TestVisible
  private List<TimeDriveRow> getRows(TimeDriveContext context, Map<String, Schema.SObjectType> objects) {
    List<TimeDriveRow> rows = new List<TimeDriveRow>();
    Time_Drive_Source__mdt s = context.source;
    if (objectIn(objects, 'ssot__Individual__dlm') == null) {
      context.warn(Label.Time_Drive_Server_Data360_Missing);
      return rows;
    }
    Schema.SObjectType dmo = objectIn(objects, s.Object_Name__c);
    if (dmo == null) {
      context.warn(String.format(Label.Time_Drive_Server_Dmo_Missing, new List<String>{ s.Label, s.Object_Name__c }));
      return rows;
    }
    Schema.DescribeSObjectResult describe = TimeDriveConfig.describeType(dmo);
    Map<String, Schema.SObjectField> dmoFields = TimeDriveConfig.fieldMap(describe.getName());
    context.sourceObject = s.Object_Name__c;
    context.sourceLabel = 'Data 360' + TimeDrivePlotter.SEPARATOR + describe.getLabel();
    s = fitIdField(context, dmoFields);

    String individualField = String.isBlank(s.Individual_Field__c) ? 'ssot__IndividualId__c' : s.Individual_Field__c;
    String dateField = context.dateField();

    Set<String> fields = new Set<String>{ context.idField(), dateField };
    fields.addAll(TimeDrivePlotter.tokens(s.Title__c));
    fields.addAll(TimeDrivePlotter.tokens(s.Subtitle__c));
    for (String extra : new List<String>{ s.Record_Id_Field__c }) {
      fields.add(extra);
    }
    for (Time_Drive_Detail_Field__mdt d : context.detailFields()) {
      fields.add(d.Field__c);
    }

    List<TimeDriveContext.Span> spans = context.spans();
    if (spans.isEmpty()) {
      return rows;
    }
    Map<String, Object> binds = new Map<String, Object>{
      'individualIds' => new List<String>(individualIdsFor(context.contactId(), objects, context))
    };
    // Only the spans asked for (a page's quiet days), not the whole window,
    // so Max Records never cuts off days further back.
    String soql =
      'SELECT ' +
      String.join(TimeDriveSoqlProvider.unique(fields), ', ') +
      ' FROM ' +
      s.Object_Name__c +
      ' WHERE ' +
      individualField +
      ' IN :individualIds' +
      context.dateCondition(dmo, dateField, binds) +
      (String.isBlank(s.Filter__c) ? '' : ' AND (' + s.Filter__c + ')') +
      ' ORDER BY ' +
      dateField +
      ' DESC LIMIT ' +
      Math.min(context.maxRecords(), MAX_DMO_ROWS);
    try {
      List<SObject> found = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
      TimeDriveQueries.record(s.DeveloperName, 'rows', soql, found.size());
      for (SObject row : found) {
        rows.add(new TimeDriveRow(row));
      }
    } catch (Exception e) {
      TimeDriveQueries.record(s.DeveloperName, 'rows', soql);
      context.fail(s.Label, e);
    }
    return rows;
  }

  /**
   * Items per hour, day, week or month, counted in Data 360 (SQL, GROUP BY):
   * no rows come back to Apex but the counts, and no SOQL query rows are
   * used, however many engagement records there are. Periods are worked out
   * in the user's time zone, as the SOQL provider's convertTimezone() does.
   * A count that can't run (the SQL isn't accepted, the DMO isn't there)
   * throws, and the source is read as rows instead.
   *
   * @param context the request context
   * @param unit the period to count by
   * @return the count for each period that has rows
   */
  public List<TimeDriveContext.DayCount> countDays(TimeDriveContext context, String unit) {
    realModel = new Map<String, Schema.SObjectType>();
    return countDays(context, unit, realModel);
  }

  @TestVisible
  private List<TimeDriveContext.DayCount> countDays(
    TimeDriveContext context,
    String unit,
    Map<String, Schema.SObjectType> objects
  ) {
    Time_Drive_Source__mdt s = context.source;
    // A filter only SOQL reads (TODAY, LAST_N_DAYS:90, INCLUDES ...) would
    // fail in Data 360 SQL on every request: read as rows straight away.
    if (soqlOnly(s.Filter__c)) {
      return null;
    }
    if (objectIn(objects, 'ssot__Individual__dlm') == null || String.isBlank(s.Object_Name__c)) {
      throw new CountException('No Data 360.');
    }
    Schema.SObjectType dmo = objectIn(objects, s.Object_Name__c);
    if (dmo == null) {
      throw new CountException('No such data model object.');
    }
    Schema.DescribeSObjectResult describe = TimeDriveConfig.describeType(dmo);
    Map<String, Schema.SObjectField> dmoFields = TimeDriveConfig.fieldMap(describe.getName());
    context.sourceObject = s.Object_Name__c;
    context.sourceLabel = 'Data 360' + TimeDrivePlotter.SEPARATOR + describe.getLabel();
    String individualField = String.isBlank(s.Individual_Field__c) ? 'ssot__IndividualId__c' : s.Individual_Field__c;
    String dateField = context.dateField();
    for (String name : new List<String>{ s.Object_Name__c, individualField, dateField }) {
      if (!PLAIN_NAME.matcher(name).matches()) {
        throw new CountException('Not a plain name: ' + name);
      }
    }
    // Data 360's query API applies its own data space and permissions, not
    // the object and field access the row reads enforce in user mode: count
    // only what this user may read, else read as rows (in user mode, which
    // says what they can't see).
    if (!readable(describe, dmoFields, new List<String>{ individualField, dateField }, s.Filter__c)) {
      throw new CountException('Not readable by this user.');
    }
    Boolean byDay = isDate(dmoFields, dateField);

    List<String> ids = new List<String>();
    for (String id : individualIdsFor(context.contactId(), objects, context)) {
      ids.add(quoted(id));
    }
    List<String> dates = new List<String>();
    for (TimeDriveContext.Span span : context.spans()) {
      dates.add(
        '(' +
          dateField +
          ' >= ' +
          bound(span.since, byDay) +
          (span.until == null ? '' : ' AND ' + dateField + ' <= ' + bound(span.until, byDay)) +
          ')'
      );
    }
    String sql =
      'SELECT ' +
      String.join(selected(dateField, unit, byDay), ', ') +
      ', COUNT(*) AS n FROM ' +
      s.Object_Name__c +
      ' WHERE ' +
      individualField +
      ' IN (' +
      String.join(ids, ', ') +
      ') AND (' +
      String.join(dates, ' OR ') +
      ')' +
      (String.isBlank(s.Filter__c) ? '' : ' AND (' + s.Filter__c + ')') +
      ' GROUP BY ' +
      String.join(grouped(dateField, unit, byDay), ', ');

    List<TimeDriveContext.DayCount> counts = new List<TimeDriveContext.DayCount>();
    for (List<Object> row : runner().run(sql, s.Data_Space__c)) {
      counts.add(
        new TimeDriveContext.DayCount(
          String.valueOf(row[0]).left(10),
          unit == TimeDriveContext.UNIT_HOUR ? Integer.valueOf(String.valueOf(row[1])) : null,
          Integer.valueOf(String.valueOf(row[row.size() - 1]))
        )
      );
    }
    return counts;
  }

  // Whether this user may read the DMO and the fields a count uses: the
  // individual and date fields, and every field of the DMO its filter names
  // (quoted text left out, so values aren't taken for fields).
  @TestVisible
  private static Boolean readable(
    Schema.DescribeSObjectResult describe,
    Map<String, Schema.SObjectField> dmoFields,
    List<String> fields,
    String filter
  ) {
    if (!describe.isAccessible()) {
      return false;
    }
    Set<String> named = new Set<String>();
    for (String f : fields) {
      named.add(f.toLowerCase());
    }
    if (String.isNotBlank(filter)) {
      Matcher m = Pattern.compile('[A-Za-z][A-Za-z0-9_]*')
        .matcher(filter.replaceAll('\'(?:[^\'\\\\]|\\\\.)*\'', '\'\''));
      while (m.find()) {
        named.add(m.group().toLowerCase());
      }
    }
    for (String f : named) {
      Schema.SObjectField field = dmoFields.get(f);
      // Words that aren't fields (AND, IN, NULL ...) are skipped.
      if (field != null && !field.getDescribe().isAccessible()) {
        return false;
      }
    }
    return true;
  }

  // SOQL date literals (TODAY, LAST_N_DAYS:90, THIS_FISCAL_QUARTER ...),
  // INCLUDES / EXCLUDES and binds: SOQL only, not Data 360 SQL.
  private static final Pattern SOQL_ONLY = Pattern.compile(
    '(?i)\\b(YESTERDAY|TODAY|TOMORROW|(LAST|THIS|NEXT)_(WEEK|MONTH|QUARTER|YEAR|FISCAL_QUARTER|FISCAL_YEAR)|(LAST|NEXT)_90_DAYS|(LAST|NEXT)_N_\\w+|N_\\w+_AGO)\\b|(?i)\\b(INCLUDES|EXCLUDES)\\s*\\(|:\\s*[A-Za-z_]'
  );

  // The filter, its quoted text left out, has SOQL that Data 360 SQL
  // doesn't read.
  @TestVisible
  private static Boolean soqlOnly(String filter) {
    if (String.isBlank(filter)) {
      return false;
    }
    String unquoted = filter.replaceAll('\'(?:[^\'\\\\]|\\\\.)*\'', '\'\'');
    return SOQL_ONLY.matcher(unquoted).find();
  }

  // The engagement time in the user's time zone; a day is the same day
  // everywhere, so a Date field is taken as it is.
  private static String local(String dateField, Boolean byDay) {
    if (byDay) {
      return 'CAST(' + dateField + ' AS TIMESTAMP)';
    }
    return '(CAST(' +
      dateField +
      ' AS TIMESTAMP WITH TIME ZONE) AT TIME ZONE ' +
      quoted(UserInfo.getTimeZone().getID()) +
      ')';
  }

  // The period's first day (as text, yyyy-MM-dd) and, by hour, the hour.
  private static List<String> grouped(String dateField, String unit, Boolean byDay) {
    String at = local(dateField, byDay);
    String first;
    if (unit == TimeDriveContext.UNIT_WEEK) {
      // Weeks from 1 January, as SOQL's WEEK_IN_YEAR.
      first =
        'date_trunc(\'year\', ' +
        at +
        ') + CAST(floor((EXTRACT(DOY FROM ' +
        at +
        ') - 1) / 7) * 7 AS INTEGER) * INTERVAL \'1\' DAY';
    } else if (unit == TimeDriveContext.UNIT_MONTH) {
      first = 'date_trunc(\'month\', ' + at + ')';
    } else {
      first = 'date_trunc(\'day\', ' + at + ')';
    }
    List<String> groups = new List<String>{ 'to_char(' + first + ', \'YYYY-MM-DD\')' };
    if (unit == TimeDriveContext.UNIT_HOUR) {
      groups.add('CAST(EXTRACT(HOUR FROM ' + at + ') AS INTEGER)');
    }
    return groups;
  }

  private static List<String> selected(String dateField, String unit, Boolean byDay) {
    List<String> groups = grouped(dateField, unit, byDay);
    List<String> result = new List<String>();
    for (Integer i = 0; i < groups.size(); i++) {
      result.add(groups[i] + ' AS g' + i);
    }
    return result;
  }

  private static String quoted(String value) {
    return '\'' + value.replace('\'', '\'\'') + '\'';
  }

  // A bound as a date literal (the user's day) or a UTC timestamp literal.
  @TestVisible
  private static String bound(Datetime at, Boolean byDay) {
    return byDay ? 'DATE ' + quoted(at.format('yyyy-MM-dd')) : stamp(at);
  }

  @TestVisible
  private static Boolean isDate(Map<String, Schema.SObjectField> fields, String name) {
    Schema.SObjectField f = fields.get(name.toLowerCase());
    return f != null && f.getDescribe().getType() == Schema.DisplayType.DATE;
  }

  /**
   * Data 360's standard DMOs key rows by ssot__Id__c; a custom one may have
   * only Id. With no Id Field set, the one the DMO has is used.
   *
   * @param context the request context
   * @param fields the DMO's fields by lower-case name
   * @return the source, with its Id field set to the one the DMO has when none was set
   */
  @TestVisible
  private static Time_Drive_Source__mdt fitIdField(TimeDriveContext context, Map<String, Schema.SObjectField> fields) {
    Time_Drive_Source__mdt s = context.source;
    if (String.isNotBlank(s.Id_Field__c) || fields.containsKey(context.idField().toLowerCase())) {
      return s;
    }
    s = s.clone(true);
    s.Id_Field__c = 'Id';
    context.source = s;
    return s;
  }

  // An instant as a UTC timestamp literal.
  private static String stamp(Datetime at) {
    return 'TIMESTAMP ' + quoted(at.formatGmt('yyyy-MM-dd HH:mm:ss.SSS'));
  }

  /** Thrown when a count cannot be run. */
  public class CountException extends Exception {
  }

  /**
   * Runs Data 360 SQL; each row is its columns' values, in order. The org's
   * runner is TimeDriveData360SqlRunner (force-app-data360), found by name.
   */
  @NamespaceAccessible
  public interface SqlRunner {
    /**
     * Runs a Data 360 SQL query.
     *
     * @param sql the SQL to run
     * @param dataSpace the data space, blank for the default one
     * @return the result rows
     */
    List<List<Object>> run(String sql, String dataSpace);
  }

  /**
   * Data 360's data model objects by name. Apex's global describe doesn't
   * list them in every org; TimeDriveData360Catalog (force-app-data360) asks
   * Data 360, found by name.
   */
  @NamespaceAccessible
  public interface Catalog {
    /**
     * Lists the DMOs in a data space.
     *
     * @param dataSpace the data space, blank for the default one
     * @return the DMO API names
     */
    List<String> dmoNames(String dataSpace);

    /**
     * The Profile DMOs in a data space: who someone is, not what they did.
     *
     * @param dataSpace the data space, blank for the default one
     * @return the API names of the Profile DMOs
     */
    Set<String> profileDmoNames(String dataSpace);
  }

  // A data model object by name: from the model given (the org's, or a
  // test's), else described by name (DMOs can be, though the global
  // describe may not list them).
  @TestVisible
  private static Schema.SObjectType objectIn(Map<String, Schema.SObjectType> objects, String name) {
    if (String.isBlank(name)) {
      return null;
    }
    Schema.SObjectType t = objects.get(name.toLowerCase());
    return t != null || objects !== realModel ? t : TimeDriveConfig.sObjectType(name);
  }

  /**
   * Data 360's DMO names in a data space (blank: the default), from
   * TimeDriveData360Catalog where force-app-data360 is deployed; none if it
   * isn't, or Data 360 couldn't be asked.
   *
   * @param dataSpace the data space, blank for the default one
   * @return the DMO API names, none when they cannot be listed
   */
  public static List<String> dmoNames(String dataSpace) {
    if (testDmoNames != null) {
      return testDmoNames;
    }
    try {
      Catalog catalog = catalog();
      if (catalog != null) {
        return catalog.dmoNames(dataSpace);
      }
    } catch (Exception e) {
      // Data 360 couldn't be asked.
    }
    return new List<String>();
  }

  /**
   * Data 360's Profile DMOs in a data space (blank: the default), which
   * describe people rather than what they did, so Setup doesn't offer them;
   * none when Data 360 couldn't be asked.
   *
   * @param dataSpace the data space, blank for the default one
   * @return the API names of the Profile DMOs
   */
  public static Set<String> profileDmoNames(String dataSpace) {
    if (testProfileDmoNames != null) {
      return testProfileDmoNames;
    }
    try {
      Catalog catalog = catalog();
      if (catalog != null) {
        return catalog.profileDmoNames(dataSpace);
      }
    } catch (Exception e) {
      // Data 360 couldn't be asked.
    }
    return new Set<String>();
  }

  // TimeDriveData360Catalog, where force-app-data360 is deployed.
  private static Catalog catalog() {
    Type catalogType = Type.forName(TimeDriveConfig.NAMESPACE, 'TimeDriveData360Catalog');
    Object found = catalogType == null ? null : catalogType.newInstance();
    return found instanceof Catalog ? (Catalog) found : null;
  }

  // The identity link DMO: the one set, else the ruleset's in the source's
  // data space (identity resolution runs per data space).
  @TestVisible
  private static String linkObjectIn(Map<String, Schema.SObjectType> objects, String configured, String dataSpace) {
    if (objectIn(objects, configured) != null) {
      return configured;
    }
    // Which ruleset link object a data space has: Data 360's metadata is
    // asked at most once every 15 minutes.
    String cacheKey = TimeDriveCache.key(new List<String>{ 'link', dataSpace });
    Object kept = TimeDriveCache.get(cacheKey);
    if (kept instanceof String && objectIn(objects, (String) kept) != null) {
      return (String) kept;
    }
    List<String> rulesets = new List<String>();
    for (String name : dmoNames(dataSpace)) {
      if (RULESET_LINK.matcher(name).matches() && objectIn(objects, name) != null) {
        rulesets.add(name);
      }
    }
    rulesets.sort();
    if (rulesets.isEmpty()) {
      return null;
    }
    TimeDriveCache.put(cacheKey, rulesets[0]);
    return rulesets[0];
  }

  /**
   * Whether the Data 360 add-on (force-app-data360) is deployed: its runner
   * and catalog are found by name and are what this class expects.
   *
   * @return true when the add-on is deployed
   */
  public static Boolean addOnInstalled() {
    if (sqlRunner != null || testDmoNames != null) {
      return true;
    }
    try {
      Type runnerType = Type.forName(TimeDriveConfig.NAMESPACE, SQL_RUNNER_CLASS);
      Type catalogType = Type.forName(TimeDriveConfig.NAMESPACE, 'TimeDriveData360Catalog');
      return runnerType != null &&
        catalogType != null &&
        runnerType.newInstance() instanceof SqlRunner &&
        catalogType.newInstance() instanceof Catalog;
    } catch (Exception e) {
      return false;
    }
  }

  private static SqlRunner runner() {
    if (sqlRunner == null) {
      Type runnerType = Type.forName(TimeDriveConfig.NAMESPACE, SQL_RUNNER_CLASS);
      Object instance = runnerType == null ? null : runnerType.newInstance();
      if (!(instance instanceof SqlRunner)) {
        throw new CountException(SQL_RUNNER_CLASS + ' isn\'t deployed (force-app-data360).');
      }
      sqlRunner = (SqlRunner) instance;
    }
    return sqlRunner;
  }

  /**
   * The Contact's own Individual Id, its Unified Individual's Id, and every
   * source Individual merged into the same Unified Individual.
   *
   * @param contactId the Contact's Id
   * @param objects sObject types by name
   * @param context the request context
   * @return the Individual Ids
   */
  @TestVisible
  private static Set<String> individualIdsFor(
    Id contactId,
    Map<String, Schema.SObjectType> objects,
    TimeDriveContext context
  ) {
    List<String> warnings = context.warnings;
    String dataSpace = context.source?.Data_Space__c;
    String memo = contactId + '|' + dataSpace;
    if (individualIdsByRecord.containsKey(memo)) {
      return individualIdsByRecord.get(memo);
    }
    Set<String> ids = new Set<String>{ String.valueOf(contactId), String.valueOf(contactId).left(15) };
    individualIdsByRecord.put(memo, ids);
    // An Account page: the object's field holds the Account's Id itself
    // (identity links are for individuals; unified accounts aren't followed).
    if (context.parentObject == 'Account') {
      return ids;
    }
    // Looked up in the last 15 minutes: identity resolution rarely changes.
    // Kept for this user only: the lookup ran as them (user mode), so someone
    // who can't read the identity links never gets another person's answer.
    String cacheKey = TimeDriveCache.key(new List<String>{ 'ids', UserInfo.getUserId(), contactId, dataSpace });
    Set<String> kept = keptIds(TimeDriveCache.get(cacheKey));
    if (kept != null) {
      ids.addAll(kept);
      return ids;
    }

    Time_Drive_Setting__mdt setting = setting();
    String linkObject = linkObjectIn(objects, setting.Identity_Link_Object__c, dataSpace);
    String sourceField = setting.Link_Source_Field__c;
    String unifiedField = setting.Link_Unified_Field__c;
    if (linkObject == null) {
      warnings.add(
        String.format(
          Label.Time_Drive_Server_No_Identity_Link,
          new List<String>{ String.valueOf(setting.Identity_Link_Object__c) }
        )
      );
      return ids;
    }
    try {
      Map<String, Object> binds = new Map<String, Object>{ 'sourceIds' => new List<String>(ids) };
      Set<String> unifiedIds = new Set<String>();
      for (
        SObject row : Database.queryWithBinds(
          'SELECT ' + unifiedField + ' FROM ' + linkObject + ' WHERE ' + sourceField + ' IN :sourceIds LIMIT 10',
          binds,
          AccessLevel.USER_MODE
        )
      ) {
        unifiedIds.add((String) row.get(unifiedField));
      }
      unifiedIds.remove(null);
      if (!unifiedIds.isEmpty()) {
        // DMOs keyed by the unified profile hold the Unified Id.
        ids.addAll(unifiedIds);
        binds = new Map<String, Object>{ 'unifiedIds' => new List<String>(unifiedIds) };
        for (
          SObject row : Database.queryWithBinds(
            'SELECT ' + sourceField + ' FROM ' + linkObject + ' WHERE ' + unifiedField + ' IN :unifiedIds LIMIT 200',
            binds,
            AccessLevel.USER_MODE
          )
        ) {
          ids.add((String) row.get(sourceField));
        }
      }
      ids.remove(null);
      // Kept only once the links were read without a failure.
      TimeDriveCache.put(cacheKey, ids);
    } catch (Exception e) {
      context.fail(Label.Time_Drive_Server_Identity_Links, e);
    }
    return ids;
  }

  // A cache entry as Ids, or null if it isn't one.
  private static Set<String> keptIds(Object kept) {
    try {
      return kept == null ? null : (Set<String>) kept;
    } catch (TypeException e) {
      return null;
    }
  }

  // The Default Time Drive Setting, with the standard names filled in.
  private static Time_Drive_Setting__mdt setting() {
    Time_Drive_Setting__mdt found = testSetting != null ? testSetting : Time_Drive_Setting__mdt.getInstance('Default');
    Time_Drive_Setting__mdt s = found == null ? new Time_Drive_Setting__mdt() : found.clone();
    if (String.isBlank(s.Identity_Link_Object__c)) {
      s.Identity_Link_Object__c = 'IndividualIdentityLink__dlm';
    }
    if (String.isBlank(s.Link_Source_Field__c)) {
      s.Link_Source_Field__c = 'SourceRecordId__c';
    }
    if (String.isBlank(s.Link_Unified_Field__c)) {
      s.Link_Unified_Field__c = 'UnifiedRecordId__c';
    }
    return s;
  }
}
