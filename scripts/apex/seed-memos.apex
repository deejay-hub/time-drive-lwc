// Sample memos for the TD contacts: TD Busy 12 over the last year, TD Year 6,
// TD Light 2 (the last month), TD Empty none. Each memo has 2-6 items within
// a few days of it; statuses mixed, about one in five flagged. A fixed
// pattern, so a rerun gives the same picture (it replaces the old memos).
Map<String, Contact> contacts = new Map<String, Contact>();
for (Contact c : [SELECT Id, LastName FROM Contact WHERE FirstName = 'TD' AND LastName IN ('Light', 'Year', 'Busy')]) {
  contacts.put(c.LastName, c);
}
delete [SELECT Id FROM Memo__c WHERE Contact__c IN :new Map<Id, Contact>(contacts.values()).keySet()];

List<String> topics = new List<String>{ 'Kick-off', 'Quarterly review', 'Renewal prep', 'Escalation', 'Site visit', 'Pricing call' };
List<String> items = new List<String>{ 'Agree scope', 'Send the plan', 'Chase sign-off', 'Book follow-up', 'Share notes', 'Confirm budget' };
List<String> statuses = new List<String>{ 'Done', 'Done', 'In Progress', 'Open' };
// [contact, memos, days back the first is, days between memos]
List<List<Object>> plans = new List<List<Object>>{
  new List<Object>{ 'Busy', 12, 350, 29 },
  new List<Object>{ 'Year', 6, 330, 55 },
  new List<Object>{ 'Light', 2, 25, 12 }
};
List<Memo__c> memos = new List<Memo__c>();
for (List<Object> p : plans) {
  Contact c = contacts.get((String) p[0]);
  for (Integer i = 0; i < (Integer) p[1]; i++) {
    Date day = Date.today().addDays(-((Integer) p[2]) + i * (Integer) p[3]);
    memos.add(new Memo__c(
      Name = topics[Math.mod(i, topics.size())] + ' ' + (i + 1),
      Contact__c = c.Id,
      Memo_Date__c = day,
      Description__c = 'Notes from the ' + topics[Math.mod(i, topics.size())].toLowerCase() + ' with ' + p[0] + '.'
    ));
  }
}
insert memos;

List<Memo_Item__c> rows = new List<Memo_Item__c>();
Integer n = 0;
for (Memo__c m : memos) {
  Integer count = 2 + Math.mod(n, 5);
  for (Integer j = 0; j < count; j++) {
    Datetime at = Datetime.newInstance(m.Memo_Date__c.addDays(j - 1), Time.newInstance(9 + Math.mod(n + j, 8), 15 * Math.mod(j, 4), 0, 0));
    if (at > Datetime.now()) {
      at = Datetime.now().addHours(-(j + 1));
    }
    rows.add(new Memo_Item__c(
      Memo__c = m.Id,
      Description__c = items[Math.mod(n + j, items.size())],
      Status__c = statuses[Math.mod(n + j, statuses.size())],
      Flagged__c = Math.mod(n * 3 + j, 5) == 0,
      Occurred_At__c = at
    ));
  }
  n++;
}
insert rows;
for (Contact c : contacts.values()) {
  System.debug('TD ' + c.LastName + ': ' + [SELECT COUNT() FROM Memo__c WHERE Contact__c = :c.Id] + ' memos, ' + [SELECT COUNT() FROM Memo_Item__c WHERE Memo__r.Contact__c = :c.Id] + ' items, ' + [SELECT COUNT() FROM Memo_Item__c WHERE Memo__r.Contact__c = :c.Id AND Flagged__c = true] + ' flagged');
}
