// Sample Cases and Opportunities for Time Drive.
// Every record is tagged '[Timeline sample]' in Description for cleanup.
final String TAG = '[Timeline sample] ';
List<AggregateResult> top = [
  SELECT ContactId c, COUNT(Id) n FROM Case
  WHERE ContactId != null GROUP BY ContactId ORDER BY COUNT(Id) DESC LIMIT 3
];
List<Id> ids = new List<Id>();
for (AggregateResult r : top) ids.add((Id) r.get('c'));
Map<Id, Contact> contacts = new Map<Id, Contact>([SELECT Id, Name, AccountId FROM Contact WHERE Id IN :ids]);

// Opportunities need an Account: give any Contact without one a sample Account.
List<Account> newAccounts = new List<Account>();
for (Contact c : contacts.values()) {
  if (c.AccountId == null) newAccounts.add(new Account(Name = c.Name + ' Office', Description = TAG + 'for ' + c.Name));
}
insert newAccounts;
Integer a = 0;
List<Contact> linked = new List<Contact>();
for (Contact c : contacts.values()) {
  if (c.AccountId == null) {
    c.AccountId = newAccounts[a++].Id;
    linked.add(c);
  }
}
update linked;

Contact first = contacts.get(ids[0]);
Contact second = contacts.get(ids.size() > 1 ? ids[1] : ids[0]);
Contact third = contacts.get(ids.size() > 2 ? ids[2] : ids[0]);

List<Case> cases = new List<Case>{
  new Case(ContactId = first.Id, Subject = 'Late delivery on Friday order', Status = 'Closed', Origin = 'Web', Reason = 'Performance', Description = TAG + 'Refunded the delivery fee'),
  new Case(ContactId = first.Id, Subject = 'Missing item in shipment', Status = 'Working', Origin = 'Phone', Description = TAG + 'Supplier contacted'),
  new Case(ContactId = second.Id, Subject = 'Promo code not applied', Status = 'Closed', Origin = 'Email', Description = TAG + 'Credit issued')
};
insert cases;

List<Opportunity> opps = new List<Opportunity>{
  new Opportunity(Name = 'Office lunches 2027', AccountId = first.AccountId, StageName = 'Prospecting', CloseDate = Date.today().addDays(45), Amount = 12000, Description = TAG + 'Business catering'),
  new Opportunity(Name = 'Holiday party catering', AccountId = third.AccountId, StageName = 'Closed Won', CloseDate = Date.today().addDays(-12), Amount = 3500, Description = TAG + 'Business catering')
};
insert opps;
insert new List<OpportunityContactRole>{
  new OpportunityContactRole(OpportunityId = opps[0].Id, ContactId = first.Id, Role = 'Decision Maker', IsPrimary = true),
  new OpportunityContactRole(OpportunityId = opps[1].Id, ContactId = third.Id, Role = 'Business User', IsPrimary = true)
};

System.debug('SEED first=' + first.Name + ' ' + first.Id + ' | second=' + second.Name + ' ' + second.Id + ' | third=' + third.Name + ' ' + third.Id);
System.debug('SEED cases=' + cases.size() + ' opps=' + opps.size() + ' accounts=' + newAccounts.size());
