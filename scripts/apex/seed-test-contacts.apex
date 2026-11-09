// Four Contacts to try the timeline at different volumes. Each gets the same
// number of Tasks, Events, Cases and Opportunities, spread evenly over the
// years before today:
//   Test Empty      no records
//   Test OneYear    50 of each over 1 year   (200 records)
//   Test TwoYears   150 of each over 2 years (600 records)
//   Test FiveYears  500 of each over 5 years (2,000 records)
// Run it again and the earlier run is removed first. Set cleanOnly to remove
// the data and stop. Tagged by "[Test data]" in Subject and Name, and by the
// Contacts' email domain, so nothing else is touched.
//
// Cases are dated by CreatedDate, which Apex can only set when the org allows
// it (Setup > User Interface > "Enable Set Audit Fields upon Record Creation",
// and the "Set Audit Fields upon Record Creation" permission). Without it the
// Cases are created today and the debug log says so.
//
// Run: sf apex run --file scripts/apex/seed-test-contacts.apex --target-org <org>
final String TAG = '[Test data]';
final String EMAIL_DOMAIN = '@timedrive-test.example.com';
Boolean cleanOnly = false;

List<String> lastNames = new List<String>{ 'Empty', 'OneYear', 'TwoYears', 'FiveYears' };
List<Integer> perType = new List<Integer>{ 0, 50, 150, 500 };
List<Integer> spanDays = new List<Integer>{ 0, 365, 730, 1826 };

// ---- clear an earlier run --------------------------------------------------
String tagged = TAG + '%';
delete [SELECT Id FROM Opportunity WHERE Name LIKE :tagged];
delete [SELECT Id FROM Case WHERE Subject LIKE :tagged];
delete [SELECT Id FROM Task WHERE Subject LIKE :tagged];
delete [SELECT Id FROM Event WHERE Subject LIKE :tagged];
String emails = '%' + EMAIL_DOMAIN;
delete [SELECT Id FROM Contact WHERE Email LIKE :emails];
System.debug('TEST DATA cleared');

if (!cleanOnly) {

  // ---- the Contacts ------------------------------------------------------------
  List<Contact> contacts = new List<Contact>();
  for (String lastName : lastNames) {
    contacts.add(
      new Contact(
        FirstName = 'Test',
        LastName = lastName,
        Email = lastName.toLowerCase() + EMAIL_DOMAIN,
        Description = TAG + ' timeline volume test'
      )
    );
  }
  insert contacts;
  Map<Id, String> lastNameById = new Map<Id, String>();
  for (Contact c : contacts) {
    lastNameById.put(c.Id, c.LastName);
  }

  // ---- their records -------------------------------------------------------------
  List<String> stages = new List<String>{ 'Prospecting', 'Qualification', 'Proposal/Price Quote', 'Closed Won', 'Closed Lost' };
  List<String> statuses = new List<String>{ 'New', 'Working', 'Escalated', 'Closed' };
  List<String> origins = new List<String>{ 'Web', 'Phone', 'Email' };

  List<Task> tasks = new List<Task>();
  List<Event> events = new List<Event>();
  List<Opportunity> opps = new List<Opportunity>();
  List<Id> oppContact = new List<Id>();
  List<Id> caseContact = new List<Id>();
  List<Integer> caseAgo = new List<Integer>();
  List<Integer> caseSeq = new List<Integer>();
  Date today = Date.today();

  for (Integer c = 0; c < contacts.size(); c++) {
    Id contactId = contacts[c].Id;
    Integer n = perType[c];
    for (Integer j = 0; j < n; j++) {
      // Evenly through the span: record j sits in the middle of its slice.
      Integer ago = (spanDays[c] * (2 * j + 1)) / (2 * n);
      Date day = today.addDays(-ago);
      Datetime at = Datetime.newInstance(day, Time.newInstance(8 + Math.mod(j, 9), 0, 0, 0));
      String label = TAG + ' ' + lastNames[c] + ' ' + (j + 1);

      tasks.add(
        new Task(
          WhoId = contactId,
          Subject = label + ' follow-up',
          ActivityDate = day,
          Status = 'Completed',
          Priority = 'Normal'
        )
      );
      events.add(
        new Event(
          WhoId = contactId,
          Subject = label + ' meeting',
          StartDateTime = at,
          EndDateTime = at.addMinutes(30),
          Location = 'Room ' + (1 + Math.mod(j, 5))
        )
      );
      opps.add(
        new Opportunity(
          Name = label + ' deal',
          CloseDate = day,
          StageName = stages[Math.mod(j, stages.size())],
          Amount = 1000 + Math.mod(j, 50) * 100
        )
      );
      oppContact.add(contactId);
      caseContact.add(contactId);
      caseAgo.add(ago);
      caseSeq.add(j);
    }
  }

  insert tasks;
  insert events;
  insert opps;
  List<OpportunityContactRole> roles = new List<OpportunityContactRole>();
  for (Integer i = 0; i < opps.size(); i++) {
    roles.add(new OpportunityContactRole(OpportunityId = opps[i].Id, ContactId = oppContact[i], Role = 'Decision Maker', IsPrimary = true));
  }
  insert roles;

  // Cases: dated first; if the org won't take a CreatedDate, created today.
  Boolean casesDated = false;
  Integer casesMade = 0;
  for (Boolean dated : new List<Boolean>{ true, false }) {
    try {
      List<Case> cases = new List<Case>();
      for (Integer i = 0; i < caseContact.size(); i++) {
        Case record = new Case(
          ContactId = caseContact[i],
          Subject = TAG + ' case ' + (caseSeq[i] + 1) + ' (' + lastNameById.get(caseContact[i]) + ')',
          Status = statuses[Math.mod(caseSeq[i], statuses.size())],
          Origin = origins[Math.mod(caseSeq[i], origins.size())]
        );
        if (dated) {
          record.put('CreatedDate', Datetime.now().addDays(-caseAgo[i]));
        }
        cases.add(record);
      }
      insert cases;
      casesDated = dated;
      casesMade = cases.size();
      break;
    } catch (Exception e) {
      System.debug(LoggingLevel.WARN, 'TEST DATA cases ' + (dated ? 'with CreatedDate' : 'without') + ' failed: ' + e.getMessage());
    }
  }

  for (Integer c = 0; c < contacts.size(); c++) {
    System.debug('TEST DATA ' + lastNames[c] + ' ' + contacts[c].Id + ': ' + (perType[c] * 4) + ' records over ' + spanDays[c] + ' days');
  }
  System.debug('TEST DATA tasks=' + tasks.size() + ' events=' + events.size() + ' opps=' + opps.size() + ' cases=' + casesMade
    + (casesDated ? '' : ' (Cases NOT backdated: the org does not allow setting CreatedDate)'));
}
