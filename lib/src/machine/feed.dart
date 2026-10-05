/// The cameras the Machine can watch through.
enum Feed {
  rear('FEED 01 // REAR'),
  front('FEED 02 // FRONT'),
  tele('FEED 03 // TELE');

  const Feed(this.label);

  final String label;
}
