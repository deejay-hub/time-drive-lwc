/**
 * An Apex source for an Account page: the products on every opportunity of
 * the account (Account › Opportunity › Opportunity Product), dated by the
 * opportunity's close date. Two steps down from the page, further than the
 * setup wizard's lookups and junctions reach.
 *
 * Each row is an Opportunity Product. Time Drive Setup asks an Apex source
 * for no date, title, subtitle or click, so the class fills them in: each
 * product on its opportunity's close date (Opportunity.CloseDate), titled
 * {Product2.Name}, under {Opportunity.Name}, a click opening the opportunity
 * product itself (its Id). A source that sets its own keeps them. Its detail fields,
 * typed in Setup's last step, are field paths such as Quantity, TotalPrice or
 * Opportunity.StageName; whatever the source names is read with the rest.
 */
public with sharing class TimeDriveOpportunityProducts implements TimeDriveRowProvider {
  private static final String DATE_FIELD = 'Opportunity.CloseDate';
  // Read whatever the source shows; its own fields are added to these.
  private static final List<String> FIELDS = new List<String>{
    'Id',
    'Quantity',
    'UnitPrice',
    'TotalPrice',
    'Product2.Name',
    'Product2.ProductCode',
    'Product2.Family',
    'OpportunityId',
    'Opportunity.Name',
    'Opportunity.StageName',
    DATE_FIELD
  };
  // A field the source names, as a field path and nothing else.
  private static final Pattern FIELD_PATH = Pattern.compile('[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)*');

  /**
   * The account's opportunity products in the window, newest first.
   *
   * @param context the request context
   * @return a row for each opportunity product; none off an account page
   */
  public List<TimeDriveRow> getRows(TimeDriveContext context) {
    List<TimeDriveRow> rows = new List<TimeDriveRow>();
    if (context.recordId == null || context.recordId.getSObjectType() != Account.SObjectType) {
      return rows;
    }
    fillBlanks(context);
    Map<String, Object> binds = new Map<String, Object>{
      'accountId' => context.recordId,
      'most' => context.maxRecords()
    };
    String soql =
      'SELECT ' +
      String.join(fieldsFor(context), ', ') +
      ' FROM OpportunityLineItem WHERE Opportunity.AccountId = :accountId' +
      within(context.spans(), binds) +
      ' ORDER BY ' +
      DATE_FIELD +
      ' DESC, Id DESC LIMIT :most';
    for (SObject item : Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)) {
      rows.add(new TimeDriveRow(item));
    }
    return rows;
  }

  // Time Drive Setup asks an Apex source for no date, title, subtitle or click: what the
  // source leaves blank, the products fill in (each on its opportunity's close date, named
  // for its product, under its opportunity, opening the opportunity product).
  @TestVisible
  private static void fillBlanks(TimeDriveContext context) {
    Time_Drive_Source__mdt s = context.source == null ? new Time_Drive_Source__mdt() : context.source.clone(true);
    if (String.isBlank(s.Date_Field__c)) {
      s.Date_Field__c = DATE_FIELD;
    }
    if (String.isBlank(s.Title__c)) {
      s.Title__c = '{Product2.Name}';
    }
    if (String.isBlank(s.Subtitle__c)) {
      s.Subtitle__c = '{Opportunity.Name}';
    }
    if (String.isBlank(s.Record_Id_Field__c)) {
      s.Record_Id_Field__c = 'Id';
    }
    context.source = s;
  }

  // The fields read: the usual ones, and those the source's title, subtitle and details name.
  private static List<String> fieldsFor(TimeDriveContext context) {
    Set<String> names = new Set<String>();
    List<String> out = new List<String>();
    List<String> wanted = new List<String>(FIELDS);
    wanted.addAll(TimeDrivePlotter.tokens(context.source?.Title__c));
    wanted.addAll(TimeDrivePlotter.tokens(context.source?.Subtitle__c));
    for (Time_Drive_Detail_Field__mdt d : context.detailFields()) {
      wanted.add(d.Field__c);
    }
    for (String name : wanted) {
      if (String.isNotBlank(name) && FIELD_PATH.matcher(name).matches() && names.add(name.toLowerCase())) {
        out.add(name);
      }
    }
    return out;
  }

  // The spans as conditions on the close date (a Date, so compared with days).
  private static String within(List<TimeDriveController.TimeWindow> spans, Map<String, Object> binds) {
    List<String> out = new List<String>();
    for (Integer i = 0; i < spans.size(); i++) {
      List<String> bounds = new List<String>();
      if (spans[i].since != null) {
        binds.put('since' + i, spans[i].since.date());
        bounds.add(DATE_FIELD + ' >= :since' + i);
      }
      if (spans[i].until != null) {
        binds.put('until' + i, spans[i].until.date());
        bounds.add(DATE_FIELD + ' <= :until' + i);
      }
      if (bounds.isEmpty()) {
        // One span is the whole history: no condition at all.
        return '';
      }
      out.add('(' + String.join(bounds, ' AND ') + ')');
    }
    return out.isEmpty() ? '' : ' AND (' + String.join(out, ' OR ') + ')';
  }
}
