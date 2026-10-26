// Two records two years apart, on a Contact of their own, to see how the
// timeline handles a long quiet stretch. Set the component's History to 2
// years or more to plot the older one; the default is the last 6 months.
// Everything is tagged "[Two-year sample]".
Contact customer = new Contact(
  FirstName = 'Riley',
  LastName = 'Span',
  Description = '[Two-year sample] Two tasks two years apart.'
);
insert customer;
Date today = Date.today();
insert new List<Task>{
  new Task(
    WhoId = customer.Id,
    Subject = '[Two-year sample] Welcome call',
    ActivityDate = today.addYears(-2).addDays(-3),
    Status = 'Completed'
  ),
  new Task(
    WhoId = customer.Id,
    Subject = '[Two-year sample] Check-in call',
    ActivityDate = today,
    Status = 'Completed'
  )
};
System.debug('SEEDED ' + customer.Id + ' start date to use: ' + String.valueOf(today.addYears(-2).addDays(-10)));
