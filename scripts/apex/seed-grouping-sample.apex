// 100 records on one day (today) for one Contact, to test busy-day grouping:
// 60 Cases and 40 Tasks. Set contactId, or it uses the newest Contact.
// Tagged '[Grouping sample]' for cleanup.
Id contactId = [SELECT Id FROM Contact ORDER BY CreatedDate DESC LIMIT 1].Id;
List<String> subjects = new List<String>{ 'Late delivery', 'Missing item', 'Billing question', 'Login issue', 'Refund request', 'Promo code not applied' };
List<Case> cases = new List<Case>();
for (Integer i = 0; i < 60; i++) {
  cases.add(new Case(
    ContactId = contactId,
    Subject = '[Grouping sample] ' + subjects[Math.mod(i, subjects.size())] + ' #' + (i + 1),
    Status = Math.mod(i, 3) == 0 ? 'Closed' : 'New',
    Origin = Math.mod(i, 2) == 0 ? 'Web' : 'Phone'
  ));
}
insert cases;
List<Task> tasks = new List<Task>();
for (Integer i = 0; i < 40; i++) {
  tasks.add(new Task(
    WhoId = contactId,
    Subject = '[Grouping sample] Follow-up ' + (i + 1),
    ActivityDate = Date.today(),
    Status = 'Completed'
  ));
}
insert tasks;
System.debug('SEED cases=' + cases.size() + ' tasks=' + tasks.size());
